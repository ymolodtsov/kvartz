import AppKit
import SwiftUI
import Vision
import XCTest
@testable import Kvartz

@MainActor
final class ConversationFlowTests: XCTestCase {
    @MainActor private final class Replies {
        var messages: [[ConversationMessage]] = []
        var continuations: [CheckedContinuation<String, Error>] = []

        func answer(_ messages: [ConversationMessage], _ prompt: String, _ provider: ProviderKind) async throws -> String {
            self.messages.append(messages)
            return try await withCheckedThrowingContinuation { continuations.append($0) }
        }

        func complete(_ index: Int, with result: Result<String, Error>) {
            continuations[index].resume(with: result)
        }
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for the conversation state", file: file, line: line)
        throw NSError(domain: "ConversationFlowTests", code: 1)
    }

    func testFollowUpRetainsQuestionIdentityAndSendsConversationHistory() async throws {
        let replies = Replies()
        let model = AppModel(provider: .ollama, requestAnswer: replies.answer)
        model.query = "First question"
        model.submit()
        let firstID = try XCTUnwrap(model.visibleTurns.first?.id)
        try await waitUntil { replies.messages.count == 1 }
        replies.complete(0, with: .success("First answer"))
        try await waitUntil { model.phase == .answer }
        XCTAssertEqual(model.conversation.first?.id, firstID)

        model.followUpQuery = "Follow-up question"
        model.submitFollowUp()
        let followUpID = try XCTUnwrap(model.visibleTurns.last?.id)
        XCTAssertEqual(model.visibleTurns.map(\.question), ["First question", "Follow-up question"])
        try await waitUntil { replies.messages.count == 2 }
        XCTAssertEqual(replies.messages[1], [
            ConversationMessage(role: .user, content: "First question"),
            ConversationMessage(role: .assistant, content: "First answer"),
            ConversationMessage(role: .user, content: "Follow-up question")
        ])
        replies.complete(1, with: .success("Second answer"))
        try await waitUntil { model.phase == .answer }
        XCTAssertEqual(model.visibleTurns.map(\.question), ["First question", "Follow-up question"])
        XCTAssertEqual(model.conversation.last?.id, followUpID)
        XCTAssertEqual(model.displayedAnswer, "Second answer")
        XCTAssertTrue(model.followUpQuery.isEmpty)
        XCTAssertNil(model.pendingTurnID)
    }

    func testFailedFollowUpPreservesDraftHistoryAndPreviousAnswerForRetry() async throws {
        let replies = Replies()
        let model = AppModel(provider: .ollama, requestAnswer: replies.answer)
        model.query = "First question"
        model.submit()
        try await waitUntil { replies.messages.count == 1 }
        replies.complete(0, with: .success("First answer"))
        try await waitUntil { model.phase == .answer }
        model.followUpQuery = "Try again"
        model.submitFollowUp()
        try await waitUntil { replies.messages.count == 2 }
        replies.complete(1, with: .failure(LLMError.http(503, "Unavailable")))
        try await waitUntil { if case .error = model.phase { return true }; return false }
        XCTAssertEqual(model.followUpQuery, "Try again")
        XCTAssertEqual(model.displayedAnswer, "First answer")
        XCTAssertEqual(model.visibleTurns.count, 1)
        model.submitFollowUp()
        try await waitUntil { replies.messages.count == 3 }
        XCTAssertEqual(replies.messages[1], replies.messages[2])
        replies.complete(2, with: .success("Retried answer"))
        try await waitUntil { model.phase == .answer }
        XCTAssertEqual(model.conversation.count, 2)
    }

