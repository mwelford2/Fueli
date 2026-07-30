import Foundation

enum BarcodeLookupError: LocalizedError {
    case notFound
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notFound: return "No product found for that barcode."
        case .requestFailed(let message): return "Lookup failed: \(message)"
        }
    }
}

/// Looks up packaged-food nutrition by barcode using the free, keyless Open Food Facts API.
final class BarcodeLookupService {
    static let shared = BarcodeLookupService()

    func lookup(barcode: String) async throws -> NutritionAnalysisResult {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json") else {
            throw BarcodeLookupError.requestFailed("Invalid barcode.")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BarcodeLookupError.requestFailed("Server error.")
        }

        struct OFFResponse: Decodable {
            struct Product: Decodable {
                struct Nutriments: Decodable {
                    // Per-serving values (present when the product has a serving_size)
                    let energyKcalServing: Double?
                    let proteinsServing: Double?
                    let carbohydratesServing: Double?
                    let fatServing: Double?
                    let fiberServing: Double?
                    // Per-100g fallback values
                    let energyKcal100g: Double?
                    let proteins100g: Double?
                    let carbohydrates100g: Double?
                    let fat100g: Double?
                    let fiber100g: Double?

                    enum CodingKeys: String, CodingKey {
                        case energyKcalServing = "energy-kcal_serving"
                        case proteinsServing = "proteins_serving"
                        case carbohydratesServing = "carbohydrates_serving"
                        case fatServing = "fat_serving"
                        case fiberServing = "fiber_serving"
                        case energyKcal100g = "energy-kcal_100g"
                        case proteins100g = "proteins_100g"
                        case carbohydrates100g = "carbohydrates_100g"
                        case fat100g = "fat_100g"
                        case fiber100g = "fiber_100g"
                    }
                }
                let productName: String?
                let nutriments: Nutriments?
                let servingSize: String?

                enum CodingKeys: String, CodingKey {
                    case productName = "product_name"
                    case nutriments
                    case servingSize = "serving_size"
                }
            }
            let status: Int
            let product: Product?
        }

        let decoded = try JSONDecoder().decode(OFFResponse.self, from: data)
        guard decoded.status == 1, let product = decoded.product, let nutriments = product.nutriments else {
            throw BarcodeLookupError.notFound
        }

        let name = product.productName?.isEmpty == false ? product.productName! : "Scanned item"

        // Prefer per-serving values when available; fall back to per-100g.
        let useServing = nutriments.energyKcalServing != nil && product.servingSize != nil
        let calories: Int
        let protein, carbs, fat, fiber: Double
        let serving: String

        if useServing {
            calories = Int((nutriments.energyKcalServing ?? 0).rounded())
            protein = nutriments.proteinsServing ?? 0
            carbs = nutriments.carbohydratesServing ?? 0
            fat = nutriments.fatServing ?? 0
            fiber = nutriments.fiberServing ?? 0
            serving = product.servingSize!
        } else {
            calories = Int((nutriments.energyKcal100g ?? 0).rounded())
            protein = nutriments.proteins100g ?? 0
            carbs = nutriments.carbohydrates100g ?? 0
            fat = nutriments.fat100g ?? 0
            fiber = nutriments.fiber100g ?? 0
            serving = "100 g"
        }

        return NutritionAnalysisResult(
            name: name,
            calories: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            fiberG: fiber,
            servingDescription: serving
        )
    }
}
