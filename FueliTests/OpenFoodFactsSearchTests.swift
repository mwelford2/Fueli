import Foundation
import Testing
@testable import Fueli

@Suite(.serialized)
struct OpenFoodFactsSearchTests {
    static func fixture() throws -> Data {
        let bundle = Bundle(for: OFFFixtureBundle.self)
        return try Data(contentsOf: #require(bundle.url(forResource: "search", withExtension: "json")))
    }
    func client() -> OpenFoodFactsSearchService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OFFSearchProtocol.self]
        return OpenFoodFactsSearchService(session: URLSession(configuration: config), minimumInterval: 0)
    }

    @Test func realSearchDecodesAndRequestsPlainTextPOSTWithoutCredentialsOrPhoto() async throws {
        let fixture = try Self.fixture()
        OFFSearchProtocol.reset([(200, fixture, [:])])
        let service = client()
        let result = try await service.search(query: "cream cheese")
        let again = try await service.search(query: "cream cheese")
        #expect(result == again)
        #expect(result.products.count == 5)
        #expect(result.products[2].brand == "Bega")
        #expect(OFFSearchProtocol.requests.count == 1)
        let request = try #require(OFFSearchProtocol.requests.first)
        #expect(request.url?.absoluteString == "https://search.openfoodfacts.org/search")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("github.com/mwelford2/Fueli") == true)
        let payload = try #require(JSONSerialization.jsonObject(with: OFFSearchProtocol.body(request)) as? [String: Any])
        #expect(payload["q"] as? String == "cream cheese")
        #expect(payload["page_size"] as? Int == 20)
        #expect(payload["boost_phrase"] as? Bool == true)
        #expect(Set(payload.keys) == ["q", "page", "page_size", "langs", "boost_phrase", "fields"])
    }

    @Test func rateLimitHasCooldownAndDoesNotBecomeNoProducts() async throws {
        OFFSearchProtocol.reset([(429, Data(), ["Retry-After": "120"])])
        let service = client()
        do { _ = try await service.search(query: "cheese"); Issue.record("Expected rate limit") }
        catch { #expect(error.localizedDescription.contains("120")) }
        do { _ = try await service.search(query: "bagel"); Issue.record("Expected cooldown") }
        catch { #expect(error.localizedDescription.contains("rate limited")) }
        #expect(OFFSearchProtocol.requests.count == 1)
    }

    @Test func malformedAndErrorStatusesAreNotSuccessfulEmptyResults() async throws {
        for (status, body) in [(200, "{broken"), (403, "{}"), (422, "{}"), (200, "{\"errors\":[]}")] {
            OFFSearchProtocol.reset([(status, Data(body.utf8), [:])])
            do { _ = try await client().search(query: "cheese"); Issue.record("Expected failure") }
            catch { #expect(error.localizedDescription.contains(status == 200 ? "unreadable" : "HTTP \(status)")) }
        }
    }

    @Test func serverFailureRetriesOnceAndPaginationDoesNotReuseWrongPage() async throws {
        let fixture = try Self.fixture()
        OFFSearchProtocol.reset([(503, Data(), [:]), (200, fixture, [:]), (200, fixture, [:])])
        let service = client()
        #expect(try await service.search(query: "cheese").page == 1)
        #expect(try await service.search(query: "cheese", page: 2).page == 2)
        #expect(OFFSearchProtocol.requests.count == 3)
    }

    @Test func emptyDuplicatesAndInvalidCodesAreHandledWithoutConfirmation() async throws {
        let json = #"{"hits":[{"code":"bad","product_name":"Bad"},{"code":"0036000291452","product_name":"Test","brands":[]},{"code":"0036000291452","product_name":"Test"}],"count":3}"#
        OFFSearchProtocol.reset([(200, Data(json.utf8), [:]), (200, Data(#"{"hits":[],"count":0}"#.utf8), [:])])
        let service = client()
        #expect(try await service.search(query: "cheese").products.count == 1)
        #expect(try await service.search(query: "nothing").products.isEmpty)
    }

    @Test func OFFOnlyProductLookupCannotFallBackToUSDA() async throws {
        OFFSearchProtocol.reset([(404, Data(), [:])])
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OFFSearchProtocol.self]
        let service = BarcodeLookupService(session: URLSession(configuration: config))
        do { _ = try await service.lookupOpenFoodFactsOnly(barcode: "036000291452"); Issue.record("Expected missing product") }
        catch { #expect(error is BarcodeLookupError) }
        #expect(OFFSearchProtocol.requests.count == 1)
        #expect(OFFSearchProtocol.requests.allSatisfy { $0.url?.host == "world.openfoodfacts.org" })
    }

    @Test func incompleteProductRemainsUnknownAndExplicitZerosAreUsable() async throws {
        let incomplete = #"{"product":{"code":"0036000291452","product_name":"Test","product_quantity_unit":"g","nutriments":{"energy-kcal_100g":150,"proteins_100g":10,"carbohydrates_100g":12.25,"fat_100g":3.5}}}"#
        OFFSearchProtocol.reset([(200, Data(incomplete.utf8), [:])])
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OFFSearchProtocol.self]
        do {
            _ = try await BarcodeLookupService(session: URLSession(configuration: config)).lookupOpenFoodFactsOnly(barcode: "036000291452")
            Issue.record("Missing fiber must not be invented")
        } catch { #expect(error is NutritionValidationError) }
        let complete = incomplete.replacingOccurrences(of: "\"fat_100g\":3.5", with: "\"fat_100g\":3.5,\"fiber_100g\":0")
        let dto = try JSONDecoder().decode(BarcodeLookupService.OFFResponse.self, from: Data(complete.utf8))
        #expect(try BarcodeLookupService.normalize(dto, barcode: "036000291452").fiberG == 0)
    }

    @Test func realProductDetailNormalizesWithoutMixingServingAndReferenceAmounts() async throws {
        let bundle = Bundle(for: OFFFixtureBundle.self)
        let data = try Data(contentsOf: #require(bundle.url(forResource: "cream-cheese-product", withExtension: "json")))
        OFFSearchProtocol.reset([(200, data, [:])])
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OFFSearchProtocol.self]
        let facts = try await BarcodeLookupService(session: URLSession(configuration: config)).lookupOpenFoodFactsOnly(barcode: "9311000999555")
        #expect(facts.caloriesValue == 330)
        #expect(facts.proteinG == 8.3)
        #expect(facts.gramsPerServing == 100)
        #expect(facts.fiberG == 0.1)
        #expect(abs(facts.carbsG - 2.8) < 0.0000001)
        #expect(facts.sourceRecordID == "OFF:9311000999555")
    }

    @Test func sourceOnlyCacheCannotBypassBarcodeConflictChecks() async throws {
        let bundle = Bundle(for: OFFFixtureBundle.self)
        let data = try Data(contentsOf: #require(bundle.url(forResource: "cream-cheese-product", withExtension: "json")))
        OFFSearchProtocol.reset([(200, data, [:]), (200, Data("{broken".utf8), [:])])
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [OFFSearchProtocol.self]
        let service = BarcodeLookupService(session: URLSession(configuration: config), minimumProductInterval: 0)
        _ = try await service.lookupOpenFoodFactsOnly(barcode: "9311000999555")
        do {
            _ = try await service.lookup(barcode: "9311000999555")
            Issue.record("The barcode lookup must not use a source-only cache entry")
        } catch { #expect(error is DecodingError) }
        #expect(OFFSearchProtocol.requests.count == 2)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FUELI_LIVE_OFF_TESTS"] == "1"))
    func optionalLiveSearchThenExplicitProductDetail() async throws {
        let page = try await OpenFoodFactsSearchService().search(query: "cream cheese")
        let selected = try #require(page.products.first { $0.code == "9311000999555" })
        let facts = try await BarcodeLookupService().lookupOpenFoodFactsOnly(barcode: selected.code)
        #expect(facts.sourceRecordID == "OFF:" + selected.code)
        #expect(facts.gramsPerServing == 100)
        #expect(facts.caloriesValue.isFinite && facts.caloriesValue > 0)
    }
}

private final class OFFFixtureBundle {}

private final class OFFSearchProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var replies: [(Int, Data, [String: String])] = []
    private static var captured: [URLRequest] = []
    static var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return captured }
    static func reset(_ values: [(Int, Data, [String: String])]) {
        lock.lock(); defer { lock.unlock() }; replies = values; captured = []
    }
    static func body(_ request: URLRequest) throws -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        var request = request
        // Capture the stream while it is still readable; URLSession may consume it.
        request.httpBody = try? Self.body(request)
        Self.captured.append(request)
        let reply = Self.replies.isEmpty ? (500, Data(), [:]) : Self.replies.removeFirst()
        Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.0, httpVersion: nil, headerFields: reply.2)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.1)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
