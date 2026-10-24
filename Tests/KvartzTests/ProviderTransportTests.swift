import Foundation
import XCTest
@testable import Kvartz

private final class ProviderStubProtocol: URLProtocol {
    static var response: [String: Any] = [:]
    static var statusCode = 200
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: Self.response))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ProviderTransportTests: XCTestCase {
    private func request(_ provider: ProviderKind, response: [String: Any], status: Int = 200) async throws -> String {
        ProviderStubProtocol.response = response
        ProviderStubProtocol.statusCode = status
        ProviderStubProtocol.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProviderStubProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        return try await LLMService(session: session).answer(
            messages: [ConversationMessage(role: .user, content: "Question")],
            systemPrompt: "Be brief",
            provider: provider,
            configuration: ProviderConfiguration(provider: provider, model: "test-model", baseURL: "https://provider.test/v1", apiKey: "test-key")
        )
    }

    func testEveryHTTPProviderReturnsCompleteText() async throws {
        let fixtures: [(ProviderKind, [String: Any])] = [
            (.openAI, ["status": "completed", "output": [["content": [["type": "output_text", "text": "Complete answer"]]]]]),
            (.anthropic, ["stop_reason": "end_turn", "content": [["type": "text", "text": "Complete answer"]]]),
            (.gemini, ["candidates": [["finishReason": "STOP", "content": ["parts": [["text": "Complete answer"]]]]]]),
            (.ollama, ["done": true, "done_reason": "stop", "message": ["content": "Complete answer"]])
        ] + [ProviderKind.qwen, .kimi, .glm, .openRouter].map {
            ($0, ["choices": [["finish_reason": "stop", "message": ["content": "Complete answer"]]]])
        }
        for (provider, fixture) in fixtures {
            let answer = try await request(provider, response: fixture)
            XCTAssertEqual(answer, "Complete answer", provider.rawValue)
            XCTAssertEqual(ProviderStubProtocol.requests.count, 1)
            let request = try XCTUnwrap(ProviderStubProtocol.requests.first)
            XCTAssertEqual(request.httpMethod, "POST")
            let stream = try XCTUnwrap(request.httpBodyStream)
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let generation = body["generationConfig"] as? [String: Any]
            let options = body["options"] as? [String: Any]
            let limit = body["max_output_tokens"] as? Int ?? body["max_tokens"] as? Int
                ?? generation?["maxOutputTokens"] as? Int ?? options?["num_predict"] as? Int
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(limit), 4096, provider.rawValue)
        }
    }

    func testTruncatedResponsesAreNeverReportedAsComplete() async throws {
        let fixtures: [(ProviderKind, [String: Any])] = [
            (.openAI, ["status": "incomplete", "output_text": "Partial"]),
            (.anthropic, ["stop_reason": "max_tokens", "content": [["text": "Partial"]]]),
            (.gemini, ["candidates": [["finishReason": "MAX_TOKENS", "content": ["parts": [["text": "Partial"]]]]]]),
            (.ollama, ["done_reason": "length", "message": ["content": "Partial"]])
        ] + [ProviderKind.qwen, .kimi, .glm, .openRouter].map {
            ($0, ["choices": [["finish_reason": "length", "message": ["content": "Partial"]]]])
        }
        for (provider, fixture) in fixtures {
            do {
                _ = try await request(provider, response: fixture)
                XCTFail("Accepted truncated \(provider) reply")
            } catch LLMError.incompleteResponse {
                // Expected: the caller can preserve the draft and offer a retry.
            }
        }
    }

    func testOllamaErrorMessageIsReadable() async throws {
        do {
            _ = try await request(.ollama, response: ["error": "model not found"], status: 404)
            XCTFail("Expected provider error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Provider error 404: model not found")
        }
    }
}
