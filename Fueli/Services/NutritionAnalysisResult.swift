import Foundation

class USDAapiCaller {
    static let shared = USDAapiCaller()
    
    static let personalKeyAccount = "usda.fdc-api-key"
    private let injectedAPIKey: String?
    private let session: URLSession

    /// Read at request time so changing a personal key does not require restarting.
    var APIKey: String {
        injectedAPIKey ?? Self.resolveAPIKey(userKey: KeychainStore.read(account: Self.personalKeyAccount),
            bundledKey: Bundle.main.object(forInfoDictionaryKey: "USDA_API_KEY") as? String)
    }

    static func resolveAPIKey(userKey: String?, bundledKey: String?) -> String {
        for candidate in [userKey, bundledKey] {
            let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty, !value.contains("$("), value.count <= 512,
               !value.contains(where: { $0.isWhitespace }) { return value }
        }
        return ""
    }

    init(apiKey: String? = nil, session: URLSession = .shared) {
        self.injectedAPIKey = apiKey
        self.session = session
    }
    
    /// Parses a raw model reply into the structured decomposition. Throws
    /// `unparsableResponse` if the JSON can't be recovered.
    static func parseNutritionResult(from raw: String) throws -> NutritionAnalysisResult {
        let clean = NutritionAnalysisResult.stripMarkdownFences(raw)
        guard let data = clean.data(using: .utf8) else { throw AIServiceError.unparsableResponse(raw) }
        do {
            let result = try JSONDecoder().decode(NutritionAnalysisResult.self, from: data)
            guard !result.components.isEmpty, result.components.count <= 50,
                  result.components.allSatisfy({ component in
                      component.estimatedGrams.isFinite && component.estimatedGrams > 0 && component.estimatedGrams <= 100000 &&
                      !component.fdcQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                      component.fdcQuery.count <= 300 && component.fallbackQueries.count <= 3 &&
                      component.fallbackQueries.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 300 } &&
                      component.quantity.amount.isFinite && component.quantity.amount > 0 &&
                      component.confidence.isFinite && (0...1).contains(component.confidence) &&
                      component.preferredDataTypes.allSatisfy { ["Foundation", "SR Legacy", "Survey (FNDDS)", "Branded"].contains($0) }
                  }) else { throw NutritionValidationError.invalidQuantity }
            return result
        } catch {
            throw AIServiceError.unparsableResponse(raw)
        }
    }

    /// Resolves a finalized decomposition into concrete nutrition numbers via the USDA API.
    func analyzeFood(result: NutritionAnalysisResult, imageBase64: String?, selections: [String: FDCFood] = [:]) async throws -> NutritionFacts {

        let components = result.components.filter { !$0.negligible }
        guard !components.isEmpty else { throw AIServiceError.emptyResponse }

        var indexedFacts: [(Int, NutritionFacts)] = []
        try await withThrowingTaskGroup(of: (Int, NutritionFacts).self) { group in
            for (index, component) in components.enumerated() {
                group.addTask {
                    let candidates: FDCSearchResponse
                    if let selection = selections[Self.identity(for: component)] {
                        candidates = FDCSearchResponse(foods: [selection])
                    } else {
                        var found = FDCSearchResponse(foods: [])
                        for query in ([component.fdcQuery] + component.fallbackQueries).prefix(4) {
                            let batch = try await self.search(query: query, dataTypes: component.preferredDataTypes.isEmpty ? nil : component.preferredDataTypes)
                            let defensible = Self.rankedMatches(foods: batch.foods, query: Self.resolutionQuery(for: component))
                            if !defensible.isEmpty { found = FDCSearchResponse(foods: defensible); break }
                        }
                        candidates = found
                    }
                    let facts = try await self.getNutritionFacts(decodedResponse: candidates,
                        query: Self.resolutionQuery(for: component), component: component)
                    return (index, facts)
                }
            }
            for try await result in group {
                indexedFacts.append(result)
            }
        }

        let sorted = indexedFacts.sorted { $0.0 < $1.0 }.map(\.1)
        guard let first = sorted.first else { throw AIServiceError.emptyResponse }
        let combined = sorted.dropFirst().reduce(first, +)
        // Prefer the model's natural dish name over the concatenated component names,
        // and surface the whole-meal portion in the serving line.
        let name = result.dishName.trimmingCharacters(in: .whitespacesAndNewlines)
        let totalGrams = components.reduce(0) { $0 + max($1.estimatedGrams, 0) }
        let servingLine = totalGrams > 0
            ? "\(Int(totalGrams.rounded())) g total"
            : combined.servingDescription
        var facts = name.isEmpty ? combined : combined.renamed(to: name)
        facts = NutritionFacts(
            name: facts.name,
            calories: facts.calories,
            proteinG: facts.proteinG,
            carbsG: facts.carbsG,
            fatG: facts.fatG,
            fiberG: facts.fiberG,
            servingDescription: servingLine, gramsPerServing: totalGrams > 0 ? totalGrams : nil,
            ingredients: zip(sorted, components).map { facts, component in
                LibraryIngredient(id: UUID(), sourceRecordID: facts.sourceRecordID, gramsPerServing: facts.gramsPerServing,
                    preparation: component.preparation, measureBasis: component.measureBasis, quantityIsEstimated: true,
                    name: facts.name, servings: 1, calories: facts.caloriesValue, protein: facts.proteinG,
                    carbs: facts.carbsG, fat: facts.fatG, fiber: facts.fiberG)
            }, caloriesExact: facts.caloriesValue
        )
        return facts
    }
    
    struct FDCSearchResponse: Codable {
        let foods: [FDCFood]
    }

    struct FDCFood: Codable, Equatable {
        let fdcId: Int
        let description: String
        let gtinUpc: String?
        let dataType: String?
        let nutrients: [FDCNutrient]?

        enum CodingKeys: String, CodingKey {
            case fdcId, description, gtinUpc, dataType
            case nutrients = "foodNutrients"
        }
    }

    struct FDCNutrient: Codable, Identifiable, Equatable {
        var id: Int { nutrientId }
        
        let nutrientId: Int
        let nutrientName: String
        let nutrientNumber: String
        let unitName: String
        let value: Double?
        let foodNutrientId: Int?
        
        // Optional fields from USDA API (captured but not required for core functionality)
        let derivationCode: String?
        let derivationDescription: String?
        let rank: Int?
        let percentDailyValue: Int?
    }
    
    /// Data types accepted, in USDA's own preference order for whole/generic ingredients:
    /// Foundation and SR Legacy are lab-analyzed generic foods (most reliable for "chicken
    /// breast, grilled"-style queries); Survey (FNDDS) covers as-eaten/prepared dishes;
    /// Branded is included last since a bare ingredient query should prefer generic data
    /// over a specific product unless nothing else matches.
    private static let defaultDataTypes = ["Foundation", "SR Legacy", "Survey (FNDDS)", "Branded"]

    /// Minimum number of results required before we trust the batch enough to hand it to
    /// the classifier — below this, a fallback query is tried instead.
    private static let minAcceptableResults = 3
    private static let searchPageSize = 5

    /// The USDA FDC `/foods/search` endpoint intermittently returns HTTP 400/429/5xx for
    /// requests that are otherwise valid (the same request often succeeds on the next
    /// attempt). Retry a few times with backoff before giving up.
    private static let maxSearchAttempts = 4

    func search(query: String, dataTypes: [String]? = nil) async throws -> FDCSearchResponse {
        guard !APIKey.isEmpty else { throw AIServiceError.requestFailed("Add your USDA API key in Settings → Food Database before looking up foods.") }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.count <= 300,
              (dataTypes ?? Self.defaultDataTypes).allSatisfy({ Self.defaultDataTypes.contains($0) }) else {
            throw AIServiceError.requestFailed("Enter a valid food query and supported USDA data types.")
        }
        let API_KEY = self.APIKey
        let BASE_URL = "https://api.nal.usda.gov/fdc/v1/foods/search"

        guard var components = URLComponents(string: BASE_URL) else { throw URLError(.badURL) }
        var queryItems = [
            URLQueryItem(name: "api_key", value: API_KEY),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: String(Self.searchPageSize))
        ]
        for dataType in dataTypes ?? Self.defaultDataTypes {
            queryItems.append(URLQueryItem(name: "dataType", value: dataType))
        }
        components.queryItems = queryItems

        guard let URL = components.url else { throw URLError(.badURL) }

        var lastNetworkError: Swift.Error?
        for attempt in 1...Self.maxSearchAttempts {
            do {
                var request = URLRequest(url: URL)
                request.timeoutInterval = 20
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if httpResponse.statusCode == 200 {
                    return try JSONDecoder().decode(FDCSearchResponse.self, from: data)
                }

                if httpResponse.statusCode == 429 { throw AIServiceError.requestFailed("USDA rate limit reached. Wait before retrying.") }
                guard httpResponse.statusCode >= 500 || httpResponse.statusCode == 408 else {
                    throw AIServiceError.requestFailed("USDA rejected the search (HTTP \(httpResponse.statusCode)). Check your API key and query.")
                }
            } catch let error as URLError {
                // Connection-level failures (proxy/VPN interference, timeouts, DNS,
                // offline). A transient blip might clear on retry.
                if error.code == .cancelled { throw error }
                lastNetworkError = error
            }

            // Retry connection failures and 408/5xx only; invalid requests and rate limits fail clearly.
            if attempt < Self.maxSearchAttempts {
                let delayNanos = UInt64((0.4 * pow(2.0, Double(attempt - 1)) + Double.random(in: 0...0.2)) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delayNanos)
            }
        }

        if let lastNetworkError { throw AIServiceError.requestFailed("USDA is unavailable: " + lastNetworkError.localizedDescription) }
        throw AIServiceError.usdaUnreachable
    }

    /// Searches the primary query, then each fallback in order, stopping at the first
    /// batch with enough results to be worth ranking. Falls back to whatever the primary
    /// query returned (even if sparse) if every fallback also comes up short.
    func searchWithFallbacks(primaryQuery: String, fallbackQueries: [String]) async throws -> FDCSearchResponse {
        var best: FDCSearchResponse?
        for query in [primaryQuery] + fallbackQueries {
            let result = try await search(query: query)
            if result.foods.count >= Self.minAcceptableResults {
                return result
            }
            if best == nil || result.foods.count > (best?.foods.count ?? 0) {
                best = result
            }
        }
        guard let best else { throw AIServiceError.emptyResponse }
        return best
    }

    /// Deterministic, conservative matching. Ambiguous or incomplete identities need review;
    /// no model is allowed to force a closest candidate or invent a database match.
    static func resolutionQuery(for component: Component) -> String {
        let basis = component.measureBasis == .raw ? " raw" : component.measureBasis == .cooked ? " cooked" : ""
        let preparation = (component.preparation ?? "").lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        let identityTerms: Set<String> = ["grilled", "fried", "roasted", "baked", "boiled", "steamed", "smoked", "skinless", "boneless", "salted", "unsalted"]
        let requiredPreparation = preparation.filter { identityTerms.contains($0) }.joined(separator: " ")
        return [component.label + basis, requiredPreparation].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func identity(for component: Component) -> String {
        [component.label, component.preparation ?? "", component.measureBasis.rawValue].joined(separator: "|")
    }

    static func rankedMatches(foods: [FDCFood], query: String) -> [FDCFood] {
        func tokens(_ text: String) -> Set<String> {
            let ignored: Set<String> = ["and", "with", "food", "the", "a", "of"]
            let aliases = ["bananas": "banana", "apples": "apple", "carrots": "carrot", "onions": "onion", "potatoes": "potato", "tomatoes": "tomato", "breasts": "breast", "eggs": "egg", "avocados": "avocado"]
            return Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init).map { aliases[$0] ?? $0 }.filter { !ignored.contains($0) })
        }
        let required = tokens(query)
        guard !required.isEmpty else { return [] }
        let matches = foods.filter { required.isSubset(of: tokens($0.description)) }
        let order = ["Foundation", "SR Legacy", "Survey (FNDDS)", "Branded"]
        func score(_ food: FDCFood) -> Int {
            (order.firstIndex(of: food.dataType ?? "") ?? 4) * 100 + tokens(food.description).subtracting(required).count
        }
        guard let best = matches.map(score).min() else { return [] }
        return matches.filter { score($0) == best }
    }

    static func matchingFood(foods: [FDCFood], query: String) throws -> FDCFood {
        let matches = rankedMatches(foods: foods, query: query)
        guard matches.count == 1, let match = matches.first else {
            throw AIServiceError.requestFailed("USDA could not identify one unambiguous match for this ingredient. Correct its name and preparation, or use manual entry.")
        }
        return match
    }

    func evalTopFoods(foods: [FDCFood], query: String) async throws -> FDCFood {
        try Self.matchingFood(foods: foods, query: query)
    }

    struct FoodDetail: Decodable {
        struct Value: Decodable {
            struct Nutrient: Decodable { let id: Int; let unitName: String }
            let nutrient: Nutrient
            let amount: Double?
        }
        let foodNutrients: [Value]
        func coreValues() throws -> [Int: Double] {
            var values: [Int: Double] = [:]
            for entry in foodNutrients {
                guard let amount = entry.amount, amount.isFinite, amount >= 0 else { continue }
                let unit = entry.nutrient.unitName.lowercased()
                switch entry.nutrient.id {
                case 1003, 1004, 1005, 1079:
                    guard unit == "g", amount <= 100 else { throw NutritionValidationError.invalidValues }
                    values[entry.nutrient.id] = amount
                case 1008, 2047, 2048:
                    guard unit == "kcal", amount <= 1000 else { throw NutritionValidationError.invalidValues }
                    values[entry.nutrient.id] = amount
                default: break
                }
            }
            // Foundation Foods replaced legacy Energy (1008) with Atwater values.
            // Prefer the food-specific factors when both are available; never sum energies.
            if values[1008] == nil { values[1008] = values[2048] ?? values[2047] }
            if values[1008] == nil,
               let energy = foodNutrients.first(where: { $0.nutrient.id == 1062 && $0.nutrient.unitName.lowercased() == "kj" }),
               let amount = energy.amount, amount.isFinite, amount >= 0, amount <= 4184 { values[1008] = amount / 4.184 }
            return values
        }
    }

    func foodDetail(id: Int) async throws -> FoodDetail {
        guard id > 0, !APIKey.isEmpty else { throw AIServiceError.requestFailed("Add your USDA API key in Settings → Food Database before looking up foods.") }
        var url = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/food/\(id)")!
        url.queryItems = [URLQueryItem(name: "api_key", value: APIKey)]
        var request = URLRequest(url: url.url!); request.timeoutInterval = 20
        for attempt in 0..<3 {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 429 { throw AIServiceError.requestFailed("USDA rate limit reached. Wait and retry.") }
            if http.statusCode >= 500 && attempt < 2 {
                try await Task.sleep(for: .seconds(pow(2, Double(attempt)) + Double.random(in: 0...0.2))); continue
            }
            guard http.statusCode == 200 else { throw AIServiceError.usdaUnreachable }
            return try JSONDecoder().decode(FoodDetail.self, from: data)
        }
        throw AIServiceError.usdaUnreachable
    }

    func getNutritionFacts(decodedResponse: FDCSearchResponse, query: String, component: Component) async throws -> NutritionFacts {
        guard !decodedResponse.foods.isEmpty else { throw AIServiceError.requestFailed("No suitable USDA food matched this ingredient and preparation. Return to review or use manual entry.") }

        let candidates = Self.rankedMatches(foods: decodedResponse.foods, query: query)
        if candidates.count > 1 { throw AIServiceError.ambiguousFood(component, candidates) }
        let topFood = try Self.matchingFood(foods: candidates, query: component.label)

        let nutrientValues = try await foodDetail(id: topFood.fdcId).coreValues()

        // The FDC *search* endpoint normalizes every foodNutrient value to per-100g,
        // including Branded items ("Calculated from value per serving size measure").
        // Scale to the portion the user actually ate.
        guard [1008, 1003, 1005, 1004, 1079].allSatisfy({ id in
            nutrientValues[id].map { $0.isFinite && $0 >= 0 } ?? false
        }) else { throw NutritionValidationError.incomplete }
        guard component.estimatedGrams.isFinite, component.estimatedGrams > 0 else {
            throw NutritionValidationError.invalidQuantity
        }
        let per100 = (
            calories: nutrientValues[1008] ?? 0,
            protein: nutrientValues[1003] ?? 0,
            carbs: nutrientValues[1005] ?? 0,
            fat: nutrientValues[1004] ?? 0,
            fiber: nutrientValues[1079] ?? 0
        )
        // Guard against a missing/zero estimate — fall back to a single 100 g serving
        // rather than logging zeros.
        let grams = component.estimatedGrams > 0 ? component.estimatedGrams : 100
        let scale = grams / 100.0

        let quantityText: String = {
            let q = component.quantity
            guard q.amount > 0, !q.unit.isEmpty else { return "\(Int(grams.rounded())) g" }
            let amount = q.amount == q.amount.rounded()
                ? String(Int(q.amount))
                : String(format: "%.2g", q.amount)
            return "\(amount) \(q.unit) (\(Int(grams.rounded())) g)"
        }()

        return NutritionFacts(
            name: topFood.description,
            calories: Int((per100.calories * scale).rounded()),
            proteinG: per100.protein * scale,
            carbsG: per100.carbs * scale,
            fatG: per100.fat * scale,
            fiberG: per100.fiber * scale,
            servingDescription: quantityText, sourceRecordID: "USDA:\(topFood.fdcId)", gramsPerServing: grams, caloriesExact: per100.calories * scale
        )
    }
}

