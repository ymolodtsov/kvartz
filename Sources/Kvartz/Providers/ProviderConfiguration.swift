import Foundation

enum ProviderKind: String, CaseIterable, Identifiable, Codable {
    case openAI
    case anthropic
    case gemini
    case qwen
    case kimi
    case glm
    case openRouter
    case ollama
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .gemini: "Google Gemini"
        case .qwen: "Qwen"
        case .kimi: "Kimi"
        case .glm: "GLM"
        case .openRouter: "OpenRouter"
        case .ollama: "Ollama"
        case .codex: "OpenAI Codex"
        }
    }

    var symbol: String {
        switch self {
        case .openAI: "circle.hexagongrid"
        case .anthropic: "a.circle"
        case .gemini: "diamond"
        case .qwen: "q.circle"
        case .kimi: "moon.stars"
        case .glm: "cube.transparent"
        case .openRouter: "arrow.triangle.branch"
        case .ollama: "desktopcomputer"
        case .codex: "terminal"
        }
    }

    var defaultModel: String {
        switch self {
        case .openAI: "gpt-5-mini"
        case .anthropic: "claude-haiku-4-5"
        case .gemini: "gemini-3.6-flash"
        case .qwen: "qwen3.7-plus"
        case .kimi: "kimi-k3"
        case .glm: "glm-5.1"
        case .openRouter: "openai/gpt-5-mini"
        case .ollama: "llama3.2"
        case .codex: "gpt-5.6-terra"
        }
    }

    var suggestedModels: [String] {
        switch self {
        case .openAI:
            ["gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol", "gpt-5-mini"]
        case .anthropic:
            ["claude-haiku-4-5", "claude-sonnet-5", "claude-opus-5", "claude-fable-5"]
        case .gemini:
            ["gemini-3.6-flash", "gemini-3.5-flash", "gemini-3.5-flash-lite"]
        case .qwen:
            ["qwen3.7-plus", "qwen3.6-plus"]
        case .kimi:
            ["kimi-k3", "kimi-k2.6"]
        case .glm:
            ["glm-5.1", "glm-5-turbo", "glm-4.7-flash"]
        case .openRouter:
            ["openai/gpt-5-mini", "openai/gpt-5.6-luna", "anthropic/claude-sonnet-5", "google/gemini-3.6-flash"]
        case .ollama:
            ["llama3.2", "qwen3", "gemma3", "mistral"]
        case .codex:
            ["gpt-5.6-terra", "gpt-5.6-sol", "gpt-5.6-luna"]
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta"
        case .qwen: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .kimi: "https://api.moonshot.ai/v1"
        case .glm: "https://api.z.ai/api/paas/v4"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .ollama: "http://127.0.0.1:11434"
        case .codex: ""
        }
    }

    var needsAPIKey: Bool { self != .ollama && self != .codex }
}

struct ProviderConfiguration: Equatable {
    let provider: ProviderKind
    var model: String
    var baseURL: String
    var apiKey: String

    static func load(for provider: ProviderKind) -> ProviderConfiguration {
        let defaults = UserDefaults.standard
        let model = defaults.string(forKey: "provider.\(provider.rawValue).model") ?? provider.defaultModel
        let baseURL = defaults.string(forKey: "provider.\(provider.rawValue).baseURL") ?? provider.defaultBaseURL
        let apiKey = (try? KeychainStore.shared.read(account: provider.rawValue)) ?? ""
        return ProviderConfiguration(provider: provider, model: model, baseURL: baseURL, apiKey: apiKey)
    }

    func save() throws {
        saveModel()
        UserDefaults.standard.set(baseURL, forKey: "provider.\(provider.rawValue).baseURL")
        if provider.needsAPIKey {
            try KeychainStore.shared.save(apiKey, account: provider.rawValue)
        }
        UserDefaults.standard.set(true, forKey: configuredKey)
    }

    func saveModel(to defaults: UserDefaults = .standard) {
        defaults.set(model, forKey: "provider.\(provider.rawValue).model")
    }

    func isConfigured(using defaults: UserDefaults = .standard) -> Bool {
        if provider.needsAPIKey {
            return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return defaults.bool(forKey: configuredKey)
            || defaults.string(forKey: "selectedProvider") == provider.rawValue
    }

    private var configuredKey: String {
        "provider.\(provider.rawValue).configured"
    }
}
