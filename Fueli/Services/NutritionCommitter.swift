import Foundation
import SwiftData

/// One confirmation session, with independent idempotency for its two explicit
/// actions. Database errors roll back and permit retry; success cannot double-log.
@MainActor @Observable
final class NutritionCommitter {
    private(set) var loggedID: UUID?
    private(set) var savedID: UUID?
    private let persist: (ModelContext) throws -> Void
    init(persist: @escaping (ModelContext) throws -> Void = { try $0.save() }) { self.persist = persist }

    func commit(context: ModelContext, toLibrary: Bool, result: NutritionFacts, standard: ServingNutrition,
                name: String, serving: String, grams: Double?, milliliters: Double?, servings: Double,
                meal: MealType, source: LogSource, savedMeal: SavedMeal?, photo: Data?) throws -> UUID {
        if toLibrary, let savedID { return savedID }
        if !toLibrary, let loggedID { return loggedID }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NutritionValidationError.incomplete }
        for value in [grams, milliliters].compactMap({ $0 }) {
            guard value.isFinite, value > 0, value <= 1000000 else { throw NutritionValidationError.invalidQuantity }
        }
        // Validate before any insert/update. Saving always uses one standard serving.
        guard servings.isFinite, servings > 0, servings <= 10_000 else { throw NutritionValidationError.invalidQuantity }
        let total = toLibrary ? standard : try standard.scaled(by: servings)
        do {
            let id: UUID
            if toLibrary {
                if savedMeal == nil, let barcode = result.barcode,
                   let existing = try context.fetch(FetchDescriptor<SavedMeal>()).first(where: {
                       $0.canonicalBarcode.map { BarcodeLookupService.sameGTIN($0, barcode) } == true
                   }) {
                    throw PersistenceError.duplicateBarcode(existing.name)
                }
                let item = savedMeal ?? SavedMeal(name: name, calories: Int(standard.calories.rounded()),
                    proteinG: standard.protein, carbsG: standard.carbohydrates, fatG: standard.fat,
                    fiberG: standard.fiber, servingDescription: serving)
                item.name = name; item.calories = Int(standard.calories.rounded()); item.caloriesExact = standard.calories
                item.proteinG = standard.protein; item.carbsG = standard.carbohydrates
                item.fatG = standard.fat; item.fiberG = standard.fiber; item.servingDescription = serving
                item.gramsPerServing = grams; item.millilitersPerServing = milliliters
                if let ingredients = result.ingredients { item.ingredientData = try JSONEncoder().encode(ingredients) }
                if let barcode = result.barcode { item.canonicalBarcode = barcode }
                if let sourceID = result.sourceRecordID { item.nutritionSourceID = sourceID }
                if let photo { item.photoData = photo }
                if savedMeal == nil { context.insert(item) }
                id = item.id
            } else {
                let log = FoodLog(name: name, calories: Int(total.calories.rounded()), proteinG: total.protein,
                    carbsG: total.carbohydrates, fatG: total.fat, fiberG: total.fiber,
                    servingDescription: serving, servings: servings, mealType: meal, source: source, photoData: photo)
                log.caloriesExact = total.calories
                log.savedFoodID = savedMeal?.id ?? savedID
                if let ingredients = result.ingredients {
                    log.recipeIngredientsData = try JSONEncoder().encode(ingredients)
                } else if let ingredients = savedMeal?.ingredientData {
                    log.recipeIngredientsData = ingredients
                } else {
                    // One standard portion; the historical log's multiplier records
                    // the amount eaten. Keep identity/units even for log-only foods.
                    let snapshot = LibraryIngredient(id: UUID(), foodID: savedMeal?.id ?? savedID,
                        sourceRecordID: result.sourceRecordID ?? savedMeal?.nutritionSourceID,
                        canonicalBarcode: result.barcode ?? savedMeal?.canonicalBarcode,
                        gramsPerServing: grams, millilitersPerServing: milliliters, servingDescription: serving,
                        name: name, servings: 1, calories: standard.calories, protein: standard.protein,
                        carbs: standard.carbohydrates, fat: standard.fat, fiber: standard.fiber)
                    log.recipeIngredientsData = try JSONEncoder().encode([snapshot])
                }
                savedMeal?.timesLogged += 1; savedMeal?.lastLoggedAt = Date()
                context.insert(log); id = log.id
            }
            try persist(context)
            if toLibrary { savedID = id } else { loggedID = id }
            return id
        } catch { context.rollback(); throw error }
    }
}

private enum PersistenceError: LocalizedError {
    case duplicateBarcode(String)
    var errorDescription: String? {
        switch self {
        case .duplicateBarcode(let name): return "This barcode is already saved as \(name). Edit it in My Foods to update its values."
        }
    }
}

enum EntryValidation {
    static func weightKg(_ value: Double) -> Bool { value.isFinite && value > 0 && value <= 1000 }
    static func heightCm(_ value: Double) -> Bool { value.isFinite && (50...300).contains(value) }
    static func bodyFat(_ value: Double) -> Bool { value.isFinite && (0..<100).contains(value) }
}