enum MatchStrategy: String, Codable, Equatable {
    case composite, ingredients
}

enum MeasureBasis: String, Codable, Equatable {
    case raw, cooked, as_packaged
}

struct Quantity: Codable, Equatable {
    var amount: Double
    var unit: String
}

struct Component: Codable, Equatable {
    var label: String
    var fdcQuery: String
    var fallbackQueries: [String]
    var preferredDataTypes: [String]
    var brand: String?
    var quantity: Quantity
    var estimatedGrams: Double
    var preparation: String?
    var measureBasis: MeasureBasis
    var negligible: Bool
    var confidence: Double

    enum CodingKeys: String, CodingKey {
        case label, brand, quantity, negligible, confidence, preparation
        case fdcQuery = "fdc_query"
        case fallbackQueries = "fallback_queries"
        case preferredDataTypes = "preferred_data_types"
        case estimatedGrams = "estimated_grams"
        case measureBasis = "measure_basis"
    }
}

struct NutritionAnalysisResult: Codable, Equatable {
    var dishName: String
    var matchStrategy: MatchStrategy
    var composite: Component?
    var components: [Component]
    var totalEstimatedGrams: Double
    var confidence: Double
    var needsConfirmation: Bool
    var clarifyingQuestion: String?
    var assumptions: [String]

