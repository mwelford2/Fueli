import Foundation

/// Structured nutrition estimate returned by an AI provider, or entered manually.
struct NutritionAnalysisResult: Codable, Equatable {
    var name: String
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var servingDescription: String

    enum CodingKeys: String, CodingKey {
        case name, calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case servingDescription = "serving_description"
    }

    init(name: String, calories: Int, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double = 0, servingDescription: String) {
        self.name = name
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.servingDescription = servingDescription
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        calories = try container.decode(Int.self, forKey: .calories)
        proteinG = try container.decode(Double.self, forKey: .proteinG)
        carbsG = try container.decode(Double.self, forKey: .carbsG)
        fatG = try container.decode(Double.self, forKey: .fatG)
        // Providers occasionally omit fiber; treat it as 0 rather than failing the parse.
        fiberG = try container.decodeIfPresent(Double.self, forKey: .fiberG) ?? 0
        servingDescription = try container.decode(String.self, forKey: .servingDescription)
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
