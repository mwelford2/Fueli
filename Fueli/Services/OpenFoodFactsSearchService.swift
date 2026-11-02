import Foundation

struct FoodProductCandidate: Identifiable, Decodable, Equatable {
    let code: String
    let product_name: String?
    let brands: [String]?
    var id: String { code }
    var name: String { product_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    var brand: String { (brands ?? []).joined(separator: ", ") }
}

struct FoodProductPage: Equatable {
    var products: [FoodProductCandidate]
    var page: Int
    var hasMore: Bool
}

/// Keyless reads directly from the phone. Search-a-licious supports plain-text
/// POST search; Product Opener v3 does not have a full-text search endpoint.
actor OpenFoodFactsSearchService {
    static let shared = OpenFoodFactsSearchService()
    static let userAgent = "Fueli/1.0 (https://github.com/mwelford2/Fueli)"
    private let session: URLSession
    private let minimumInterval: TimeInterval
    private var nextSearch = Date.distantPast
    private var blockedUntil = Date.distantPast
    private var cache: [String: (Date, FoodProductPage)] = [:]

    init(session: URLSession = .shared, minimumInterval: TimeInterval = 6.1) {
        self.session = session
        self.minimumInterval = max(0, minimumInterval)
    }

    struct Response: Decodable {
        let hits: [FoodProductCandidate]
        let count: Int?
        let timed_out: Bool?
    }
    private struct Request: Encodable {
        let q: String
        let page: Int
        let page_size = 20
        let langs = ["en"]
        let boost_phrase = true
        let fields = ["code", "product_name", "brands"]
    }

    func search(query: String, page: Int = 1) async throws -> FoodProductPage {
        let query = IngredientSearchText.clean(query)
        guard !query.isEmpty, query.count <= 200, (1...100).contains(page) else {
            throw AIServiceError.requestFailed("Enter a product or ingredient name of at most 200 characters.")
        }
        let key = "\(page)|\(query)"
        if let (date, result) = cache[key], Date().timeIntervalSince(date) < 900 { return result }
        for attempt in 0..<2 {
            try Task.checkCancellation()
            guard Date() >= blockedUntil else {
                throw AIServiceError.requestFailed("Open Food Facts is rate limited. Retry in \(max(1, Int(blockedUntil.timeIntervalSinceNow.rounded(.up)))) seconds.")
            }
            let slot = max(Date(), nextSearch)
            nextSearch = slot.addingTimeInterval(minimumInterval)
            if slot > Date() { try await Task.sleep(for: .seconds(slot.timeIntervalSinceNow)) }
            try Task.checkCancellation()
            guard Date() >= blockedUntil else { throw AIServiceError.requestFailed("Open Food Facts is rate limited. Wait before retrying.") }
            var request = URLRequest(url: URL(string: "https://search.openfoodfacts.org/search")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            request.httpBody = try JSONEncoder().encode(Request(q: query, page: page))
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                if http.statusCode == 429 {
                    let delay = max(60, min(3600, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60))
                    blockedUntil = Date().addingTimeInterval(delay)
                    throw AIServiceError.requestFailed("Open Food Facts rate limit reached. Retry after \(Int(delay)) seconds.")
                }
                if (http.statusCode >= 500 || http.statusCode == 408), attempt == 0 {
                    try await Task.sleep(for: .seconds(0.4 + Double.random(in: 0...0.3)))
                    continue
                }
                guard http.statusCode == 200 else {
                    throw AIServiceError.requestFailed("Open Food Facts search returned HTTP \(http.statusCode). Retry later or choose USDA.")
                }
                guard data.count <= 2_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
                let decoded = try JSONDecoder().decode(Response.self, from: data)
                guard decoded.timed_out != true else { throw AIServiceError.requestFailed("Open Food Facts search timed out. Retry or refine the product name.") }
                var seen: Set<String> = []
                let products = decoded.hits.filter {
                    !$0.name.isEmpty && BarcodeLookupService.databaseBarcode($0.code) != nil && seen.insert($0.code).inserted
                }
                let result = FoodProductPage(products: products, page: page,
                    hasMore: decoded.count.map { page * 20 < $0 } ?? (decoded.hits.count == 20))
                if cache.count >= 50 { cache.removeAll() }
                cache[key] = (Date(), result)
                return result
            } catch let error as URLError {
                if error.code == .cancelled { throw error }
                if attempt == 0, [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(error.code) {
                    try await Task.sleep(for: .seconds(0.4 + Double.random(in: 0...0.3)))
                    continue
                }
                throw AIServiceError.requestFailed("Open Food Facts is unavailable: \(error.localizedDescription) Your ingredient review is preserved.")
            } catch is DecodingError {
                throw AIServiceError.requestFailed("Open Food Facts returned an unreadable response. Retry later or choose USDA; no nutrition was inferred.")
            }
        }
        throw AIServiceError.requestFailed("Open Food Facts is temporarily unavailable. Retry later or choose USDA.")
    }
}