    enum CodingKeys: String, CodingKey {
        case composite, components, confidence, assumptions
        case dishName = "dish_name"
        case matchStrategy = "match_strategy"
        case totalEstimatedGrams = "total_estimated_grams"
        case needsConfirmation = "needs_confirmation"
        case clarifyingQuestion = "clarifying_question"
    }
}

/// Simple nutrition-facts container used by the barcode, manual entry, and confirm flows.
struct NutritionFacts: Identifiable, Equatable {
    var id: String { name + servingDescription }
    var name: String
    var calories: Int
    var caloriesExact: Double?
    var caloriesValue: Double { caloriesExact ?? Double(calories) }
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var servingDescription: String
    var ingredients: [LibraryIngredient]?
    var barcode: String?
    var sourceRecordID: String?
    var gramsPerServing: Double?
    var millilitersPerServing: Double?

    init(name: String, calories: Int, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double = 0, servingDescription: String, barcode: String? = nil, sourceRecordID: String? = nil, gramsPerServing: Double? = nil, millilitersPerServing: Double? = nil, ingredients: [LibraryIngredient]? = nil, caloriesExact: Double? = nil) {
        self.name = name
        self.calories = calories
        self.caloriesExact = caloriesExact
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.servingDescription = servingDescription
        self.ingredients = ingredients
        self.barcode = barcode
        self.sourceRecordID = sourceRecordID
        self.gramsPerServing = gramsPerServing
        self.millilitersPerServing = millilitersPerServing
    }
}

