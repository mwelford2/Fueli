import Foundation
import SwiftData

@Model
final class SavedMeal {
    var id: UUID
    var name: String
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double = 0
    var servingDescription: String
    @Attribute(.externalStorage) var photoData: Data?
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
        FoodLog(
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
    }
}
