import Foundation

enum BarcodeLookupError: LocalizedError {
    case notFound
    case requestFailed(String)
    var errorDescription: String? {
        switch self {
        case .notFound: return "No exact product match was found. Try manual entry."
        case .requestFailed(let message): return "Lookup failed: \(message)"
        }
    }
}

actor BarcodeLookupService {
    static let shared = BarcodeLookupService()
    private var cache: [String: (Date, NutritionFacts)] = [:]
    private var offCache: [String: (Date, NutritionFacts)] = [:]
    private var nextRequest = Date.distantPast
    private var nextProductSlot = Date.distantPast
    private let session: URLSession
    private let minimumProductInterval: TimeInterval
    init(session: URLSession = .shared, minimumProductInterval: TimeInterval = 4.1) {
        self.session = session
        self.minimumProductInterval = max(0, minimumProductInterval)
    }

    func clearCache() { cache.removeAll(); offCache.removeAll() }

    struct OFFResponse: Decodable {
        struct Product: Decodable {
            let code: String?
            let product_name: String?
            let brands: String?
            let product_quantity_unit: String?
            let serving_quantity_unit: String?
            let nutriments: Nutrients?
        }
        struct Nutrients: Decodable {
            let kcal, kj, protein, availableCarbs, totalCarbs, fat, fiber: Double?
            enum CodingKeys: String, CodingKey {
                case kcal = "energy-kcal_100g", kj = "energy-kj_100g", protein = "proteins_100g"
                case availableCarbs = "carbohydrates_100g", totalCarbs = "carbohydrates-total_100g"
                case fat = "fat_100g", fiber = "fiber_100g"
            }
        }
        let product: Product?
    }

    static func databaseBarcode(_ code: String) -> String? {
        let normalized = code.count == 14 && code.first == "0" ? String(code.dropFirst()) : code
        return try? RetailBarcode(normalized).canonical
    }

    /// GS1 database records may pad GTIN-8/12/13 to fourteen digits.
    /// Padding is only for comparison; scanner format and leading zeros are retained.
    static func gtinIdentity(_ code: String) -> String? {
        guard let canonical = databaseBarcode(code) else { return nil }
        return String(repeating: "0", count: 14 - canonical.count) + canonical
    }

    static func sameGTIN(_ lhs: String, _ rhs: String) -> Bool {
        guard let left = gtinIdentity(lhs), let right = gtinIdentity(rhs) else { return false }
        return left == right
    }

    static func normalize(_ response: OFFResponse, barcode: String) throws -> NutritionFacts {
        guard let product = response.product, let code = product.code,
              sameGTIN(code, barcode), let n = product.nutriments else { throw BarcodeLookupError.notFound }
        let unit = (product.product_quantity_unit ?? product.serving_quantity_unit ?? "").lowercased()
        let volume = ["ml", "cl", "l"].contains(unit)
        guard volume || ["g", "kg", "oz", "lb"].contains(unit) else {
            throw BarcodeLookupError.requestFailed("This record does not establish a mass or volume basis. Review its package and use manual entry.")
        }
        // OFF available carbohydrate excludes fiber. Prefer its explicit total; otherwise
        // derive a total only when BOTH available carbohydrate and fiber are present.
        let carbs = n.totalCarbs ?? n.availableCarbs.flatMap { available in n.fiber.map { available + $0 } }
        guard let c = n.kcal ?? n.kj.map({ $0 / 4.184 }), let p = n.protein,
              let carbs, let fat = n.fat, let fiber = n.fiber else { throw NutritionValidationError.incomplete }
        _ = try ServingNutrition(calories: c, protein: p, carbohydrates: carbs, fat: fat, fiber: fiber)
        guard c <= 1000, p <= 100, carbs <= 100, fat <= 100, fiber <= 100 else { throw NutritionValidationError.invalidValues }
        guard let productName = product.product_name, !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BarcodeLookupError.notFound }
        let name = [product.brands, productName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        guard !name.isEmpty else { throw BarcodeLookupError.notFound }
        return NutritionFacts(name: name, calories: Int(c.rounded()), proteinG: p, carbsG: carbs, fatG: fat,
                              fiberG: fiber, servingDescription: "100 \(volume ? "mL" : "g") · Open Food Facts · \(code)", barcode: databaseBarcode(barcode), sourceRecordID: "OFF:" + code, gramsPerServing: volume ? nil : 100, millilitersPerServing: volume ? 100 : nil, caloriesExact: c)
    }

    static func materiallyDisagree(_ lhs: NutritionFacts, _ rhs: NutritionFacts) -> Bool {
        guard lhs.gramsPerServing == rhs.gramsPerServing, lhs.millilitersPerServing == rhs.millilitersPerServing else { return true }
        let energyDifference = abs(lhs.caloriesValue - rhs.caloriesValue)
        if energyDifference > max(20, Double(max(lhs.calories, rhs.calories)) * 0.15) { return true }
        return [(lhs.proteinG, rhs.proteinG), (lhs.carbsG, rhs.carbsG), (lhs.fatG, rhs.fatG)].contains {
            abs($0.0 - $0.1) > max(2, max($0.0, $0.1) * 0.2)
        }
    }

    func lookup(barcode: String) async throws -> NutritionFacts {
        try await lookup(barcode: barcode, allowUSDAFallback: true)
    }

    /// A selected database must not silently switch providers or reuse a USDA cache entry.
    func lookupOpenFoodFactsOnly(barcode: String) async throws -> NutritionFacts {
        try await lookup(barcode: barcode, allowUSDAFallback: false)
    }

    private func lookup(barcode: String, allowUSDAFallback: Bool) async throws -> NutritionFacts {
        let barcode = try RetailBarcode(barcode).canonical
        let selectedCache = allowUSDAFallback ? cache : offCache
        if let (date, facts) = selectedCache[barcode], Date().timeIntervalSince(date) < 86400 { return facts }
        guard Date() >= nextRequest else { throw BarcodeLookupError.requestFailed("Product service is rate limited. Wait before retrying.") }
        let url = URL(string: "https://world.openfoodfacts.org/api/v3/product/\(barcode)?fields=code,product_name,brands,nutriments,product_quantity_unit,serving_quantity_unit")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Fueli/1.0 (https://github.com/mwelford2/Fueli)", forHTTPHeaderField: "User-Agent")
        for attempt in 0..<3 {
            let slot = max(Date(), nextProductSlot)
            nextProductSlot = slot.addingTimeInterval(minimumProductInterval)
            if slot > Date() { try await Task.sleep(for: .seconds(slot.timeIntervalSinceNow)) }
            try Task.checkCancellation()
            guard Date() >= nextRequest else { throw BarcodeLookupError.requestFailed("Product service is rate limited. Wait before retrying.") }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 429 {
                let seconds = min(3600, max(60, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60))
                nextRequest = Date().addingTimeInterval(seconds)
                throw BarcodeLookupError.requestFailed("Rate limit reached. Retry after \(Int(seconds)) seconds.")
            }
            if http.statusCode >= 500 && attempt < 2 {
                try await Task.sleep(for: .seconds(pow(2, Double(attempt)) + Double.random(in: 0...0.3)))
                continue
            }
            if http.statusCode == 404 {
                guard allowUSDAFallback else { throw BarcodeLookupError.notFound }
                return try await usdaFallback(barcode)
            }
            guard http.statusCode == 200 else { throw BarcodeLookupError.requestFailed("Product service returned HTTP \(http.statusCode). Retry later.") }
            let decoded = try JSONDecoder().decode(OFFResponse.self, from: data)
            guard decoded.product != nil else {
                guard allowUSDAFallback else { throw BarcodeLookupError.notFound }
                return try await usdaFallback(barcode)
            }
            let facts: NutritionFacts
            do { facts = try Self.normalize(decoded, barcode: barcode) }
            catch {
                if allowUSDAFallback, let fallback = try? await usdaFallback(barcode) { return fallback }
                throw error
            }
            if allowUSDAFallback, !USDAapiCaller.shared.APIKey.isEmpty, let alternative = try? await usdaFallback(barcode),
               Self.materiallyDisagree(facts, alternative) {
                cache[barcode] = nil
                throw BarcodeLookupError.requestFailed("Open Food Facts and USDA disagree for this exact barcode (\(facts.calories) vs \(alternative.calories) kcal per reference portion), or use different mass/volume bases. Review the package and use manual entry.")
            }
            if offCache.count >= 200 { offCache.removeAll() }
            offCache[barcode] = (Date(), facts)
            // Source-only reads have not performed the barcode flow's USDA
            // conflict comparison; they must not populate that flow's cache.
            if allowUSDAFallback { cache[barcode] = (Date(), facts) }
            return facts
        }
        throw URLError(.badServerResponse)
    }

    private func usdaFallback(_ barcode: String) async throws -> NutritionFacts {
        guard !USDAapiCaller.shared.APIKey.isEmpty else { throw BarcodeLookupError.notFound }
        let response = try await USDAapiCaller.shared.search(query: barcode, dataTypes: ["Branded"])
        let exact = response.foods.filter { $0.gtinUpc.map { Self.sameGTIN($0, barcode) } == true }
        guard exact.count == 1, let food = exact.first else { throw BarcodeLookupError.notFound }
        let n = try await USDAapiCaller.shared.foodDetail(id: food.fdcId).coreValues()
        func required(_ id: Int) throws -> Double {
            guard let value = n[id] else { throw NutritionValidationError.incomplete }; return value
        }
        let c = try required(1008), p = try required(1003), carbs = try required(1005), fat = try required(1004), fiber = try required(1079)
        _ = try ServingNutrition(calories: c, protein: p, carbohydrates: carbs, fat: fat, fiber: fiber)
        let facts = NutritionFacts(name: food.description, calories: Int(c.rounded()), proteinG: p,
            carbsG: carbs, fatG: fat, fiberG: fiber, servingDescription: "100 g · USDA \(food.fdcId) · \(barcode)", barcode: barcode, sourceRecordID: "USDA:\(food.fdcId)", gramsPerServing: 100, caloriesExact: c)
        cache[barcode] = (Date(), facts)
        return facts
    }
}