extension NutritionFacts {
    /// Same numbers, different display name.
    func renamed(to newName: String) -> NutritionFacts {
        NutritionFacts(
            name: newName,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            fiberG: fiberG,
            servingDescription: servingDescription, caloriesExact: caloriesValue
        )
    }

    static func + (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        NutritionFacts(
            name: "\(lhs.name), \(rhs.name)",
            calories: lhs.calories + rhs.calories,
            proteinG: lhs.proteinG + rhs.proteinG,
            carbsG: lhs.carbsG + rhs.carbsG,
            fatG: lhs.fatG + rhs.fatG,
            fiberG: lhs.fiberG + rhs.fiberG,
            servingDescription: lhs.servingDescription + "; " + rhs.servingDescription,
            caloriesExact: lhs.caloriesValue + rhs.caloriesValue
        )
    }

    static func - (lhs: NutritionFacts, rhs: NutritionFacts) -> NutritionFacts {
        NutritionFacts(
            name: lhs.name,
            calories: lhs.calories - rhs.calories,
            proteinG: lhs.proteinG - rhs.proteinG,
            carbsG: lhs.carbsG - rhs.carbsG,
            fatG: lhs.fatG - rhs.fatG,
            fiberG: lhs.fiberG - rhs.fiberG,
            servingDescription: lhs.servingDescription, caloriesExact: lhs.caloriesValue - rhs.caloriesValue
        )
    }
}

