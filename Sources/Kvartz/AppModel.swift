import AppKit
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    enum Phase: Equatable {
        case ready
        case loading
        case answer
        case error(String)
    }

    @Published var query = ""
    @Published var answer = ""
    @Published var displayedAnswer = ""
    @Published var editorHeight: CGFloat = 50
    @Published var phase: Phase = .ready
    @Published var selectedProvider: ProviderKind {
        didSet { UserDefaults.standard.set(selectedProvider.rawValue, forKey: "selectedProvider") }
    }
    @Published var shortcut: KeyboardShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(shortcut) {
                UserDefaults.standard.set(data, forKey: "globalShortcut")
                NotificationCenter.default.post(name: .kvartzShortcutChanged, object: nil)
            }
        }
    }
    @Published var codexStatus = "Not connected"
    @Published var isConnectingCodex = false
    @Published var codexModels: [String] = []
    @Published var isLoadingCodexModels = false
    @Published private(set) var configuredProviders: [ProviderKind] = []
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginMessage = ""
    @Published private(set) var launchAtLoginNeedsApproval = false

    private var requestTask: Task<Void, Never>?
    private var typingTask: Task<Void, Never>?

    private init() {
        let savedProvider = UserDefaults.standard.string(forKey: "selectedProvider")
        selectedProvider = ProviderKind(rawValue: savedProvider ?? "") ?? .openAI
        if let data = UserDefaults.standard.data(forKey: "globalShortcut"),
           let saved = try? JSONDecoder().decode(KeyboardShortcut.self, from: data) {
            shortcut = saved
        } else {
            shortcut = .default
        }
        refreshConfiguredProviders()
        refreshLaunchAtLoginStatus()
    }

    func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, phase != .loading else { return }
        guard configuredProviders.contains(selectedProvider) else {
            phase = .error("Configure an AI provider in Settings, then try again.")
            return
        }

        requestTask?.cancel()
        typingTask?.cancel()
        answer = ""
        displayedAnswer = ""
        phase = .loading
        let provider = selectedProvider

        requestTask = Task {
            do {
                let result = try await LLMService.shared.answer(
                    query: trimmed,
                    provider: provider,
                    configuration: ProviderConfiguration.load(for: provider)
                )
                guard !Task.isCancelled else { return }
                answer = result.trimmingCharacters(in: .whitespacesAndNewlines)
                phase = .answer
                revealAnswer()
            } catch is CancellationError {
                phase = .ready
            } catch {
                phase = .error(error.localizedDescription)
            }
        }
    }

    func reset() {
        requestTask?.cancel()
        typingTask?.cancel()
        requestTask = nil
        typingTask = nil
        query = ""
        answer = ""
        displayedAnswer = ""
        editorHeight = 50
        phase = .ready
    }

    func copyAnswer() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
    }

    private func revealAnswer() {
        typingTask?.cancel()
        displayedAnswer = ""
        let characters = Array(answer)
        let chunkSize = max(1, characters.count / 180)
        typingTask = Task {
            var index = 0
            while index < characters.count, !Task.isCancelled {
                let end = min(index + chunkSize, characters.count)
                displayedAnswer.append(contentsOf: characters[index..<end])
                index = end
                try? await Task.sleep(for: .milliseconds(12))
            }
            if !Task.isCancelled { displayedAnswer = answer }
        }
    }

    func connectCodex() {
        guard !isConnectingCodex else { return }
        isConnectingCodex = true
        codexStatus = "Starting Codex…"

        Task {
            do {
                let status = try await CodexProvider.shared.signIn()
                codexStatus = status
                await refreshCodexModels()
            } catch {
                codexStatus = error.localizedDescription
            }
            isConnectingCodex = false
        }
    }

    func refreshCodexStatus() {
        Task {
            do {
                codexStatus = try await CodexProvider.shared.accountStatus()
            } catch {
                codexStatus = error.localizedDescription
            }
        }
    }

    func refreshCodexModels() async {
        guard !isLoadingCodexModels else { return }
        isLoadingCodexModels = true
        defer { isLoadingCodexModels = false }
        if let models = try? await CodexProvider.shared.availableModels(), !models.isEmpty {
            codexModels = models
        }
    }

    func refreshConfiguredProviders() {
        configuredProviders = ProviderKind.allCases.filter {
            ProviderConfiguration.load(for: $0).isConfigured()
        }
        if configuredProviders.isEmpty {
            reset()
        } else if let first = configuredProviders.first,
           !configuredProviders.contains(selectedProvider) {
            selectedProvider = first
        }
    }

    func refreshLaunchAtLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginEnabled = true
            launchAtLoginNeedsApproval = false
            launchAtLoginMessage = ""
        case .requiresApproval:
            launchAtLoginEnabled = true
            launchAtLoginNeedsApproval = true
            launchAtLoginMessage = "Approval is required in System Settings."
        case .notRegistered:
            launchAtLoginEnabled = false
            launchAtLoginNeedsApproval = false
            launchAtLoginMessage = ""
        case .notFound:
            launchAtLoginEnabled = false
            launchAtLoginNeedsApproval = false
            launchAtLoginMessage = "Launch at login is unavailable for this app bundle."
        @unknown default:
            launchAtLoginEnabled = false
            launchAtLoginNeedsApproval = false
            launchAtLoginMessage = "Launch at login status is unavailable."
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .notRegistered || service.status == .notFound {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            refreshLaunchAtLoginStatus()
        } catch {
            refreshLaunchAtLoginStatus()
            launchAtLoginMessage = error.localizedDescription
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

enum PromptPolicy {
    static let system = """
    Answer the user's question directly and briefly. Default to 1–3 short paragraphs or up to 5 bullets. Use only Markdown bold, italic, inline code, and links when helpful. Do not add a heading, preamble, repetition, follow-up questions, or mention these instructions. If accuracy requires a caveat, state it in one sentence.
    """
}
