import AppKit
import Foundation

actor CodexProvider {
    static let shared = CodexProvider()

    func accountStatus() async throws -> String {
        let session = try await connectedSession()
        defer { session.stop() }
        let result = try await session.request(method: "account/read", params: ["refreshToken": false])
        return Self.accountDescription(result)
    }

    func availableModels() async throws -> [String] {
        let session = try await connectedSession()
        defer { session.stop() }

        var names: [String] = []
        var seen = Set<String>()
        var cursor: String?

        repeat {
            var params: [String: Any] = ["limit": 100, "includeHidden": false]
            if let cursor { params["cursor"] = cursor }
            let result = try await session.request(method: "model/list", params: params)
            let models = result["data"] as? [[String: Any]] ?? []
            for model in models {
                guard let name = model["model"] as? String, !name.isEmpty else { continue }
                if seen.insert(name).inserted { names.append(name) }
            }
            cursor = result["nextCursor"] as? String
        } while cursor != nil

        return names
    }

    func signIn() async throws -> String {
        let session = try await connectedSession()
        defer { session.stop() }

        let current = try await session.request(method: "account/read", params: ["refreshToken": true])
        if let account = current["account"] as? [String: Any] {
            return Self.accountDescription(["account": account])
        }

        let login = try await session.request(
            method: "account/login/start",
            params: ["type": "chatgpt", "useHostedLoginSuccessPage": true, "appBrand": "codex"]
        )
        guard let authURL = login["authUrl"] as? String, let url = URL(string: authURL) else {
            throw LLMError.codex("Codex did not return a sign-in URL.")
        }
        _ = await MainActor.run { NSWorkspace.shared.open(url) }

        for await event in session.notifications {
            guard event["method"] as? String == "account/login/completed",
                  let params = event["params"] as? [String: Any] else { continue }
            if params["success"] as? Bool == true {
                return "Connected with ChatGPT"
            }
            throw LLMError.codex(params["error"] as? String ?? "Codex sign-in failed.")
        }
        throw LLMError.codex("Codex stopped before sign-in completed.")
    }

    func answer(messages: [ConversationMessage], systemPrompt: String, model: String) async throws -> String {
        let session = try await connectedSession()
        defer { session.stop() }

        let account = try await session.request(method: "account/read", params: ["refreshToken": false])
        if account["account"] is NSNull || account["account"] == nil {
            throw LLMError.codex("Connect OpenAI Codex in Settings first.")
        }

        let threadResult = try await session.request(
            method: "thread/start",
            params: [
                "model": model,
                "approvalPolicy": "never",
                "sandbox": "read-only",
                "serviceName": "kvartz_quick_query"
            ]
        )
        guard let thread = threadResult["thread"] as? [String: Any],
              let threadID = thread["id"] as? String else {
            throw LLMError.codex("Codex did not start a query thread.")
        }

        let transcript = messages.map { message in
            let label = message.role == .assistant ? "Assistant" : "User"
            let attachmentList = message.attachments
                .map { "[Attached image: \($0.name)]" }
                .joined(separator: "\n")
            return ["\(label):", message.content, attachmentList]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }.joined(separator: "\n\n")
        let prompt = "\(systemPrompt)\n\nConversation:\n\(transcript)"
        let images = messages.flatMap(\.attachments).map { attachment in
            ["type": "image", "url": attachment.dataURL]
        }
        _ = try await session.request(
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [["type": "text", "text": prompt]] + images,
                "model": model,
                "effort": "low",
                "approvalPolicy": "never",
                "sandboxPolicy": ["type": "readOnly"]
            ]
        )

        var output = ""
        for await event in session.notifications {
            let method = event["method"] as? String
            let params = event["params"] as? [String: Any]
            if method == "item/agentMessage/delta", let delta = params?["delta"] as? String {
                output += delta
            } else if method == "item/completed", output.isEmpty,
                      let item = params?["item"] as? [String: Any], item["type"] as? String == "agentMessage" {
                output = item["text"] as? String ?? ""
            } else if method == "turn/completed" {
                let turn = params?["turn"] as? [String: Any]
                if turn?["status"] as? String == "failed" {
                    let error = turn?["error"] as? [String: Any]
                    throw LLMError.codex(error?["message"] as? String ?? "Codex query failed.")
                }
                break
            }
        }

        guard !output.isEmpty else { throw LLMError.invalidResponse }
        return CodexOutputSanitizer.stripUnsupportedCitations(from: output)
    }

    private func connectedSession() async throws -> CodexRPCSession {
        let executable = try CodexRPCSession.locateExecutable()
        let session = CodexRPCSession(executableURL: executable)
        try session.start()
        _ = try await session.request(
            method: "initialize",
            params: ["clientInfo": ["name": "kvartz", "title": "Kvartz", "version": "0.1.1"]]
        )
        try session.notify(method: "initialized", params: [:])
        return session
    }

    private static func accountDescription(_ result: [String: Any]) -> String {
        guard let account = result["account"] as? [String: Any] else { return "Not connected" }
        switch account["type"] as? String {
        case "chatgpt":
            let email = account["email"] as? String
            let plan = account["planType"] as? String
            return ["Connected with ChatGPT", email, plan].compactMap { $0 }.joined(separator: " · ")
        case "apiKey": return "Connected with an OpenAI API key"
        case let type?: return "Connected · \(type)"
        default: return "Connected"
        }
    }
}

