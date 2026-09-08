import Foundation

//TODO: Add USDA API Call from AI response. Needs to send description to API and get 5 most relevant responses for AI to evaluate.

class USDAapiCaller {
    static let shared = USDAapiCaller()
    
    let APIKey: String
    private var imageBase64: String?

    init() {
        self.APIKey = Bundle.main.object(forInfoDictionaryKey: "USDA_API_KEY") as? String ?? ""
    }
    
    /// Parses a raw model reply into the structured decomposition. Throws
    /// `unparsableResponse` if the JSON can't be recovered.
    static func parseNutritionResult(from raw: String) throws -> NutritionAnalysisResult {
        let clean = NutritionAnalysisResult.stripMarkdownFences(raw)
        guard let data = clean.data(using: .utf8) else { throw AIServiceError.unparsableResponse(raw) }
        do {
            return try JSONDecoder().decode(NutritionAnalysisResult.self, from: data)
        } catch {
            print("parseNutritionResult decode failed:", error)
            throw AIServiceError.unparsableResponse(raw)
        }
    }

    /// Resolves a finalized decomposition into concrete nutrition numbers via the USDA API.
    func analyzeFood(result: NutritionAnalysisResult, imageBase64: String?) async throws -> NutritionFacts {
        self.imageBase64 = imageBase64

        let components = result.components.filter { !$0.negligible }
        guard !components.isEmpty else { throw AIServiceError.emptyResponse }

        var indexedFacts: [(Int, NutritionFacts)] = []
        try await withThrowingTaskGroup(of: (Int, NutritionFacts).self) { group in
            for (index, component) in components.enumerated() {
                group.addTask {
                    let searchResults = try await self.searchWithFallbacks(
                        primaryQuery: component.fdcQuery,
                        fallbackQueries: component.fallbackQueries
                    )
                    let facts = try await self.getNutritionFacts(
                        decodedResponse: searchResults,
                        query: component.fdcQuery,
                        component: component
                    )
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
            servingDescription: servingLine
        )
        return facts
    }
    
    struct FDCSearchResponse: Codable {
        let foods: [FDCFood]
    }

    struct FDCFood: Codable {
        let fdcId: Int
        let description: String
        let nutrients: [FDCNutrient]?

        enum CodingKeys: String, CodingKey {
            case fdcId, description
            case nutrients = "foodNutrients"
        }
    }

    struct FDCNutrient: Codable, Identifiable{
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
        let API_KEY = self.APIKey
        let BASE_URL = "https://api.nal.usda.gov/fdc/v1/foods/search"

        guard var components = URLComponents(string: BASE_URL) else { throw URLError(.badURL) }
        var queryItems = [
            URLQueryItem(name: "api_key", value: API_KEY),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: String(Self.searchPageSize)),
            URLQueryItem(name: "sortBy", value: "score"),
            URLQueryItem(name: "sortOrder", value: "desc")
        ]
        for dataType in dataTypes ?? Self.defaultDataTypes {
            queryItems.append(URLQueryItem(name: "dataType", value: dataType))
        }
        components.queryItems = queryItems

        guard let URL = components.url else { throw URLError(.badURL) }

        var lastStatusCode = -1
        var lastNetworkError: Swift.Error?
        for attempt in 1...Self.maxSearchAttempts {
            do {
                let (data, response) = try await URLSession.shared.data(from: URL)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if httpResponse.statusCode == 200 {
                    return try JSONDecoder().decode(FDCSearchResponse.self, from: data)
                }

                lastStatusCode = httpResponse.statusCode
            } catch let error as URLError {
                // Connection-level failures (proxy/VPN interference, timeouts, DNS,
                // offline). A transient blip might clear on retry.
                lastNetworkError = error
            }

            // 400/429/5xx from FDC are usually transient; back off and retry.
            if attempt < Self.maxSearchAttempts {
                let delayNanos = UInt64(0.4 * pow(2.0, Double(attempt - 1)) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delayNanos)
            }
        }

        if let lastNetworkError {
            print("USDA search unreachable after \(Self.maxSearchAttempts) attempts for query '\(query)': \(lastNetworkError)")
        } else {
            print("USDA search failed after \(Self.maxSearchAttempts) attempts (last status \(lastStatusCode)) for query: \(query)")
        }
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

    func evalTopFoods(foods: [FDCFood], query: String) async throws -> FDCFood {
        guard !foods.isEmpty else { throw AIServiceError.emptyResponse }
        guard foods.count > 1 else { return foods[0] }

        let candidateList = foods.enumerated()
            .map { index, food in "\(index): \(food.description)" }
            .joined(separator: "\n")

        let prompt = """
        You are a food-matching classifier. You will be given the name of a food item and up to \(foods.count) candidate descriptions from a USDA nutrition database, indexed starting at 0.

        Your job: determine which candidate best matches the food, and output ONLY that index number.

        MATCHING CRITERIA (in priority order):
        1. Core food identity — is it the same base food? (e.g. "chicken breast" vs "chicken thigh" vs "chicken nuggets" are different foods)
        2. Preparation method — grilled, fried, baked, raw, steamed, etc.
        3. Form/cut — whole, sliced, diced, shredded, ground
        4. Additional qualifiers — fat content (whole/skim/2%), skin on/off, bone in/out, seasoning, brand vs generic

        Match on the most specific overlapping terms, not just the first shared word.

        TIE-BREAKING / AMBIGUITY:
        - If two candidates seem equally close, prefer the one that matches preparation method over the one that only matches the base ingredient.
        - You must always pick exactly one index, even if no candidate is a perfect match — choose the closest.

        OUTPUT FORMAT (strict):
        Respond with a single number from 0 to \(foods.count - 1).
        No words, no punctuation, no explanation, no newline before or after.

        ---

        Food item: \(query)

        Candidate descriptions:
        \(candidateList)
        """

        let response = try await AINutritionService.shared.runRawText(userText: "Match the food item to the best candidate.", imageBase64: nil, prompt: prompt)
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let responseIndex = Int(trimmed), foods.indices.contains(responseIndex) else {
            return foods[0]
        }
        return foods[responseIndex]
    }

    func getNutritionFacts(decodedResponse: FDCSearchResponse, query: String, component: Component) async throws -> NutritionFacts {
        guard !decodedResponse.foods.isEmpty else { throw AIServiceError.emptyResponse }

        let topFood = try await evalTopFoods(foods: decodedResponse.foods, query: query)

        let foodNutrients = topFood.nutrients ?? []
        let nutrientsById = Dictionary(
            foodNutrients.map { ($0.nutrientId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // The FDC *search* endpoint normalizes every foodNutrient value to per-100g,
        // including Branded items ("Calculated from value per serving size measure").
        // Scale to the portion the user actually ate.
        let per100 = (
            calories: nutrientsById[1008]?.value ?? 0,
            protein: nutrientsById[1003]?.value ?? 0,
            carbs: nutrientsById[1005]?.value ?? 0,
            fat: nutrientsById[1004]?.value ?? 0,
            fiber: nutrientsById[1079]?.value ?? 0
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
            servingDescription: quantityText
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
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var servingDescription: String

    init(name: String, calories: Int, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double = 0, servingDescription: String) {
        self.name = name
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.servingDescription = servingDescription
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
            servingDescription: servingDescription
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
            servingDescription: lhs.servingDescription + "; " + rhs.servingDescription
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
            servingDescription: lhs.servingDescription
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
        case .usdaUnreachable:
            return "Couldn't reach the USDA nutrition database. Check your internet connection — if you're on a VPN or proxy, try turning it off and retrying."
        }
    }
}
