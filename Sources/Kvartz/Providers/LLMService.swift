import Foundation

actor LLMService {
    static let shared = LLMService()

    func answer(
        messages: [ConversationMessage],
        systemPrompt: String,
        provider: ProviderKind,
        configuration: ProviderConfiguration
    ) async throws -> String {
        if provider == .codex {
            return try await CodexProvider.shared.answer(
                messages: messages,
                systemPrompt: systemPrompt,
                model: configuration.model
            )
        }
        if configuration.apiKey.isEmpty && provider.needsAPIKey {
            throw LLMError.configuration("Add an API key for \(provider.displayName) in Settings.")
        }
        guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.configuration("Choose a model for \(provider.displayName) in Settings.")
        }

        switch provider {
        case .openAI:
            return try await openAI(messages, systemPrompt, configuration)
        case .anthropic:
            return try await anthropic(messages, systemPrompt, configuration)
        case .gemini:
            return try await gemini(messages, systemPrompt, configuration)
        case .qwen, .kimi, .glm:
            return try await openAICompatible(messages, systemPrompt, configuration)
        case .openRouter:
            return try await openRouter(messages, systemPrompt, configuration)
        case .ollama:
            return try await ollama(messages, systemPrompt, configuration)
        case .codex:
            fatalError("Handled above")
        }
    }

    private func openAI(
        _ messages: [ConversationMessage],
        _ systemPrompt: String,
        _ config: ProviderConfiguration
    ) async throws -> String {
        let json = try await post(
            url: endpoint(config.baseURL, "responses"),
            headers: ["Authorization": "Bearer \(config.apiKey)"],
            body: [
                "model": config.model,
                "instructions": systemPrompt,
                "input": apiMessages(messages),
                "max_output_tokens": 320
            ]
        )
        if let direct = json["output_text"] as? String, !direct.isEmpty { return direct }
        if let output = json["output"] as? [[String: Any]] {
            let texts = output.flatMap { ($0["content"] as? [[String: Any]]) ?? [] }
                .compactMap { $0["text"] as? String }
            if !texts.isEmpty { return texts.joined() }
        }
        throw LLMError.invalidResponse
    }

    private func anthropic(
        _ messages: [ConversationMessage],
        _ systemPrompt: String,
        _ config: ProviderConfiguration
    ) async throws -> String {
        let json = try await post(
            url: endpoint(config.baseURL, "messages"),
            headers: ["x-api-key": config.apiKey, "anthropic-version": "2023-06-01"],
            body: [
                "model": config.model,
                "max_tokens": 320,
                "system": systemPrompt,
                "messages": apiMessages(messages)
            ]
        )
        let text = (json["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
        guard !text.isEmpty else { throw LLMError.invalidResponse }
        return text
    }

    private func gemini(
        _ messages: [ConversationMessage],
        _ systemPrompt: String,
        _ config: ProviderConfiguration
    ) async throws -> String {
        let json = try await post(
            url: endpoint(config.baseURL, "models/\(config.model):generateContent"),
            headers: ["x-goog-api-key": config.apiKey],
            body: [
                "systemInstruction": ["parts": [["text": systemPrompt]]],
                "contents": messages.map { message in
                    [
                        "role": message.role == .assistant ? "model" : "user",
                        "parts": [["text": message.content]]
                    ]
                },
                "generationConfig": ["maxOutputTokens": 320]
            ]
        )
        let candidates = json["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let text = (content?["parts"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
        guard !text.isEmpty else { throw LLMError.invalidResponse }
        return text
    }

    private func openRouter(
        _ messages: [ConversationMessage],
        _ systemPrompt: String,
        _ config: ProviderConfiguration
    ) async throws -> String {
        try await openAICompatible(
            messages,
            systemPrompt,
            config,
            additionalHeaders: [
                "HTTP-Referer": "https://github.com/kvartz-app/kvartz",
                "X-OpenRouter-Title": "Kvartz"
            ]
        )
    }

    private func openAICompatible(
        _ messages: [ConversationMessage],
        _ systemPrompt: String,
        _ config: ProviderConfiguration,
        additionalHeaders: [String: String] = [:]
    ) async throws -> String {
        var headers = ["Authorization": "Bearer \(config.apiKey)"]
        headers.merge(additionalHeaders) { _, new in new }
        let json = try await post(
            url: endpoint(config.baseURL, "chat/completions"),
            headers: headers,
            body: [
                "model": config.model,
                "max_tokens": 320,
                "messages": [["role": "system", "content": systemPrompt]] + apiMessages(messages)
            ]
        )
        let choices = json["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let text = message?["content"] as? String, !text.isEmpty else { throw LLMError.invalidResponse }
        return text
    }

    private func ollama(
        _ messages: [ConversationMessage],
        _ systemPrompt: String,
        _ config: ProviderConfiguration
    ) async throws -> String {
        let json = try await post(
            url: endpoint(config.baseURL, "api/chat"),
            headers: [:],
            body: [
                "model": config.model,
                "stream": false,
                "options": ["num_predict": 320],
                "messages": [["role": "system", "content": systemPrompt]] + apiMessages(messages)
            ]
        )
        let message = json["message"] as? [String: Any]
        guard let text = message?["content"] as? String, !text.isEmpty else { throw LLMError.invalidResponse }
        return text
    }

    private func endpoint(_ baseURL: String, _ path: String) -> URL {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: "\(trimmed)/\(path)")!
    }

    private func apiMessages(_ messages: [ConversationMessage]) -> [[String: String]] {
        messages.map { ["role": $0.role.rawValue, "content": $0.content] }
    }

    private func post(url: URL, headers: [String: String], body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LLMError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let nested = json?["error"] as? [String: Any]
            let message = nested?["message"] as? String
                ?? json?["message"] as? String
                ?? String(data: data, encoding: .utf8)
                ?? "Request failed"
            throw LLMError.http(http.statusCode, message)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse
        }
        return json
    }
}

enum LLMError: LocalizedError {
    case configuration(String)
    case http(Int, String)
    case invalidResponse
    case codex(String)

    var errorDescription: String? {
        switch self {
        case .configuration(let message): message
        case .http(let status, let message): "Provider error \(status): \(message)"
        case .invalidResponse: "The provider returned an unreadable response."
        case .codex(let message): message
        }
    }
}
