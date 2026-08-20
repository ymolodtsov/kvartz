import XCTest
@testable import Kvartz

final class KvartzTests: XCTestCase {
    func testPromptPolicyKeepsAnswersShortAndAllowsFormatting() {
        XCTAssertTrue(PromptPolicy.system.contains("briefly"))
        XCTAssertTrue(PromptPolicy.system.contains("Markdown"))
        XCTAssertTrue(PromptPolicy.system.contains("links"))
    }

    func testDefaultShortcutIsReadable() {
        XCTAssertEqual(KeyboardShortcut.default.displayString, "⌥Space")
    }

    func testProviderDefaultsAreComplete() {
        for provider in ProviderKind.allCases {
            XCTAssertFalse(provider.defaultModel.isEmpty)
            XCTAssertTrue(provider.suggestedModels.contains(provider.defaultModel))
            if provider != .codex { XCTAssertFalse(provider.defaultBaseURL.isEmpty) }
        }
    }

    func testModelChoicePersistsIndependentlyOfCredentials() throws {
        let suiteName = "KvartzTests.ModelPersistence.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var configuration = ProviderConfiguration(
            provider: .codex,
            model: "custom-codex-model",
            baseURL: "",
            apiKey: ""
        )

        configuration.saveModel(to: defaults)

        XCTAssertEqual(defaults.string(forKey: "provider.codex.model"), "custom-codex-model")
        configuration.model = "another-model"
        configuration.saveModel(to: defaults)
        XCTAssertEqual(defaults.string(forKey: "provider.codex.model"), "another-model")
    }

    func testCurrentProviderDefaults() {
        XCTAssertEqual(ProviderKind.anthropic.defaultModel, "claude-haiku-4-5")
        XCTAssertEqual(ProviderKind.gemini.defaultModel, "gemini-3.6-flash")
        XCTAssertEqual(ProviderKind.qwen.defaultModel, "qwen3.7-plus")
        XCTAssertEqual(ProviderKind.kimi.defaultModel, "kimi-k3")
        XCTAssertEqual(ProviderKind.glm.defaultModel, "glm-5.1")
    }

    func testAPIProviderRequiresAKeyToBeConfigured() {
        let missingKey = ProviderConfiguration(
            provider: .anthropic,
            model: ProviderKind.anthropic.defaultModel,
            baseURL: ProviderKind.anthropic.defaultBaseURL,
            apiKey: ""
        )
        var configured = missingKey
        configured.apiKey = "test-key"

        XCTAssertFalse(missingKey.isConfigured())
        XCTAssertTrue(configured.isConfigured())
    }

    func testKeylessProviderRequiresAnExplicitSaveOrSelection() throws {
        let suiteName = "KvartzTests.ConfiguredProvider.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let ollama = ProviderConfiguration(
            provider: .ollama,
            model: ProviderKind.ollama.defaultModel,
            baseURL: ProviderKind.ollama.defaultBaseURL,
            apiKey: ""
        )

        XCTAssertFalse(ollama.isConfigured(using: defaults))
        defaults.set(true, forKey: "provider.ollama.configured")
        XCTAssertTrue(ollama.isConfigured(using: defaults))
    }

    func testAsianModelProvidersAreAvailable() {
        XCTAssertTrue(ProviderKind.allCases.contains(.qwen))
        XCTAssertTrue(ProviderKind.allCases.contains(.kimi))
        XCTAssertTrue(ProviderKind.allCases.contains(.glm))
    }

    func testBundleDeclaresItsIcon() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let info = NSDictionary(contentsOf: sourceRoot.appendingPathComponent("Info.plist"))
        XCTAssertEqual(info?["CFBundleIconFile"] as? String, "Kvartz")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent("Assets/Kvartz.icns").path))
    }

    func testCodexAutodetectionPrefersWorkingChatGPTBinary() throws {
        let bundled = "/Applications/ChatGPT.app/Contents/Resources/codex"
        guard FileManager.default.isExecutableFile(atPath: bundled) else {
            throw XCTSkip("ChatGPT's bundled Codex executable is not installed")
        }
        UserDefaults.standard.removeObject(forKey: "codexExecutable")
        XCTAssertEqual(try CodexRPCSession.locateExecutable().path, bundled)
    }
}
