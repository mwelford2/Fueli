import Foundation
import SwiftData
import Testing
@testable import Fueli

@MainActor struct PersistenceActionTests {
    func container() throws -> ModelContainer {
        try ModelContainer(for: Schema(versionedSchema: CurrentFueliSchema.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    func perform(_ service: NutritionCommitter, _ context: ModelContext, save: Bool, servings: Double = 2.5,
                 food: SavedMeal? = nil, facts: NutritionFacts = MealDatabaseChoiceTests.reference()) throws -> UUID {
        try service.commit(context: context, toLibrary: save, result: facts,
            standard: ServingNutrition(calories: facts.caloriesValue, protein: facts.proteinG,
                carbohydrates: facts.carbsG, fat: facts.fatG, fiber: facts.fiberG), name: facts.name,
            serving: "100 g standard serving", grams: 100, milliliters: nil,
            servings: servings, meal: .lunch, source: .manual, savedMeal: food, photo: Data([1, 2, 3]))
    }

    @Test(arguments: [0.125, 0.5, 1, 2.5, 3]) func saveAndLogAreIndependentIdempotentAndFullPrecision(_ quantity: Double) throws {
        let store = try container(), service = NutritionCommitter()
        let savedID = try perform(service, store.mainContext, save: true, servings: quantity)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<FoodLog>()) == 0)
        let food = try #require(store.mainContext.fetch(FetchDescriptor<SavedMeal>()).first)
        #expect(food.caloriesValue == 150.125 && food.photoData == Data([1, 2, 3]))
        #expect(try perform(service, store.mainContext, save: true, servings: quantity) == savedID)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<SavedMeal>()) == 1)
        let logID = try perform(service, store.mainContext, save: false, servings: quantity)
        #expect(try perform(service, store.mainContext, save: false, servings: quantity) == logID)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<FoodLog>()) == 1)
        let log = try #require(store.mainContext.fetch(FetchDescriptor<FoodLog>()).first)
        #expect(log.caloriesValue == 150.125 * quantity)
        #expect(log.servings == quantity && log.savedFoodID == savedID)
        food.calories = 999; food.caloriesExact = 999.125
        #expect(log.caloriesValue == 150.125 * quantity)
    }

    @Test func saveStandardDoesNotScaleUnloggedQuantity() throws {
        let store = try container()
        _ = try perform(NutritionCommitter(), store.mainContext, save: true, servings: 10_000)
        #expect(try store.mainContext.fetch(FetchDescriptor<SavedMeal>()).first?.caloriesValue == 150.125)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<FoodLog>()) == 0)
        #expect(throws: (any Swift.Error).self) {
            try perform(NutritionCommitter(), store.mainContext, save: false, servings: 10_000)
        }
    }

