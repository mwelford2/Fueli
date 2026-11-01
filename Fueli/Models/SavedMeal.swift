import Foundation
import SwiftData

@Model
final class SavedMeal {
    var id: UUID
    var name: String
    var calories: Int
    var caloriesExact: Double?
    var caloriesValue: Double { caloriesExact ?? Double(calories) }
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double = 0
    var servingDescription: String
    @Attribute(.externalStorage) var photoData: Data?
    var ingredientData: Data?
    var canonicalBarcode: String?
    var nutritionSourceID: String?
    var gramsPerServing: Double?
    var millilitersPerServing: Double?
    var isFavorite: Bool = false
    var lastLoggedAt: Date?
    var createdAt: Date
    var timesLogged: Int

    init(
        id: UUID = UUID(),
        name: String,
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double = 0,
        servingDescription: String = "1 serving",
        photoData: Data? = nil,
        createdAt: Date = Date(),
        timesLogged: Int = 0
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.servingDescription = servingDescription
        self.photoData = photoData
        self.createdAt = createdAt
        self.timesLogged = timesLogged
    }

    func makeLog(mealType: MealType) -> FoodLog {
        let log = FoodLog(
            name: name,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            fiberG: fiberG,
            servingDescription: servingDescription,
            mealType: mealType,
            source: .savedMeal,
            photoData: photoData
        )
        log.caloriesExact = caloriesExact
        log.savedFoodID = id
        log.recipeIngredientsData = ingredientData
        return log
    }
}
