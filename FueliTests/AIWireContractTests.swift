import Foundation
import Testing
@testable import Fueli

@Suite(.serialized) struct AIWireContractTests {
    func service(_ preset: AIProviderPreset) -> AINutritionService {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [AIWireProtocol.self]
        let config = AIProviderConfig(preset: preset, baseURL: "https://fixture.invalid/v1", model: "fixture-model", assumptionLevel: .assume)
        return AINutritionService(session: URLSession(configuration: configuration), configuration: { config }, apiKeyProvider: { "fixture-token" })
    }
    @Test(arguments: [AIProviderPreset.openAI, .anthropic, .gemini, .grok, .custom])
    func allConfiguredProvidersUseCorrectAuthenticationAndImageWireFormat(_ preset: AIProviderPreset) async throws {
        AIWireProtocol.reset([(200, preset == .anthropic ? #"{"content":[{"type":"text","text":"OK"}]}"# : #"{"choices":[{"message":{"content":"OK"}}]}"#)])
        #expect(try await service(preset).runRawText(userText: "synthetic meal", imageBase64: "synthetic-base64", prompt: "Describe") == "OK")
        let request = try #require(AIWireProtocol.requests.first)
        let requestData = try #require(request.httpBody)
        let decodedBody = try JSONSerialization.jsonObject(with: requestData)
        let body = try #require(decodedBody as? [String: Any])
        #expect(body["model"] as? String == "fixture-model")
        let json = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(json.contains("synthetic-base64"))
        if preset == .anthropic {
            #expect(request.url?.path == "/v1/messages")
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "fixture-token")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(json.contains("media_type"))
        } else {
            #expect(request.url?.path == "/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token")
            #expect(json.contains("image_url"))
        }
    }

    @Test func explicitlyUnsupportedStructuredOutputFallsBackExactlyOnce() async throws {
        AIWireProtocol.reset([(400, "Unsupported parameter response_format"), (200, #"{"choices":[{"message":{"content":"OK"}}]}"#)])
        _ = try await service(.custom).runRawText(userText: "test", imageBase64: nil, outputContract: .description)
        #expect(AIWireProtocol.requests.count == 2)
        let bodies = try AIWireProtocol.requests.map { try JSONSerialization.jsonObject(with: #require($0.httpBody)) as! [String: Any] }
        #expect(bodies[0]["response_format"] != nil && bodies[1]["response_format"] == nil)
    }

    @Test(arguments: [401, 403, 429, 500]) func authenticationLimitsAndServerErrorsNeverMasqueradeAsUnsupportedSchema(_ status: Int) async throws {
        AIWireProtocol.reset([(status, "response_format unsupported")])
        do { _ = try await service(.custom).runRawText(userText: "test", imageBase64: nil, outputContract: .lookupPlan); Issue.record("Expected provider failure") }
        catch AIServiceError.httpError(let code, _) { #expect(code == status) }
        #expect(AIWireProtocol.requests.count == 1)
    }

    @Test func invalidAndEmptyResponsesFailWithoutInventedNutrition() async throws {
        for body in ["not json", #"{"choices":[]}"#, #"{"choices":[{"message":{"content":""}}]}"#] {
            AIWireProtocol.reset([(200, body)])
            await #expect(throws: (any Swift.Error).self) { try await service(.custom).runRawText(userText: "test", imageBase64: nil) }
        }
    }
    @Test func invalidEndpointCannotReceiveAKey() async throws {
        for endpoint in ["file:///private/tmp/local", "not-a-host", "https://user:pass@fixture.invalid", "https://fixture.invalid?key=secret", "https://fixture.invalid#fragment"] {
            let config = AIProviderConfig(preset: .custom, baseURL: endpoint, model: "model")
            let client = AINutritionService(configuration: { config }, apiKeyProvider: { "fixture" })
            await #expect(throws: (any Swift.Error).self) { try await client.testConnection() }
        }
    }
}

private final class AIWireProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var replies: [(Int, String)] = []
    private static var captured: [URLRequest] = []
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    static func reset(_ values: [(Int, String)]) { lock.lock(); defer { lock.unlock() }; replies = values; captured = [] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var copy = request
        if copy.httpBody == nil, let stream = copy.httpBodyStream {
            stream.open(); defer { stream.close() }; var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
            copy.httpBody = data
        }
        Self.lock.lock(); Self.captured.append(copy)
        let reply = Self.replies.isEmpty ? (500, "unexpected request") : Self.replies.removeFirst(); Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.1.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