    @Test func logOnlyDoesNotSaveAndTwoIndependentSessionsCanLogSameFood() throws {
        let store = try container()
        _ = try perform(NutritionCommitter(), store.mainContext, save: false)
        _ = try perform(NutritionCommitter(), store.mainContext, save: false)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<FoodLog>()) == 2)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<SavedMeal>()) == 0)
    }

    @Test func failureRollsBackAndAllowsRetryWithoutPhantomLog() throws {
        let store = try container(); var attempts = 0
        let service = NutritionCommitter { context in
            attempts += 1
            if attempts == 1 { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        }
        #expect(throws: (any Swift.Error).self) { try perform(service, store.mainContext, save: false) }
        #expect(service.loggedID == nil)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<FoodLog>()) == 0)
        _ = try perform(service, store.mainContext, save: false)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<FoodLog>()) == 1)
    }

    @Test func logOnlyRetainsSourceAndStandardServingMetadataAcrossBackup() throws {
        let source = try container()
        let facts = MealDatabaseChoiceTests.reference()
        _ = try perform(NutritionCommitter(), source.mainContext, save: false, servings: 2.5, facts: facts)
        #expect(try source.mainContext.fetchCount(FetchDescriptor<SavedMeal>()) == 0)
        let backup = try LibraryBackup.capture(source.mainContext, images: true)
        let target = try container()
        _ = try JSONDecoder().decode(LibraryBackup.self, from: JSONEncoder().encode(backup)).restore(target.mainContext)
        let log = try #require(target.mainContext.fetch(FetchDescriptor<FoodLog>()).first)
        let data = try #require(log.recipeIngredientsData)
        let snapshot = try #require(JSONDecoder().decode([LibraryIngredient].self, from: data).first)
        #expect(snapshot.sourceRecordID == facts.sourceRecordID)
        #expect(snapshot.canonicalBarcode == facts.barcode)
        #expect(snapshot.gramsPerServing == 100 && snapshot.servings == 1)
        #expect(snapshot.calories == 150.125 && log.caloriesValue == 375.3125)
        #expect(log.servings == 2.5 && log.savedFoodID == nil)
    }

    @Test func canonicalBarcodeDuplicateCannotOverwriteFoodOrHistory() throws {
        let store = try container()
        _ = try perform(NutritionCommitter(), store.mainContext, save: true)
        let facts = MealDatabaseChoiceTests.reference("Different name", code: "036000291452")
        #expect(throws: (any Swift.Error).self) { try perform(NutritionCommitter(), store.mainContext, save: true, facts: facts) }
        #expect(try store.mainContext.fetchCount(FetchDescriptor<SavedMeal>()) == 1)
        #expect(try store.mainContext.fetchCount(FetchDescriptor<FoodLog>()) == 0)
    }

    @Test(arguments: 0..<7) func corruptBackupIsRejectedBeforeAnyImportMutation(_ mutation: Int) throws {
        let source = try container()
        _ = try perform(NutritionCommitter(), source.mainContext, save: true)
        _ = try perform(NutritionCommitter(), source.mainContext, save: false)
        var backup = try LibraryBackup.capture(source.mainContext, images: true)
        switch mutation {
        case 0: backup.foods[0].protein = -1
        case 1: backup.logs[0].recipeIngredientsData = Data("not JSON".utf8)
        case 2: backup.logs[0].date = Date(timeIntervalSince1970: .infinity)
        case 3: backup.foods.append(backup.foods[0])
        case 4: backup.logs[0].servings = .nan
        case 5: backup.logs[0].name = " \n "
        default: backup.version = 999
        }
        let target = try container()
        target.mainContext.insert(FoodLog(name: "Retained history", calories: 123, proteinG: 1, carbsG: 2, fatG: 3, source: .manual))
        try target.mainContext.save()
        #expect(throws: (any Swift.Error).self) { try backup.restore(target.mainContext) }
        #expect(try target.mainContext.fetchCount(FetchDescriptor<FoodLog>()) == 1)
        #expect(try target.mainContext.fetchCount(FetchDescriptor<SavedMeal>()) == 0)
    }

    @Test func everyPersistentEntitySurvivesReopenOfPopulatedStore() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fueli-all-entities-\(UUID()).store")
        let schema = Schema(versionedSchema: CurrentFueliSchema.self)
        func open() throws -> ModelContainer { try ModelContainer(for: schema, migrationPlan: FueliMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: url)) }
        var first: ModelContainer? = try open()
        let context = try #require(first?.mainContext)
        context.insert(UserProfile(hasCompletedOnboarding: true))
        context.insert(WeightEntry(weightKg: 75.25)); context.insert(WaterEntry(amountOz: 16))
        context.insert(WorkoutLog(workoutType: .running, durationSeconds: 120, caloriesBurned: 25))
        _ = try perform(NutritionCommitter(), context, save: true)
        _ = try perform(NutritionCommitter(), context, save: false)
        try context.save(); first = nil
        let second = try open()
        #expect(try second.mainContext.fetchCount(FetchDescriptor<UserProfile>()) == 1)
        #expect(try second.mainContext.fetch(FetchDescriptor<WeightEntry>()).first?.weightKg == 75.25)
        #expect(try second.mainContext.fetch(FetchDescriptor<WaterEntry>()).first?.amountOz == 16)
        #expect(try second.mainContext.fetch(FetchDescriptor<WorkoutLog>()).first?.durationSeconds == 120)
        #expect(try second.mainContext.fetchCount(FetchDescriptor<SavedMeal>()) == 1)
        #expect(try second.mainContext.fetchCount(FetchDescriptor<FoodLog>()) == 1)
    }
}
