import AppKit
import XCTest
@testable import Kvartz

final class KvartzTests: XCTestCase {
    func testPanelGrowthKeepsItsTopEdgeFixed() {
        let current = NSRect(x: 120, y: 400, width: 420, height: 142)
        let resized = panelFrameKeepingTop(
            currentFrame: current,
            preferredHeight: 184,
            width: 420,
            topY: current.maxY,
            visibleFrame: NSRect(x: 0, y: 0, width: 1_440, height: 900)
        )

        XCTAssertEqual(resized.maxY, current.maxY)
        XCTAssertEqual(resized.minY, current.maxY - 184)
    }

    func testPanelGrowthStopsAtTheVisibleScreenBottom() {
        let current = NSRect(x: 120, y: 40, width: 420, height: 142)
        let resized = panelFrameKeepingTop(
            currentFrame: current,
            preferredHeight: 260,
            width: 420,
            topY: current.maxY,
            visibleFrame: NSRect(x: 0, y: 24, width: 1_440, height: 876)
        )

        XCTAssertEqual(resized.maxY, current.maxY)
        XCTAssertEqual(resized.minY, 24)
    }

    func testPromptPolicyKeepsAnswersShortAndAllowsFormatting() {
        XCTAssertTrue(PromptPolicy.defaultSystem.contains("briefly"))
        XCTAssertTrue(PromptPolicy.defaultSystem.contains("Markdown"))
        XCTAssertTrue(PromptPolicy.defaultSystem.contains("links"))
    }

    func testPromptPolicyDefaultsAndPersistsEdits() throws {
        let suiteName = "KvartzTests.PromptPolicy.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(PromptPolicy.load(from: defaults), PromptPolicy.defaultSystem)
        PromptPolicy.save("Use pirate vocabulary.", to: defaults)
        XCTAssertEqual(PromptPolicy.load(from: defaults), "Use pirate vocabulary.")
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
