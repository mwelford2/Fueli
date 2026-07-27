import Foundation
import SwiftData

enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snack: return "leaf.fill"
        }
    }

    /// Best-guess meal type based on time of day, matching CalAI's meal-timing feature.
    static func suggested(for date: Date = Date()) -> MealType {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 4..<11: return .breakfast
        case 11..<16: return .lunch
        case 16..<21: return .dinner
        default: return .snack
        }
    }
}

enum LogSource: String, Codable {
    case photo, barcode, textDescription, manual, savedMeal
}

@Model
final class FoodLog {
    var id: UUID
    var name: String
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double = 0
    var servingDescription: String
    var mealType: MealType
    var loggedAt: Date
    var source: LogSource
    /// JPEG data for photo-sourced logs, shown as a thumbnail in history.
    @Attribute(.externalStorage) var photoData: Data?
    var notes: String?

    init(
        id: UUID = UUID(),
        name: String,
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double = 0,
        servingDescription: String = "1 serving",
        mealType: MealType = .suggested(),
        loggedAt: Date = Date(),
        source: LogSource,
        photoData: Data? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.servingDescription = servingDescription
        self.mealType = mealType
        self.loggedAt = loggedAt
        self.source = source
        self.photoData = photoData
        self.notes = notes
    }
}
