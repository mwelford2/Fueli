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
                    let energyKcal100g: Double?
                    let proteins100g: Double?
                    let carbohydrates100g: Double?
                    let fat100g: Double?
                    let fiber100g: Double?

                    enum CodingKeys: String, CodingKey {
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
        let calories = Int((nutriments.energyKcal100g ?? 0).rounded())
        let serving = product.servingSize ?? "100 g"

        return NutritionAnalysisResult(
            name: name,
            calories: calories,
            proteinG: nutriments.proteins100g ?? 0,
            carbsG: nutriments.carbohydrates100g ?? 0,
            fatG: nutriments.fat100g ?? 0,
            fiberG: nutriments.fiber100g ?? 0,
            servingDescription: "\(serving) (per 100g shown)"
        )
    }
}
