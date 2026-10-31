import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryIngredient: Codable, Identifiable, Equatable {
    var id: UUID
    var foodID: UUID? = nil
    var sourceRecordID: String? = nil
    var gramsPerServing: Double? = nil
    var millilitersPerServing: Double? = nil
    var servingDescription: String? = nil
    var preparation: String? = nil
    var measureBasis: MeasureBasis? = nil
    var quantityIsEstimated: Bool? = nil
    var name: String
    var servings: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double

    func nutrition() throws -> ServingNutrition {
        for reference in [gramsPerServing, millilitersPerServing].compactMap({ $0 }) {
            guard reference.isFinite, reference > 0 else { throw NutritionValidationError.invalidQuantity }
        }
        return try ServingNutrition(calories: calories, protein: protein, carbohydrates: carbs, fat: fat, fiber: fiber).scaled(by: servings)
    }
}

struct LibraryBackup: Codable {
    var version = 1
    var exportedAt = Date()
    var foods: [Food]
    var logs: [Log]
    struct Food: Codable {
        var id: UUID
        var name: String
        var calories: Int
        var caloriesExact: Double? = nil
        var protein, carbs, fat, fiber: Double
        var serving: String
        var ingredients: Data?
        var photo: Data?
        var created: Date
        var timesLogged: Int
        var barcode: String? = nil
        var sourceRecordID: String? = nil
        var gramsPerServing: Double? = nil
        var millilitersPerServing: Double? = nil
        var favorite: Bool? = nil
        var lastLogged: Date? = nil
    }
    struct Log: Codable {
        var id: UUID
        var name: String
        var calories: Int
        var caloriesExact: Double? = nil
        var protein, carbs, fat, fiber, servings: Double
        var serving: String
        var date: Date
        var meal: MealType
        var source: LogSource
        var photo: Data?
        var notes: String?
        var savedFoodID: UUID? = nil
        var recipeIngredientsData: Data? = nil
    }
    func validate() throws {
        guard version == 1, foods.count <= 100000, logs.count <= 100000,
              Set(foods.map(\.id)).count == foods.count, Set(logs.map(\.id)).count == logs.count else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for food in foods {
            guard !food.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, food.timesLogged >= 0 else { throw CocoaError(.fileReadCorruptFile) }
            if let grams = food.gramsPerServing, !grams.isFinite || grams <= 0 { throw NutritionValidationError.invalidQuantity }
            if let ml = food.millilitersPerServing, !ml.isFinite || ml <= 0 { throw NutritionValidationError.invalidQuantity }
            if let barcode = food.barcode, BarcodeLookupService.databaseBarcode(barcode) == nil { throw CocoaError(.fileReadCorruptFile) }
            _ = try ServingNutrition(calories: food.caloriesExact ?? Double(food.calories), protein: food.protein, carbohydrates: food.carbs, fat: food.fat, fiber: food.fiber)
            if let data = food.ingredients {
                let ingredients = try JSONDecoder().decode([LibraryIngredient].self, from: data)
                for ingredient in ingredients { _ = try ingredient.nutrition() }
            }
        }
        for log in logs {
            _ = try ServingNutrition(calories: log.caloriesExact ?? Double(log.calories), protein: log.protein, carbohydrates: log.carbs, fat: log.fat, fiber: log.fiber)
            guard log.servings.isFinite, log.servings > 0, !log.name.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        }
    }
    @MainActor static func capture(_ context: ModelContext, images: Bool) throws -> Self {
        let foods = try context.fetch(FetchDescriptor<SavedMeal>()).map {
            Food(id: $0.id, name: $0.name, calories: $0.calories, caloriesExact: $0.caloriesExact, protein: $0.proteinG, carbs: $0.carbsG,
                 fat: $0.fatG, fiber: $0.fiberG, serving: $0.servingDescription, ingredients: $0.ingredientData,
                 photo: images ? $0.photoData : nil, created: $0.createdAt, timesLogged: $0.timesLogged, barcode: $0.canonicalBarcode, sourceRecordID: $0.nutritionSourceID, gramsPerServing: $0.gramsPerServing, millilitersPerServing: $0.millilitersPerServing, favorite: $0.isFavorite, lastLogged: $0.lastLoggedAt)
        }
        let logs = try context.fetch(FetchDescriptor<FoodLog>()).map {
            Log(id: $0.id, name: $0.name, calories: $0.calories, caloriesExact: $0.caloriesExact, protein: $0.proteinG, carbs: $0.carbsG,
                fat: $0.fatG, fiber: $0.fiberG, servings: $0.servings, serving: $0.servingDescription,
                date: $0.loggedAt, meal: $0.mealType, source: $0.source, photo: images ? $0.photoData : nil, notes: $0.notes, savedFoodID: $0.savedFoodID, recipeIngredientsData: $0.recipeIngredientsData)
        }
        return Self(foods: foods, logs: logs)
    }
    /// Additive restore: matching UUIDs are skipped; existing history is never overwritten.
    @MainActor func restore(_ context: ModelContext) throws -> Int {
        try validate()
        let existingFoods = try context.fetch(FetchDescriptor<SavedMeal>())
        let foodIDs = Set(existingFoods.map(\.id))
        var barcodeIDs = Dictionary(existingFoods.compactMap { item in item.canonicalBarcode.flatMap(BarcodeLookupService.gtinIdentity).map { ($0, item.id) } }, uniquingKeysWith: { first, _ in first })
        var remappedFoodIDs: [UUID: UUID] = [:]
        let logIDs = Set(try context.fetch(FetchDescriptor<FoodLog>()).map(\.id))
        var count = 0
        var insertedFoods: [SavedMeal] = []
        do {
            for food in foods where !foodIDs.contains(food.id) {
                if let barcode = food.barcode.flatMap(BarcodeLookupService.gtinIdentity), let existingID = barcodeIDs[barcode] {
                    remappedFoodIDs[food.id] = existingID
                    continue
                }
                let item = SavedMeal(id: food.id, name: food.name, calories: Int((food.caloriesExact ?? Double(food.calories)).rounded()), proteinG: food.protein,
                    carbsG: food.carbs, fatG: food.fat, fiberG: food.fiber, servingDescription: food.serving,
                    photoData: food.photo, createdAt: food.created, timesLogged: food.timesLogged)
                item.caloriesExact = food.caloriesExact
                item.ingredientData = food.ingredients
                item.canonicalBarcode = food.barcode.flatMap(BarcodeLookupService.databaseBarcode)
                if let barcode = item.canonicalBarcode.flatMap(BarcodeLookupService.gtinIdentity) { barcodeIDs[barcode] = item.id }
                item.nutritionSourceID = food.sourceRecordID
                item.gramsPerServing = food.gramsPerServing
                item.millilitersPerServing = food.millilitersPerServing
                item.isFavorite = food.favorite ?? false
                item.lastLoggedAt = food.lastLogged
                context.insert(item); insertedFoods.append(item); count += 1
            }
            for food in insertedFoods {
                if let data = food.ingredientData {
                    var ingredients = try JSONDecoder().decode([LibraryIngredient].self, from: data)
                    for index in ingredients.indices {
                        ingredients[index].foodID = ingredients[index].foodID.map { remappedFoodIDs[$0] ?? $0 }
                    }
                    food.ingredientData = try JSONEncoder().encode(ingredients)
                }
            }
            for log in logs where !logIDs.contains(log.id) {
                let entry = FoodLog(id: log.id, name: log.name, calories: Int((log.caloriesExact ?? Double(log.calories)).rounded()), proteinG: log.protein,
                    carbsG: log.carbs, fatG: log.fat, fiberG: log.fiber, servingDescription: log.serving,
                    servings: log.servings, mealType: log.meal, loggedAt: log.date, source: log.source,
                    photoData: log.photo, notes: log.notes)
                entry.caloriesExact = log.caloriesExact
                entry.savedFoodID = log.savedFoodID.map { remappedFoodIDs[$0] ?? $0 }
                entry.recipeIngredientsData = log.recipeIngredientsData
                context.insert(entry); count += 1
            }
            try context.save()
            return count
        } catch { context.rollback(); throw error }
    }
}