extension NutritionAnalysisResult {
    /// Strips a leading ```json (or plain ```) fence and trailing ``` from an AI response.
    static func stripMarkdownFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        // Drop the opening fence line (e.g. "```json\n")
        if let newline = s.firstIndex(of: "\n") {
            s = String(s[s.index(after: newline)...])
        } else {
            s = String(s.dropFirst(3)) // no newline — just drop the backticks
        }
        // Drop the trailing fence
        if s.hasSuffix("```") {
            s = String(s.dropLast(3))
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum AIServiceError: LocalizedError {
    case notConfigured
    case invalidBaseURL
    case requestFailed(String)
    case httpError(Int, String)
    case emptyResponse
    case unparsableResponse(String)
    case usdaUnreachable
    case ambiguousFood(Component, [USDAapiCaller.FDCFood])

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No AI provider is configured yet. Add an API key and base URL in Settings."
        case .invalidBaseURL:
            return "The configured base URL is invalid."
        case .requestFailed(let message):
            return "Request failed: \(message)"
        case .httpError(let code, let message):
            return "Provider returned HTTP \(code): \(message)"
        case .emptyResponse:
            return "The AI provider returned an empty response."
        case .unparsableResponse(let raw):
            return "Couldn't parse a nutrition estimate from the response: \(raw.prefix(200))"
        case .ambiguousFood:
            return "Several USDA records could match. Choose a food or return to ingredient review."
        case .usdaUnreachable:
            return "Couldn't reach the USDA nutrition database. Check your internet connection — if you're on a VPN or proxy, try turning it off and retrying."
        }
    }
}

