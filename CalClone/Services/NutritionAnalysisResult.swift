import Foundation

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

enum AIServiceError: LocalizedError {
    case notConfigured
    case invalidBaseURL
    case requestFailed(String)
    case httpError(Int, String)
    case emptyResponse
    case unparsableResponse(String)

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
        }
    }
}