struct NutritionJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct NutritionBackupView: View {
    @Environment(\.modelContext) private var context
    @State private var images = false
    @State private var exporting = false
    @State private var importing = false
    @State private var document = NutritionJSONDocument(data: Data())
    @State private var pending: LibraryBackup?
    @State private var message: String?
    var body: some View {
        Form {
            Section("Local backup") {
                Toggle("Include food photographs", isOn: $images)
                Text("JSON includes your saved foods, recipes, meal history, dates and notes. It may contain sensitive diet information. Store it privately. Profile, weight, water and workouts are not included.").font(.caption)
                Button("Export Foods, Recipes & Logs") {
                    do {
                        let backup = try LibraryBackup.capture(context, images: images)
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        document = NutritionJSONDocument(data: try encoder.encode(backup)); exporting = true
                    } catch { message = error.localizedDescription }
                }
                Button("Import Backup") { importing = true }
                if let message { Text(message) }
            }
        }.themedScreenBackground().navigationTitle("Nutrition Backup")
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Fueli-nutrition-backup") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 100_000_000 else { throw CocoaError(.fileReadTooLarge) }
                var readError: NSError?
                var contents: Data?
                NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &readError) { contents = try? Data(contentsOf: $0) }
                if let readError { throw readError }
                guard let contents else { throw CocoaError(.fileReadCorruptFile) }
                let backup = try JSONDecoder().decode(LibraryBackup.self, from: contents)
                try backup.validate(); pending = backup
            } catch { message = error.localizedDescription }
        }
        .confirmationDialog("Import adds missing records. Existing UUIDs are skipped and history is never overwritten.", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Import Reviewed Backup") {
                do { if let pending { message = "Added \(try pending.restore(context)) records." } }
                catch { message = error.localizedDescription }
                pending = nil
            }
        }
    }
}