/// Stage-one contract deliberately has no nutrient values or database queries.
struct PhotoMealDescription: Codable {
    struct Item: Codable {
        var name: String
        var estimatedGrams: Double
        var preparation: String
        var measureBasis: MeasureBasis
    }
    var dishName: String
    var observedFacts: [String]
    var estimates: [String]
    var unknowns: [String]
    var items: [Item]
    var clarifyingQuestion: String?

    func reviewResult() throws -> NutritionAnalysisResult {
        guard !items.isEmpty, items.count <= 50, !dishName.isEmpty,
              items.allSatisfy({ !$0.name.isEmpty && $0.estimatedGrams.isFinite && $0.estimatedGrams > 0 && $0.estimatedGrams <= 100000 }) else {
            throw NutritionValidationError.invalidQuantity
        }
        return NutritionAnalysisResult(dishName: dishName, matchStrategy: .ingredients, composite: nil,
            components: items.map { item in
                Component(label: item.name, fdcQuery: item.name, fallbackQueries: [],
                    preferredDataTypes: ["Foundation", "SR Legacy", "Survey (FNDDS)"], brand: nil,
                    quantity: Quantity(amount: item.estimatedGrams, unit: "g"), estimatedGrams: item.estimatedGrams,
                    preparation: item.preparation, measureBasis: item.measureBasis, negligible: false, confidence: 0.5)
            }, totalEstimatedGrams: items.reduce(0) { $0 + $1.estimatedGrams }, confidence: 0.5,
            needsConfirmation: clarifyingQuestion?.isEmpty == false, clarifyingQuestion: clarifyingQuestion,
            assumptions: observedFacts.map { "Observed: " + $0 } + estimates.map { "Estimated: " + $0 } + unknowns.map { "Unknown: " + $0 })
    }
}