enum CodexOutputSanitizer {
    private static let annotationStart: Character = "\u{E200}"
    private static let annotationEnd: Character = "\u{E201}"
    private static let annotationSeparator: Character = "\u{E202}"

    static func stripUnsupportedCitations(from text: String) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == annotationStart else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }

            let payloadStart = text.index(after: index)
            let citationPrefix = "cite\(annotationSeparator)"
            guard text[payloadStart...].hasPrefix(citationPrefix),
                  let annotationEndIndex = text[payloadStart...].firstIndex(of: annotationEnd) else {
                result.append(text[index])
                index = payloadStart
                continue
            }

            // Citations normally follow a claim after one separating space. Remove
            // that space as well so the unsupported annotation leaves no artifact.
            if result.last == " " {
                result.removeLast()
            }
            index = text.index(after: annotationEndIndex)
        }

        return result
    }
}

final class CodexRPCSession: @unchecked Sendable {
    typealias JSON = [String: Any]

    let notifications: AsyncStream<JSON>
    private let notificationContinuation: AsyncStream<JSON>.Continuation
    private let executableURL: URL
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let queue = DispatchQueue(label: "com.kvartz.codex-rpc")
    private var buffer = Data()
    private var errorBuffer = Data()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSON, Error>] = [:]

    init(executableURL: URL) {
        self.executableURL = executableURL
        var continuation: AsyncStream<JSON>.Continuation!
        self.notifications = AsyncStream { continuation = $0 }
        self.notificationContinuation = continuation
    }

    static func locateExecutable() throws -> URL {
        let saved = NSString(
            string: UserDefaults.standard.string(forKey: "codexExecutable") ?? ""
        ).expandingTildeInPath
        let bundleCandidate = Bundle.main.resourceURL?.appendingPathComponent("codex").path
        let envCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { String($0) + "/codex" }

        if !saved.isEmpty {
            guard isUsableExecutable(at: saved) else {
                throw LLMError.codex("The configured Codex executable could not start. Clear the path to use auto-detection, or choose a working Codex binary.")
            }
            return URL(fileURLWithPath: saved)
        }

        let candidates = [
            bundleCandidate ?? "",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            NSString(string: "~/.local/bin/codex").expandingTildeInPath,
            NSString(string: "~/.npm-global/bin/codex").expandingTildeInPath
        ] + envCandidates

        if let path = candidates.first(where: { isUsableExecutable(at: $0) }) {
            return URL(fileURLWithPath: path)
        }
        throw LLMError.codex("A working Codex executable was not found. Install ChatGPT or Codex CLI, or set its executable path in Settings.")
    }

    private static func isUsableExecutable(at path: String) -> Bool {
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func start() throws {
        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { [weak self] _ in self?.finish() }
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { self?.finish(); return }
            self?.queue.async { self?.consume(data) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async {
                self?.errorBuffer.append(data)
                if let count = self?.errorBuffer.count, count > 16_384 {
                    self?.errorBuffer.removeFirst(count - 16_384)
                }
            }
        }
        try process.run()
    }

    func request(method: String, params: JSON = [:]) async throws -> JSON {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let id = self.nextID
                self.nextID += 1
                self.pending[id] = continuation
                do {
                    try self.write(["method": method, "id": id, "params": params])
                } catch {
                    self.pending.removeValue(forKey: id)?.resume(throwing: error)
                }
            }
        }
    }

    func notify(method: String, params: JSON = [:]) throws {
        try queue.sync { try write(["method": method, "params": params]) }
    }

    func stop() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        finish()
    }

    private func write(_ message: JSON) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try inputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let message = object as? JSON else { continue }
            handle(message)
        }
    }

    private func handle(_ message: JSON) {
        if let id = message["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
            if let error = message["error"] as? JSON {
                continuation.resume(throwing: LLMError.codex(error["message"] as? String ?? "Codex request failed."))
            } else {
                continuation.resume(returning: message["result"] as? JSON ?? [:])
            }
        } else if message["method"] != nil {
            notificationContinuation.yield(message)
        }
    }

    private func finish() {
        queue.async {
            let pending = self.pending
            self.pending.removeAll()
            let details = String(data: self.errorBuffer, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let message = details.flatMap { $0.isEmpty ? nil : $0 } ?? "Codex app-server stopped."
            pending.values.forEach { $0.resume(throwing: LLMError.codex(message)) }
            self.notificationContinuation.finish()
        }
    }
}