    func testClosingAndReopeningIgnoresLateFailureFromCancelledRequest() async throws {
        let replies = Replies()
        let model = AppModel(provider: .ollama, requestAnswer: replies.answer)
        model.query = "Old request"
        model.submit()
        try await waitUntil { replies.messages.count == 1 }
        model.reset()
        model.query = "New request"
        model.submit()
        let newID = model.pendingTurnID
        try await waitUntil { replies.messages.count == 2 }
        replies.complete(0, with: .failure(CancellationError()))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.phase, .loading)
        XCTAssertEqual(model.pendingQuestion, "New request")
        XCTAssertEqual(model.pendingTurnID, newID)
        replies.complete(1, with: .success("New answer"))
        try await waitUntil { model.phase == .answer }
        XCTAssertEqual(model.conversation.map(\.question), ["New request"])
    }

    func testClosingIgnoresLateSuccessAndGenericErrors() async throws {
        for result: Result<String, Error> in [.success("Late answer"), .failure(LLMError.invalidResponse)] {
            let replies = Replies()
            let model = AppModel(provider: .ollama, requestAnswer: replies.answer)
            model.query = "Old request"
            model.submit()
            try await waitUntil { replies.messages.count == 1 }
            model.reset()
            replies.complete(0, with: result)
            try await Task.sleep(for: .milliseconds(30))
            XCTAssertEqual(model.phase, .ready)
            XCTAssertTrue(model.conversation.isEmpty)
            XCTAssertTrue(model.answer.isEmpty)
            XCTAssertNil(model.pendingTurnID)
        }
    }

    func testBlankResponsesBecomeRetryableErrorsAndDoubleSubmitIsIgnored() async throws {
        let replies = Replies()
        let model = AppModel(provider: .ollama, requestAnswer: replies.answer)
        model.query = "Question"
        model.submit()
        model.submit()
        try await waitUntil { replies.messages.count == 1 }
        replies.complete(0, with: .success(" \n "))
        try await waitUntil { if case .error = model.phase { return true }; return false }
        XCTAssertEqual(replies.messages.count, 1)
        XCTAssertEqual(model.query, "Question")
        XCTAssertTrue(model.conversation.isEmpty)
        XCTAssertNil(model.pendingTurnID)
    }

    func testImageOnlyQuestionAndRetryRetainAttachments() async throws {
        let replies = Replies()
        let model = AppModel(provider: .ollama, requestAnswer: replies.answer)
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        model.addAttachment(image, suggestedName: "Test")
        let attachment = try XCTUnwrap(model.draftAttachments.first)
        model.submit()
        try await waitUntil { replies.messages.count == 1 }
        XCTAssertEqual(model.visibleTurns.first?.attachments, [attachment])
        XCTAssertEqual(replies.messages[0].first?.attachments, [attachment])
        replies.complete(0, with: .failure(LLMError.invalidResponse))
        try await waitUntil { if case .error = model.phase { return true }; return false }
        XCTAssertEqual(model.draftAttachments, [attachment])
        model.submit()
        try await waitUntil { replies.messages.count == 2 }
        replies.complete(1, with: .success("An image"))
        try await waitUntil { model.phase == .answer }
        XCTAssertEqual(model.conversation.first?.attachments, [attachment])
        XCTAssertTrue(model.draftAttachments.isEmpty)
    }

    func testProviderURLValidation() throws {
        for value in ["", "localhost:11434", "https://", "https://[bad", "file:///tmp/server", "https://host/v1?key=a", "https://host/#fragment"] {
            XCTAssertThrowsError(try ProviderConfiguration.validatedBaseURL(value), value)
        }
        XCTAssertEqual(try ProviderConfiguration.validatedBaseURL(" https://example.com/v1/ \n").appendingPathComponent("responses").absoluteString, "https://example.com/v1/responses")
        XCTAssertEqual(try ProviderConfiguration.validatedBaseURL("http://127.0.0.1:11434").host, "127.0.0.1")
    }

    func testReturnConfirmsMarkedTextWithoutSubmitting() throws {
        _ = NSApplication.shared
        let view = SubmitTextView()
        var submitted = false
        view.onSubmit = { submitted = true }
        view.setMarkedText("test", selectedRange: NSRange(location: 4, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let enter = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36
        ))
        view.keyDown(with: enter)
        XCTAssertFalse(submitted)
        view.unmarkText()
        view.keyDown(with: enter)
        XCTAssertTrue(submitted)
    }

    func testAnimatedAnswerRendersThroughItsFinalSentence() async throws {
        _ = NSApplication.shared
        let response = "Preheat oven to 180 degrees.\n\nMix peaches with sugar and lemon juice. Spread them in a baking dish.\n\nCombine flour, sugar, baking powder, milk, and melted butter. Spoon the batter over the fruit.\n\nBake until golden and bubbling. Serve warm with vanilla ice cream."
        let model = AppModel(provider: .ollama, animatesAnswers: true) { _, _, _ in
            try await Task.sleep(for: .milliseconds(400))
            return response
        }
        let controller = QueryPanelController(model: model)
        controller.show()
        let window = try XCTUnwrap(controller.window)
        let hosting = try XCTUnwrap(window.contentView)
        defer { window.close(); model.reset() }
        model.query = "Peach cobbler recipe"
        withAnimation(.smooth(duration: 0.32)) { model.submit() }
        try await Task.sleep(for: .seconds(5))
        XCTAssertFalse(model.isRevealingAnswer)
        XCTAssertEqual(model.displayedAnswer, response)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        if let directory = ProcessInfo.processInfo.environment["KVARTZ_UI_SNAPSHOTS"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("animated-answer.png"))
        }
        let recognition = VNRecognizeTextRequest()
        recognition.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([recognition])
        let text = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(text.contains("vanilla ice cream"), "The model finished, but the visible answer is incomplete: \(text)")
    }

    func testRenderFollowUpFlow() async throws {
        guard let directory = ProcessInfo.processInfo.environment["KVARTZ_UI_SNAPSHOTS"] else {
            throw XCTSkip("Set KVARTZ_UI_SNAPSHOTS to render native conversation snapshots")
        }
        _ = NSApplication.shared
        let replies = Replies()
        let model = AppModel(provider: .ollama, requestAnswer: replies.answer)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 1000), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: QuickQueryView(model: model, onClose: {}))
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        func snapshot(_ name: String, containing expectedText: String, answer expectedAnswer: String? = nil) async throws {
            try await Task.sleep(for: .milliseconds(500))
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([recognition])
            let text = (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            XCTAssertTrue(text.contains(expectedText), "Missing rendered text: \(expectedText). Found: \(text)")
            if let expectedAnswer {
                XCTAssertTrue(text.contains(expectedAnswer), "Missing rendered answer: \(expectedAnswer). Found: \(text)")
            }
        }
        model.query = "How to move Apple Watch to a new iPhone after recovery?"
        model.submit()
        try await waitUntil { replies.messages.count == 1 }
        replies.complete(0, with: .success("On the recovered iPhone:\n\n1. Restore your iPhone backup and sign in with the same Apple Account.\n2. Open the Watch app and tap **Pair New Watch**.\n3. Choose **Restore from Backup** if prompted.\n\nIf the Watch is still paired to the old iPhone, unpair it there first."))
        try await waitUntil { model.phase == .answer }
        try await snapshot("01-first-answer", containing: "How to move Apple Watch", answer: "unpair it there first")
        model.followUpQuery = "How do I unpair it on the old iPhone?"
        model.submitFollowUp()
        try await waitUntil { replies.messages.count == 2 }
        try await snapshot("02-follow-up-loading", containing: "How do I unpair it on the old iPhone?")
        replies.complete(1, with: .success("On the old iPhone:\n\n1. Open the Watch app.\n2. Tap **My Watch → All Watches**.\n3. Tap ⓘ, then **Unpair Apple Watch**.\n4. Enter your Apple Account password if asked.\n\nThen pair the Watch on the recovered iPhone."))
        try await waitUntil { model.phase == .answer }
        try await snapshot("03-follow-up-answer", containing: "How do I unpair it on the old iPhone?", answer: "Then pair the Watch on the recovered iPhone")
        model.followUpQuery = "What if the old phone is unavailable?"
        model.submitFollowUp()
        try await waitUntil { replies.messages.count == 3 }
        replies.complete(2, with: .failure(LLMError.http(503, "Temporarily unavailable. Try again.")))
        try await waitUntil { if case .error = model.phase { return true }; return false }
        try await snapshot("04-follow-up-error", containing: "How do I unpair it on the old iPhone?")

        window.setContentSize(NSSize(width: 420, height: 520))
        model.submitFollowUp()
        try await waitUntil { replies.messages.count == 4 }
        replies.complete(3, with: .success((1...30).map { "Recovery step \($0): follow the instructions shown on your device." }.joined(separator: "\n\n")))
        try await waitUntil { model.phase == .answer }
        try await snapshot("05-long-answer", containing: "What if the old phone is unavailable?")

        func conversationScrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, !(scroll.documentView is NSTextView) { return scroll }
            return view.subviews.lazy.compactMap { conversationScrollView(in: $0) }.first
        }
        let scrollView = try XCTUnwrap(conversationScrollView(in: hosting))
        let document = try XCTUnwrap(scrollView.documentView)
        let endY = max(0, document.bounds.height - scrollView.contentView.bounds.height)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? endY : 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        try await snapshot("06-scrolled-to-bottom", containing: "What if the old phone is unavailable?", answer: "Recovery step 30")
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: document.isFlipped ? 0 : endY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        try await snapshot("07-scrolled-to-top", containing: "How to move Apple Watch")
    }
}