/// Provider-enforced JSON shapes. Numeric and identity validation remains local.
/// All properties are required, with nullable fields for optional information.
enum MealOutputContract {
    case description, lookupPlan

    var name: String { self == .description ? "meal_description" : "usda_lookup_plan" }
    var schema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let number: [String: Any] = ["type": "number"]
        let nullableString: [String: Any] = ["type": ["string", "null"]]
        let strings: [String: Any] = ["type": "array", "items": string]
        let basis: [String: Any] = ["type": "string", "enum": ["raw", "cooked", "as_packaged"]]
        func object(_ properties: [String: Any]) -> [String: Any] {
            ["type": "object", "properties": properties, "required": properties.keys.sorted(), "additionalProperties": false]
        }
        if self == .description {
            return object(["dishName": string, "observedFacts": strings, "estimates": strings, "unknowns": strings,
                "items": ["type": "array", "items": object(["name": string, "estimatedGrams": number,
                    "preparation": string, "measureBasis": basis])], "clarifyingQuestion": nullableString])
        }
        let component = object(["label": string, "fdc_query": string, "fallback_queries": strings,
            "preferred_data_types": ["type": "array", "items": ["type": "string", "enum": ["Foundation", "SR Legacy", "Survey (FNDDS)", "Branded"]]],
            "brand": nullableString, "quantity": object(["amount": number, "unit": string]),
            "estimated_grams": number, "preparation": nullableString, "measure_basis": basis,
            "negligible": ["type": "boolean"], "confidence": number])
        return object(["dish_name": string, "match_strategy": ["type": "string", "enum": ["ingredients", "composite"]],
            "composite": ["anyOf": [component, ["type": "null"]]], "components": ["type": "array", "items": component],
            "total_estimated_grams": number, "confidence": number, "needs_confirmation": ["type": "boolean"],
            "clarifying_question": nullableString, "assumptions": strings])
    }
}
