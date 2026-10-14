import Foundation
import XCTest
@testable import Kvartz

final class CodexTransportTests: XCTestCase {
    func testFinalAnswerExcludesCommentaryAndDoesNotDuplicateDeltas() {
        var output = CodexAnswerAccumulator()
        output.append(delta: "Looking it up", id: "comment")
        output.complete(id: "comment", text: "Looking it up.", phase: "commentary")
        output.append(delta: "The answer", id: "answer")
        output.complete(id: "answer", text: "The answer is 42.", phase: "final_answer")
        XCTAssertEqual(output.answer, "The answer is 42.")
    }

    func testLegacyMessagesWithoutPhasesRemainReadable() {
        var output = CodexAnswerAccumulator()
        output.append(delta: "First", id: "a")
        output.complete(id: "a", text: "First paragraph.", phase: nil)
        output.complete(id: "b", text: "Second paragraph.", phase: nil)
        XCTAssertEqual(output.answer, "First paragraph.\n\nSecond paragraph.")
    }

    private func makeServer() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("codex")
        // Stay alive and accept input without replying, as a stalled app-server would.
        try "#!/bin/sh\nwhile IFS= read -r line; do :; done\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    func testUnresponsiveServerTimesOut() async throws {
        let executable = try makeServer()
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let session = CodexRPCSession(executableURL: executable, requestTimeout: 0.05)
        try session.start()
        defer { session.stop() }
        do {
            _ = try await session.request(method: "initialize")
            XCTFail("An unresponsive server must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("did not respond"))
        }
    }

    func testCancellationUnblocksPendingRequest() async throws {
        let executable = try makeServer()
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let session = CodexRPCSession(executableURL: executable, requestTimeout: 1)
        try session.start()
        defer { session.stop() }
        let task = Task { try await session.request(method: "initialize") }
        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled request must fail")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("did not respond"), "Cancellation must not wait for the timeout")
        }
    }

    func testRequestAfterStopFailsImmediately() async throws {
        let executable = try makeServer()
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let session = CodexRPCSession(executableURL: executable, requestTimeout: 1)
        try session.start()
        session.stop()
        do {
            _ = try await session.request(method: "initialize")
            XCTFail("A stopped server must reject requests")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("stopped"))
        }
    }
}
