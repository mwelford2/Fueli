import Foundation
import Testing
import SwiftData
@testable import Fueli

@MainActor struct MigrationSafetyTests {
    @Test func populatedOriginalUnversionedStoreMigratesWithoutReset() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let logID = UUID(), foodID = UUID()
        func seed() throws {
            let legacy = Schema(LegacyFueliSchema.models)
            let container = try ModelContainer(for: legacy, configurations: ModelConfiguration(schema: legacy, url: url))
            let context = container.mainContext
            context.insert(LegacyFueliSchema.UserProfile(hasCompletedOnboarding: true))
            context.insert(LegacyFueliSchema.FoodLog(id: logID, name: "Original meal", calories: 123, proteinG: 4.5, carbsG: 20, fatG: 2, source: .manual, photoData: Data([1,2,3])))
            context.insert(LegacyFueliSchema.SavedMeal(id: foodID, name: "Original favorite", calories: 200, proteinG: 10, carbsG: 30, fatG: 5))
            context.insert(LegacyFueliSchema.WeightEntry(weightKg: 75))
            context.insert(LegacyFueliSchema.WaterEntry(amountOz: 16))
            context.insert(LegacyFueliSchema.WorkoutLog(workoutType: .walking, durationSeconds: 60, caloriesBurned: 5))
            try context.save()
        }
        try seed()
        let current = Schema(versionedSchema: CurrentFueliSchema.self)
        let container = try ModelContainer(for: current, migrationPlan: FueliMigrationPlan.self, configurations: ModelConfiguration(schema: current, url: url))
        let context = container.mainContext
        let logs = try context.fetch(FetchDescriptor<FoodLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.id == logID)
        #expect(logs.first?.calories == 123)
        #expect(logs.first?.photoData == Data([1,2,3]))
        #expect(try context.fetch(FetchDescriptor<SavedMeal>()).first?.id == foodID)
        #expect(try context.fetch(FetchDescriptor<SavedMeal>()).first?.isFavorite == true)
        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<WeightEntry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<WaterEntry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutLog>()) == 1)
    }
    @Test func unreadableStoreIsNotDeletedOrReplaced() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let original = Data("Deliberately corrupt test-only store".utf8)
        try original.write(to: url, options: .atomic)
        let schema = Schema(versionedSchema: CurrentFueliSchema.self)
        #expect(throws: (any Swift.Error).self) {
            _ = try ModelContainer(for: schema, migrationPlan: FueliMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, url: url))
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test(arguments: [false, true]) func interimUnversionedInstallationsMigrate(libraryPreview: Bool) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        func seed() throws {
            let schema = Schema(libraryPreview ? LibraryPreviewFueliSchema.models : HealthSetupFueliSchema.models)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            if libraryPreview {
                let p = LibraryPreviewFueliSchema.UserProfile(hasCompletedOnboarding: true)
                p.healthMaintenanceCalories = 2345
                container.mainContext.insert(p)
                let favorite = LibraryPreviewFueliSchema.SavedMeal(name: "Interim favorite", calories: 123, proteinG: 4, carbsG: 20, fatG: 2)
                container.mainContext.insert(favorite)
            } else {
                let p = HealthSetupFueliSchema.UserProfile(hasCompletedOnboarding: true)
                p.healthMaintenanceCalories = 2345
                container.mainContext.insert(p)
                container.mainContext.insert(HealthSetupFueliSchema.SavedMeal(name: "Interim favorite", calories: 123, proteinG: 4, carbsG: 20, fatG: 2))
            }
            try container.mainContext.save()
        }
        try seed()
        let schema = Schema(versionedSchema: CurrentFueliSchema.self)
        let container = try ModelContainer(for: schema, migrationPlan: FueliMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: url))
        #expect(try container.mainContext.fetch(FetchDescriptor<UserProfile>()).first?.healthMaintenanceCalories == 2345)
        #expect(try container.mainContext.fetch(FetchDescriptor<SavedMeal>()).first?.isFavorite == true)
    }

    @Test func populatedVersionTwoLibraryMigratesToPreciseCalories() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let foodID = UUID()
        func seed() throws {
            let schema = Schema(versionedSchema: PrePrecisionFueliSchema.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let food = PrePrecisionFueliSchema.SavedMeal(id: foodID, name: "Version two food", calories: 150, proteinG: 10.25, carbsG: 12.5, fatG: 3)
            food.isFavorite = true
            food.gramsPerServing = 30
            food.nutritionSourceID = "USDA:123"
            container.mainContext.insert(food)
            let log = PrePrecisionFueliSchema.FoodLog(name: "Existing half serving", calories: 75, proteinG: 5.125, carbsG: 6.25, fatG: 1.5, servings: 0.5, source: .savedMeal)
            log.savedFoodID = foodID
            container.mainContext.insert(log)
            try container.mainContext.save()
        }
        try seed()
        let schema = Schema(versionedSchema: CurrentFueliSchema.self)
        let container = try ModelContainer(for: schema, migrationPlan: FueliMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: url))
        let fetchedFoods = try container.mainContext.fetch(FetchDescriptor<SavedMeal>())
        let food = try #require(fetchedFoods.first)
        #expect(food.caloriesExact == nil)
        #expect(food.caloriesValue == 150)
        #expect(food.gramsPerServing == 30)
        #expect(food.nutritionSourceID == "USDA:123")
        #expect(food.isFavorite)
        let fetchedLogs = try container.mainContext.fetch(FetchDescriptor<FoodLog>())
        let log = try #require(fetchedLogs.first)
        #expect(log.caloriesValue == 75)
        #expect(log.servings == 0.5)
        #expect(log.savedFoodID == foodID)
    }

    @Test func versionThreeStoreAddsManualBurnWithoutChangingExistingData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let logID = UUID()
        func seed() throws {
            let schema = Schema(versionedSchema: PrecisionFueliSchema.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let profile = PrecisionFueliSchema.UserProfile(hasCompletedOnboarding: true)
            profile.healthMaintenanceCalories = 2500.5
            profile.healthEnergyDayCount = 9
            profile.manualCalorieTarget = 2100
            container.mainContext.insert(profile)
            let food = PrecisionFueliSchema.SavedMeal(name: "Existing food", calories: 100, proteinG: 10, carbsG: 5, fatG: 2)
            food.caloriesExact = 100.25
            food.isFavorite = true
            container.mainContext.insert(food)
            let log = PrecisionFueliSchema.FoodLog(id: logID, name: "Existing snapshot", calories: 50, proteinG: 5, carbsG: 2.5, fatG: 1, servings: 0.5, source: .savedMeal, photoData: Data([4,5,6]))
            log.caloriesExact = 50.125
            log.savedFoodID = food.id
            container.mainContext.insert(log)
            container.mainContext.insert(PrecisionFueliSchema.WaterEntry(amountOz: 16))
            container.mainContext.insert(PrecisionFueliSchema.WeightEntry(weightKg: 75))
            container.mainContext.insert(PrecisionFueliSchema.WorkoutLog(workoutType: .walking, durationSeconds: 60, caloriesBurned: 5))
            try container.mainContext.save()
        }
        try seed()
        let schema = Schema(versionedSchema: CurrentFueliSchema.self)
        let container = try ModelContainer(for: schema, migrationPlan: FueliMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: url))
        let context = container.mainContext
        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        let profile = try #require(profiles.first)
        #expect(profile.manualMaintenanceCalories == nil)
        #expect(profile.healthMaintenanceCalories == 2500.5)
        #expect(profile.healthEnergyDayCount == 9)
        #expect(profile.manualCalorieTarget == 2100)
        let foods = try context.fetch(FetchDescriptor<SavedMeal>())
        #expect(foods.first?.caloriesValue == 100.25)
        #expect(foods.first?.isFavorite == true)
        let logs = try context.fetch(FetchDescriptor<FoodLog>())
        #expect(logs.first?.id == logID)
        #expect(logs.first?.caloriesValue == 50.125)
        #expect(logs.first?.photoData == Data([4,5,6]))
        #expect(try context.fetchCount(FetchDescriptor<WaterEntry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<WeightEntry>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutLog>()) == 1)
    }

}
