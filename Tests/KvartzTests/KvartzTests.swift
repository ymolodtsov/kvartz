import AppKit
import Carbon.HIToolbox
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

    func testPanelGrowthAboveCursorKeepsItsBottomEdgeFixed() {
        let current = NSRect(x: 120, y: 200, width: 420, height: 142)
        let resized = panelFrameKeepingBottom(
            currentFrame: current,
            preferredHeight: 260,
            width: 420,
            bottomY: current.minY,
            visibleFrame: NSRect(x: 0, y: 24, width: 1_440, height: 876)
        )

        XCTAssertEqual(resized.minY, current.minY)
        XCTAssertEqual(resized.maxY, current.minY + 260)
    }

    func testPanelOpensBelowCursorWhenThereIsRoom() {
        let position = panelPositionNearCursor(
            cursor: NSPoint(x: 720, y: 600),
            panelSize: NSSize(width: 420, height: 140),
            visibleFrame: NSRect(x: 0, y: 24, width: 1_440, height: 876)
        )

        XCTAssertEqual(position.anchoredEdge, .top)
        XCTAssertEqual(position.frame.midX, 720)
        XCTAssertEqual(position.frame.maxY, 588)
    }

    func testPanelOpensAboveCursorNearScreenBottom() {
        let position = panelPositionNearCursor(
            cursor: NSPoint(x: 720, y: 60),
            panelSize: NSSize(width: 420, height: 140),
            visibleFrame: NSRect(x: 0, y: 24, width: 1_440, height: 876)
        )

        XCTAssertEqual(position.anchoredEdge, .bottom)
        XCTAssertEqual(position.frame.minY, 72)
        XCTAssertEqual(position.frame.height, 140)
    }

    func testCursorPositionClampsPanelToVisibleScreen() {
        let position = panelPositionNearCursor(
            cursor: NSPoint(x: 10, y: 500),
            panelSize: NSSize(width: 420, height: 140),
            visibleFrame: NSRect(x: 0, y: 24, width: 1_440, height: 876)
        )

        XCTAssertEqual(position.frame.minX, 0)
        XCTAssertTrue(NSContainsRect(NSRect(x: 0, y: 24, width: 1_440, height: 876), position.frame))
    }

    func testSavedPanelPositionIsRestoredAndClampedToVisibleScreen() {
        let frame = panelFrameAtSavedPosition(
            anchorX: 1_400,
            topY: 850,
            panelSize: NSSize(width: 420, height: 180),
            visibleFrame: NSRect(x: 0, y: 24, width: 1_440, height: 876)
        )

        XCTAssertEqual(frame.maxX, 1_440)
        XCTAssertEqual(frame.maxY, 850)
        XCTAssertTrue(NSContainsRect(NSRect(x: 0, y: 24, width: 1_440, height: 876), frame))
    }

    func testPanelOpeningPositionDefaultsToCursorAndPersists() throws {
        let suiteName = "KvartzTests.PanelOpeningPosition.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(PanelOpeningPosition.load(from: defaults), .nearCursor)
        PanelOpeningPosition.lastPosition.save(to: defaults)
        XCTAssertEqual(PanelOpeningPosition.load(from: defaults), .lastPosition)
    }

    func testInitialLoadingHeightAccountsForWrappedQuestion() {
        let short = estimatedSubmittedMessageHeight(
            question: "Best email client?",
            hasAttachments: false
        )
        let wrapped = estimatedSubmittedMessageHeight(
            question: "Want to find some blue trousers for a sports jackets, what other brands like Mango should I look into?",
            hasAttachments: false
        )

        XCTAssertEqual(short, 44)
        XCTAssertGreaterThan(wrapped, short)
    }

    func testInitialLoadingHeightAccountsForQuestionAttachments() {
        XCTAssertGreaterThan(
            estimatedSubmittedMessageHeight(question: "What is this?", hasAttachments: true),
            estimatedSubmittedMessageHeight(question: "What is this?", hasAttachments: false)
        )
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

    func testActivationShortcutMigratesLegacyKeyboardShortcut() throws {
        let suiteName = "KvartzTests.ActivationShortcut.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey))
        defaults.set(try JSONEncoder().encode(legacy), forKey: ActivationShortcutStorage.legacyDefaultsKey)

        XCTAssertEqual(
            ActivationShortcutStorage.load(from: defaults),
            ActivationShortcut(mode: .keyboard, keyboardShortcut: legacy)
        )
    }

    func testDoubleModifierTapActivatesAfterTwoCleanTaps() {
        var recognizer = ModifierGestureRecognizer(gesture: .doubleTap(.command))

        XCTAssertFalse(recognizer.flagsChanged(key: .leftCommand, modifierIsActive: true, timestamp: 1.00))
        XCTAssertFalse(recognizer.flagsChanged(key: .leftCommand, modifierIsActive: false, timestamp: 1.08))
        XCTAssertFalse(recognizer.flagsChanged(key: .rightCommand, modifierIsActive: true, timestamp: 1.24))
        XCTAssertTrue(recognizer.flagsChanged(key: .rightCommand, modifierIsActive: false, timestamp: 1.31))
    }

    func testDoubleModifierTapDoesNotActivateAfterTypingAKey() {
        var recognizer = ModifierGestureRecognizer(gesture: .doubleTap(.option))

        XCTAssertFalse(recognizer.flagsChanged(key: .leftOption, modifierIsActive: true, timestamp: 1.00))
        recognizer.interrupt()
        XCTAssertFalse(recognizer.flagsChanged(key: .leftOption, modifierIsActive: false, timestamp: 1.10))
        XCTAssertFalse(recognizer.flagsChanged(key: .leftOption, modifierIsActive: true, timestamp: 1.20))
        XCTAssertFalse(recognizer.flagsChanged(key: .leftOption, modifierIsActive: false, timestamp: 1.28))
    }

    func testBothShiftKeysActivateOnceUntilOneSideIsReleased() {
        var recognizer = ModifierGestureRecognizer(gesture: .bothSides(.shift))

        XCTAssertFalse(recognizer.flagsChanged(key: .leftShift, modifierIsActive: true, timestamp: 1.00))
        XCTAssertTrue(recognizer.flagsChanged(key: .rightShift, modifierIsActive: true, timestamp: 1.05))
        XCTAssertFalse(recognizer.flagsChanged(key: .leftControl, modifierIsActive: true, timestamp: 1.10))
        XCTAssertFalse(recognizer.flagsChanged(key: .leftControl, modifierIsActive: false, timestamp: 1.15))
        XCTAssertFalse(recognizer.flagsChanged(key: .rightShift, modifierIsActive: true, timestamp: 1.20))
        XCTAssertTrue(recognizer.flagsChanged(key: .rightShift, modifierIsActive: true, timestamp: 1.25))
    }

    func testShortcutCaptureLearnsDoubleModifierTap() {
        var recognizer = ShortcutCaptureRecognizer()

        XCTAssertNil(recognizer.flagsChanged(key: .leftCommand, modifierIsActive: true, timestamp: 1.00))
        XCTAssertNil(recognizer.flagsChanged(key: .leftCommand, modifierIsActive: false, timestamp: 1.07))
        XCTAssertNil(recognizer.flagsChanged(key: .rightCommand, modifierIsActive: true, timestamp: 1.20))
        XCTAssertEqual(
            recognizer.flagsChanged(key: .rightCommand, modifierIsActive: false, timestamp: 1.27),
            .doubleCommand
        )
    }

    func testShortcutCaptureLearnsBothShiftKeys() {
        var recognizer = ShortcutCaptureRecognizer()

        XCTAssertNil(recognizer.flagsChanged(key: .leftShift, modifierIsActive: true, timestamp: 1.00))
        XCTAssertEqual(
            recognizer.flagsChanged(key: .rightShift, modifierIsActive: true, timestamp: 1.08),
            .bothShiftKeys
        )
    }

    func testShortcutCaptureRejectsMixedModifierTaps() {
        var recognizer = ShortcutCaptureRecognizer()

        XCTAssertNil(recognizer.flagsChanged(key: .leftCommand, modifierIsActive: true, timestamp: 1.00))
        XCTAssertNil(recognizer.flagsChanged(key: .leftCommand, modifierIsActive: false, timestamp: 1.07))
        XCTAssertNil(recognizer.flagsChanged(key: .leftOption, modifierIsActive: true, timestamp: 1.20))
        XCTAssertNil(recognizer.flagsChanged(key: .leftOption, modifierIsActive: false, timestamp: 1.27))
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

    func testCodexOutputStripsInternalCitationAnnotations() {
        let answer = "Use **Mimestream**. \u{E200}cite\u{E202}turn0search11\u{E202}turn0news30\u{E201}\n\nNext paragraph."

        XCTAssertEqual(
            CodexOutputSanitizer.stripUnsupportedCitations(from: answer),
            "Use **Mimestream**.\n\nNext paragraph."
        )
    }

    func testCodexOutputPreservesRegularMarkdownAndNonCitationText() {
        let answer = "Try [Mimestream](https://mimestream.com). \u{E200}image_group\u{E202}mail-apps\u{E201}"

        XCTAssertEqual(CodexOutputSanitizer.stripUnsupportedCitations(from: answer), answer)
    }

    func testImageAttachmentIsNormalizedForProviderUpload() throws {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 2,
                pixelsHigh: 2,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.addRepresentation(bitmap)

        let attachment = try QueryAttachment.make(from: image, suggestedName: "Screenshot.tiff")

        XCTAssertEqual(attachment.name, "Screenshot.png")
        XCTAssertEqual(attachment.mediaType, "image/png")
        XCTAssertFalse(attachment.data.isEmpty)
        XCTAssertTrue(attachment.dataURL.hasPrefix("data:image/png;base64,"))
        XCTAssertNotNil(NSImage(data: attachment.data))
    }

    func testAttachmentPayloadsMatchEveryProviderProtocol() throws {
        let attachment = QueryAttachment(
            name: "pixel.png",
            mediaType: "image/png",
            data: Data([1, 2, 3])
        )
        let messages = [
            ConversationMessage(role: .user, content: "Explain this", attachments: [attachment])
        ]

        let openAI = ProviderMessagePayloads.openAIResponses(messages)
        let openAIContent = try XCTUnwrap(openAI.first?["content"] as? [[String: Any]])
        XCTAssertEqual(openAIContent.map { $0["type"] as? String }, ["input_text", "input_image"])

        let anthropic = ProviderMessagePayloads.anthropic(messages)
        let anthropicContent = try XCTUnwrap(anthropic.first?["content"] as? [[String: Any]])
        let anthropicSource = try XCTUnwrap(anthropicContent.last?["source"] as? [String: String])
        XCTAssertEqual(anthropicSource["media_type"], "image/png")
        XCTAssertEqual(anthropicSource["data"], "AQID")

        let gemini = ProviderMessagePayloads.gemini(messages)
        let geminiParts = try XCTUnwrap(gemini.first?["parts"] as? [[String: Any]])
        let inlineData = try XCTUnwrap(geminiParts.last?["inline_data"] as? [String: String])
        XCTAssertEqual(inlineData["mime_type"], "image/png")

        let openAIChat = ProviderMessagePayloads.openAIChat(messages)
        let chatContent = try XCTUnwrap(openAIChat.first?["content"] as? [[String: Any]])
        XCTAssertEqual(chatContent.last?["type"] as? String, "image_url")

        let ollama = ProviderMessagePayloads.ollama(messages)
        XCTAssertEqual(ollama.first?["images"] as? [String], ["AQID"])

        for payload in [openAI, anthropic, gemini, openAIChat, ollama] {
            XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: payload))
        }
    }
}
