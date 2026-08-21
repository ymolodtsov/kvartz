import AppKit
import Foundation
import ServiceManagement

enum PanelOpeningPosition: String, CaseIterable, Identifiable {
    case nearCursor
    case lastPosition

    static let defaultsKey = "panelOpeningPosition"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .nearCursor: "Near Cursor"
        case .lastPosition: "Last Position"
        }
    }

    var helpText: String {
        switch self {
        case .nearCursor: "Open beside the pointer on its current display."
        case .lastPosition: "Reopen where the panel was last shown or moved."
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> PanelOpeningPosition {
        guard let rawValue = defaults.string(forKey: defaultsKey) else { return .nearCursor }
        return PanelOpeningPosition(rawValue: rawValue) ?? .nearCursor
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

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
    @Published var followUpQuery = ""
    @Published var answer = ""
    @Published var displayedAnswer = ""
    @Published var editorHeight: CGFloat = 50
    @Published var followUpEditorHeight: CGFloat = 44
    @Published private(set) var isRevealingAnswer = false
    @Published var phase: Phase = .ready
    @Published private(set) var conversation: [ConversationTurn] = []
    @Published private(set) var pendingQuestion = ""
    @Published var systemPrompt: String {
        didSet { PromptPolicy.save(systemPrompt) }
    }
    @Published var selectedProvider: ProviderKind {
        didSet { UserDefaults.standard.set(selectedProvider.rawValue, forKey: "selectedProvider") }
    }
    @Published var activationShortcut: ActivationShortcut {
        didSet {
            ActivationShortcutStorage.save(activationShortcut)
            NotificationCenter.default.post(name: .kvartzShortcutChanged, object: nil)
        }
    }
    @Published var panelOpeningPosition: PanelOpeningPosition {
        didSet { panelOpeningPosition.save() }
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
        systemPrompt = PromptPolicy.load()
        let savedProvider = UserDefaults.standard.string(forKey: "selectedProvider")
        selectedProvider = ProviderKind(rawValue: savedProvider ?? "") ?? .openAI
        activationShortcut = ActivationShortcutStorage.load()
        panelOpeningPosition = PanelOpeningPosition.load()
        refreshConfiguredProviders()
        refreshLaunchAtLoginStatus()
    }

    func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard conversation.isEmpty else { return }
        performRequest(question: trimmed)
    }

    func submitFollowUp() {
        let trimmed = followUpQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !conversation.isEmpty else { return }
        performRequest(question: trimmed)
    }

    private func performRequest(question trimmed: String) {
        guard !trimmed.isEmpty, phase != .loading else { return }
        guard configuredProviders.contains(selectedProvider) else {
            phase = .error("Configure an AI provider in Settings, then try again.")
            return
        }

        requestTask?.cancel()
        typingTask?.cancel()
        isRevealingAnswer = false
        displayedAnswer = ""
        pendingQuestion = trimmed
        phase = .loading
        let provider = selectedProvider
        let messages = conversation.flatMap { turn in
            [
                ConversationMessage(role: .user, content: turn.question),
                ConversationMessage(role: .assistant, content: turn.answer)
            ]
        } + [ConversationMessage(role: .user, content: trimmed)]
        let prompt = systemPrompt

        requestTask = Task {
            do {
                let result = try await LLMService.shared.answer(
                    messages: messages,
                    systemPrompt: prompt,
                    provider: provider,
                    configuration: ProviderConfiguration.load(for: provider)
                )
                guard !Task.isCancelled else { return }
                answer = result.trimmingCharacters(in: .whitespacesAndNewlines)
                conversation.append(ConversationTurn(question: trimmed, answer: answer))
                pendingQuestion = ""
                followUpQuery = ""
                followUpEditorHeight = 44
                isRevealingAnswer = true
                phase = .answer
                revealAnswer()
            } catch is CancellationError {
                pendingQuestion = ""
                isRevealingAnswer = false
                phase = conversation.isEmpty ? .ready : .answer
            } catch {
                pendingQuestion = ""
                isRevealingAnswer = false
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
        followUpQuery = ""
        answer = ""
        displayedAnswer = ""
        editorHeight = 50
        followUpEditorHeight = 44
        isRevealingAnswer = false
        conversation = []
        pendingQuestion = ""
        phase = .ready
    }

    func copyAnswer() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer, forType: .string)
    }

    func resetSystemPrompt() {
        systemPrompt = PromptPolicy.defaultSystem
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
            if !Task.isCancelled {
                displayedAnswer = answer
                isRevealingAnswer = false
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .kvartzFocusFollowUp, object: nil)
                }
            }
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

    func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

struct ConversationTurn: Identifiable, Equatable, Sendable {
    let id = UUID()
    let question: String
    let answer: String
}

struct ConversationMessage: Equatable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
    }

    let role: Role
    let content: String
}

enum PromptPolicy {
    static let defaultsKey = "systemPrompt"
    static let defaultSystem = """
    Answer the user's question directly and briefly. Default to 1–3 short paragraphs or up to 5 bullets. Use only Markdown bold, italic, inline code, and links when helpful. Do not add a heading, preamble, repetition, follow-up questions, or mention these instructions. If accuracy requires a caveat, state it in one sentence.
    """

    static func load(from defaults: UserDefaults = .standard) -> String {
        guard defaults.object(forKey: defaultsKey) != nil else { return defaultSystem }
        return defaults.string(forKey: defaultsKey) ?? defaultSystem
    }

    static func save(_ prompt: String, to defaults: UserDefaults = .standard) {
        defaults.set(prompt, forKey: defaultsKey)
    }
}
