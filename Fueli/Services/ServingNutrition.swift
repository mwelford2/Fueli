import Foundation

/// Full precision arithmetic; rounding occurs only at the legacy integer calorie boundary.
struct ServingNutrition: Equatable {
    let calories: Double
    let protein: Double
    let carbohydrates: Double
    let fat: Double
    let fiber: Double

    init(calories: Double, protein: Double, carbohydrates: Double, fat: Double, fiber: Double) throws {
        guard [calories, protein, carbohydrates, fat, fiber].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1_000_000 }) else {
            throw NutritionValidationError.invalidValues
        }
        self.calories = calories
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
        self.fiber = fiber
    }

    func scaled(by servings: Double) throws -> ServingNutrition {
        guard servings.isFinite, servings > 0, servings <= 10_000 else { throw NutritionValidationError.invalidQuantity }
        return try ServingNutrition(calories: calories * servings, protein: protein * servings,
                                    carbohydrates: carbohydrates * servings, fat: fat * servings, fiber: fiber * servings)
    }

    static func grams(ounces: Double) -> Double { ounces * 28.349523125 }
    static func milliliters(usFluidOunces: Double) -> Double { usFluidOunces * 29.5735295625 }
}

enum NutritionValidationError: LocalizedError {
    case invalidValues, invalidQuantity, incomplete
    var errorDescription: String? {
        switch self {
        case .invalidValues: return "Enter finite, nonnegative nutrition values."
        case .invalidQuantity: return "Enter a serving amount greater than zero."
        case .incomplete: return "This record is missing essential nutrition. Review the package and enter nutrition manually."
        }
    }
}
