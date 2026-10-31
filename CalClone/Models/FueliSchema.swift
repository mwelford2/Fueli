import Foundation
import SwiftData
import CoreMotion

// Frozen persisted schemas; constructors are retained for migration fixtures.

enum LegacyFueliSchema: VersionedSchema {
static var versionIdentifier = Schema.Version(1, 0, 0)
static var models: [any PersistentModel.Type] { [UserProfile.self, FoodLog.self, SavedMeal.self, WeightEntry.self, WaterEntry.self, WorkoutLog.self] }
@Model
final class UserProfile {
    var id: UUID
    var hasCompletedOnboarding: Bool = false
    var sex: BiologicalSex
    var birthDate: Date
    /// Stored in cm internally; displayed as ft/in in the UI.
    var heightCm: Double
    /// Stored in kg internally; displayed as lbs in the UI.
    var startingWeightKg: Double
    var goalWeightKg: Double
    /// Optional body fat percentage (0-100). When set, BMR uses Katch-McArdle (lean mass
    /// based) instead of Mifflin-St Jeor for a more accurate estimate.
    var bodyFatPercent: Double?
    var stepsTier: StepsTier
    var workoutHoursTier: WorkoutHoursTier
    var trainingGoal: TrainingGoal
    var recompFocus: RecompFocus
    /// Desired weight change rate in kg/week (positive for gain, negative for loss).
    var weeklyRateKg: Double
    var dietPreference: DietPreference
    var unitSystem: UnitSystem = UnitSystem.usCustomary

    /// Manual overrides; if nil, computed targets are used.
    var manualCalorieTarget: Int?
    var manualProteinTarget: Int?
    var manualCarbTarget: Int?
    var manualFatTarget: Int?
    var manualFiberTarget: Int?

    var dailyWaterTargetOz: Int

    /// When enabled, yesterday's calorie overshoot trims today's budget (capped at
    /// 15% of the daily target — research favors small, spread-out corrections over
    /// harsh next-day restriction, since weekly energy balance is what drives results).
    var rolloverExcessCalories: Bool = true

    /// Fraction of the daily budget that a rollover correction may not exceed.
    static let rolloverCapFraction = 0.15

    init(
        id: UUID = UUID(),
        hasCompletedOnboarding: Bool = false,
        sex: BiologicalSex = .male,
        birthDate: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date(),
        heightCm: Double = 175,
        startingWeightKg: Double = 75,
        goalWeightKg: Double = 70,
        bodyFatPercent: Double? = nil,
        stepsTier: StepsTier = .tier7to9k,
        workoutHoursTier: WorkoutHoursTier = .oneToThree,
        trainingGoal: TrainingGoal = .cut,
        recompFocus: RecompFocus = .maintenance,
        weeklyRateKg: Double = -0.5,
        dietPreference: DietPreference = .classic,
        dailyWaterTargetOz: Int = 84,
        rolloverExcessCalories: Bool = true,
        unitSystem: UnitSystem = .usCustomary
    ) {
        self.id = id
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.sex = sex
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.startingWeightKg = startingWeightKg
        self.goalWeightKg = goalWeightKg
        self.bodyFatPercent = bodyFatPercent
        self.stepsTier = stepsTier
        self.workoutHoursTier = workoutHoursTier
        self.trainingGoal = trainingGoal
        self.recompFocus = recompFocus
        self.weeklyRateKg = weeklyRateKg
        self.dietPreference = dietPreference
        self.dailyWaterTargetOz = dailyWaterTargetOz
        self.rolloverExcessCalories = rolloverExcessCalories
        self.unitSystem = unitSystem
    }
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
    var servings: Double = 1.0
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
        servings: Double = 1.0,
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
        self.servings = servings
        self.mealType = mealType
        self.loggedAt = loggedAt
        self.source = source
        self.photoData = photoData
        self.notes = notes
    }
}
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
}
@Model
final class WeightEntry {
    var id: UUID
    var weightKg: Double
    var recordedAt: Date

    init(id: UUID = UUID(), weightKg: Double, recordedAt: Date = Date()) {
        self.id = id
        self.weightKg = weightKg
        self.recordedAt = recordedAt
    }
}
@Model
final class WaterEntry {
    var id: UUID
    var amountOz: Int
    var recordedAt: Date

    init(id: UUID = UUID(), amountOz: Int, recordedAt: Date = Date()) {
        self.id = id
        self.amountOz = amountOz
        self.recordedAt = recordedAt
    }
}
@Model
final class WorkoutLog {
    var id: UUID
    var workoutType: WorkoutType
    var startedAt: Date
    var durationSeconds: Int
    var steps: Int
    var caloriesBurned: Int
    var distanceMeters: Double

    init(
        id: UUID = UUID(),
        workoutType: WorkoutType = .other,
        startedAt: Date = Date(),
        durationSeconds: Int = 0,
        steps: Int = 0,
        caloriesBurned: Int = 0,
        distanceMeters: Double = 0
    ) {
        self.id = id
        self.workoutType = workoutType
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.steps = steps
        self.caloriesBurned = caloriesBurned
        self.distanceMeters = distanceMeters
    }
}
}

enum HealthSetupFueliSchema: VersionedSchema {
static var versionIdentifier = Schema.Version(1, 1, 0)
static var models: [any PersistentModel.Type] { [UserProfile.self, FoodLog.self, SavedMeal.self, WeightEntry.self, WaterEntry.self, WorkoutLog.self] }
@Model
final class UserProfile {
    var id: UUID
    var hasCompletedOnboarding: Bool = false
    var sex: BiologicalSex
    var birthDate: Date
    /// Stored in cm internally; displayed as ft/in in the UI.
    var heightCm: Double
    /// Stored in kg internally; displayed as lbs in the UI.
    var startingWeightKg: Double
    var goalWeightKg: Double
    /// Optional body fat percentage (0-100). When set, BMR uses Katch-McArdle (lean mass
    /// based) instead of Mifflin-St Jeor for a more accurate estimate.
    var bodyFatPercent: Double?
    var stepsTier: StepsTier
    var workoutHoursTier: WorkoutHoursTier
    var trainingGoal: TrainingGoal
    var recompFocus: RecompFocus
    /// Desired weight change rate in kg/week (positive for gain, negative for loss).
    var weeklyRateKg: Double
    var dietPreference: DietPreference
    var unitSystem: UnitSystem = UnitSystem.usCustomary

    /// Manual overrides; if nil, computed targets are used.
    var manualCalorieTarget: Int?
    var manualProteinTarget: Int?
    var manualCarbTarget: Int?
    var manualFatTarget: Int?
    var manualFiberTarget: Int?

    var healthMaintenanceCalories: Double?
    var healthEnergyDayCount: Int?
    var healthEnergyWindowStart: Date?
    var healthEnergyWindowEnd: Date?
    var dailyWaterTargetOz: Int

    /// When enabled, yesterday's calorie overshoot trims today's budget (capped at
    /// 15% of the daily target — research favors small, spread-out corrections over
    /// harsh next-day restriction, since weekly energy balance is what drives results).
    var rolloverExcessCalories: Bool = true

    /// Fraction of the daily budget that a rollover correction may not exceed.
    static let rolloverCapFraction = 0.15

    init(
        id: UUID = UUID(),
        hasCompletedOnboarding: Bool = false,
        sex: BiologicalSex = .male,
        birthDate: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date(),
        heightCm: Double = 175,
        startingWeightKg: Double = 75,
        goalWeightKg: Double = 70,
        bodyFatPercent: Double? = nil,
        stepsTier: StepsTier = .tier7to9k,
        workoutHoursTier: WorkoutHoursTier = .oneToThree,
        trainingGoal: TrainingGoal = .cut,
        recompFocus: RecompFocus = .maintenance,
        weeklyRateKg: Double = -0.5,
        dietPreference: DietPreference = .classic,
        dailyWaterTargetOz: Int = 84,
        rolloverExcessCalories: Bool = true,
        unitSystem: UnitSystem = .usCustomary
    ) {
        self.id = id
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.sex = sex
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.startingWeightKg = startingWeightKg
        self.goalWeightKg = goalWeightKg
        self.bodyFatPercent = bodyFatPercent
        self.stepsTier = stepsTier
        self.workoutHoursTier = workoutHoursTier
        self.trainingGoal = trainingGoal
        self.recompFocus = recompFocus
        self.weeklyRateKg = weeklyRateKg
        self.dietPreference = dietPreference
        self.dailyWaterTargetOz = dailyWaterTargetOz
        self.rolloverExcessCalories = rolloverExcessCalories
        self.unitSystem = unitSystem
    }
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
    var servings: Double = 1.0
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
        servings: Double = 1.0,
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
        self.servings = servings
        self.mealType = mealType
        self.loggedAt = loggedAt
        self.source = source
        self.photoData = photoData
        self.notes = notes
    }
}
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
}
@Model
final class WeightEntry {
    var id: UUID
    var weightKg: Double
    var recordedAt: Date

    init(id: UUID = UUID(), weightKg: Double, recordedAt: Date = Date()) {
        self.id = id
        self.weightKg = weightKg
        self.recordedAt = recordedAt
    }
}
@Model
final class WaterEntry {
    var id: UUID
    var amountOz: Int
    var recordedAt: Date

    init(id: UUID = UUID(), amountOz: Int, recordedAt: Date = Date()) {
        self.id = id
        self.amountOz = amountOz
        self.recordedAt = recordedAt
    }
}
@Model
final class WorkoutLog {
    var id: UUID
    var workoutType: WorkoutType
    var startedAt: Date
    var durationSeconds: Int
    var steps: Int
    var caloriesBurned: Int
    var distanceMeters: Double

    init(
        id: UUID = UUID(),
        workoutType: WorkoutType = .other,
        startedAt: Date = Date(),
        durationSeconds: Int = 0,
        steps: Int = 0,
        caloriesBurned: Int = 0,
        distanceMeters: Double = 0
    ) {
        self.id = id
        self.workoutType = workoutType
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.steps = steps
        self.caloriesBurned = caloriesBurned
        self.distanceMeters = distanceMeters
    }
}
}

enum LibraryPreviewFueliSchema: VersionedSchema {
static var versionIdentifier = Schema.Version(1, 2, 0)
static var models: [any PersistentModel.Type] { [UserProfile.self, FoodLog.self, SavedMeal.self, WeightEntry.self, WaterEntry.self, WorkoutLog.self] }
@Model
final class UserProfile {
    var id: UUID
    var hasCompletedOnboarding: Bool = false
    var sex: BiologicalSex
    var birthDate: Date
    /// Stored in cm internally; displayed as ft/in in the UI.
    var heightCm: Double
    /// Stored in kg internally; displayed as lbs in the UI.
    var startingWeightKg: Double
    var goalWeightKg: Double
    /// Optional body fat percentage (0-100). When set, BMR uses Katch-McArdle (lean mass
    /// based) instead of Mifflin-St Jeor for a more accurate estimate.
    var bodyFatPercent: Double?
    var stepsTier: StepsTier
    var workoutHoursTier: WorkoutHoursTier
    var trainingGoal: TrainingGoal
    var recompFocus: RecompFocus
    /// Desired weight change rate in kg/week (positive for gain, negative for loss).
    var weeklyRateKg: Double
    var dietPreference: DietPreference
    var unitSystem: UnitSystem = UnitSystem.usCustomary

    /// Manual overrides; if nil, computed targets are used.
    var manualCalorieTarget: Int?
    var manualProteinTarget: Int?
    var manualCarbTarget: Int?
    var manualFatTarget: Int?
    var manualFiberTarget: Int?

    var healthMaintenanceCalories: Double?
    var healthEnergyDayCount: Int?
    var healthEnergyWindowStart: Date?
    var healthEnergyWindowEnd: Date?
    var dailyWaterTargetOz: Int

    /// When enabled, yesterday's calorie overshoot trims today's budget (capped at
    /// 15% of the daily target — research favors small, spread-out corrections over
    /// harsh next-day restriction, since weekly energy balance is what drives results).
    var rolloverExcessCalories: Bool = true

    /// Fraction of the daily budget that a rollover correction may not exceed.
    static let rolloverCapFraction = 0.15

    init(
        id: UUID = UUID(),
        hasCompletedOnboarding: Bool = false,
        sex: BiologicalSex = .male,
        birthDate: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date(),
        heightCm: Double = 175,
        startingWeightKg: Double = 75,
        goalWeightKg: Double = 70,
        bodyFatPercent: Double? = nil,
        stepsTier: StepsTier = .tier7to9k,
        workoutHoursTier: WorkoutHoursTier = .oneToThree,
        trainingGoal: TrainingGoal = .cut,
        recompFocus: RecompFocus = .maintenance,
        weeklyRateKg: Double = -0.5,
        dietPreference: DietPreference = .classic,
        dailyWaterTargetOz: Int = 84,
        rolloverExcessCalories: Bool = true,
        unitSystem: UnitSystem = .usCustomary
    ) {
        self.id = id
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.sex = sex
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.startingWeightKg = startingWeightKg
        self.goalWeightKg = goalWeightKg
        self.bodyFatPercent = bodyFatPercent
        self.stepsTier = stepsTier
        self.workoutHoursTier = workoutHoursTier
        self.trainingGoal = trainingGoal
        self.recompFocus = recompFocus
        self.weeklyRateKg = weeklyRateKg
        self.dietPreference = dietPreference
        self.dailyWaterTargetOz = dailyWaterTargetOz
        self.rolloverExcessCalories = rolloverExcessCalories
        self.unitSystem = unitSystem
    }
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
    var servings: Double = 1.0
    var mealType: MealType
    var loggedAt: Date
    var source: LogSource
    /// JPEG data for photo-sourced logs, shown as a thumbnail in history.
    @Attribute(.externalStorage) var photoData: Data?
    var notes: String?
    var savedFoodID: UUID?
    var recipeIngredientsData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double = 0,
        servingDescription: String = "1 serving",
        servings: Double = 1.0,
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
        self.servings = servings
        self.mealType = mealType
        self.loggedAt = loggedAt
        self.source = source
        self.photoData = photoData
        self.notes = notes
    }
}
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
    var ingredientData: Data?
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
}
@Model
final class WeightEntry {
    var id: UUID
    var weightKg: Double
    var recordedAt: Date

    init(id: UUID = UUID(), weightKg: Double, recordedAt: Date = Date()) {
        self.id = id
        self.weightKg = weightKg
        self.recordedAt = recordedAt
    }
}
@Model
final class WaterEntry {
    var id: UUID
    var amountOz: Int
    var recordedAt: Date

    init(id: UUID = UUID(), amountOz: Int, recordedAt: Date = Date()) {
        self.id = id
        self.amountOz = amountOz
        self.recordedAt = recordedAt
    }
}
@Model
final class WorkoutLog {
    var id: UUID
    var workoutType: WorkoutType
    var startedAt: Date
    var durationSeconds: Int
    var steps: Int
    var caloriesBurned: Int
    var distanceMeters: Double

    init(
        id: UUID = UUID(),
        workoutType: WorkoutType = .other,
        startedAt: Date = Date(),
        durationSeconds: Int = 0,
        steps: Int = 0,
        caloriesBurned: Int = 0,
        distanceMeters: Double = 0
    ) {
        self.id = id
        self.workoutType = workoutType
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.steps = steps
        self.caloriesBurned = caloriesBurned
        self.distanceMeters = distanceMeters
    }
}
}

enum PrePrecisionFueliSchema: VersionedSchema {
static var versionIdentifier = Schema.Version(2, 0, 0)
static var models: [any PersistentModel.Type] { [UserProfile.self, FoodLog.self, SavedMeal.self, WeightEntry.self, WaterEntry.self, WorkoutLog.self] }
@Model
final class UserProfile {
    var id: UUID
    var hasCompletedOnboarding: Bool = false
    var sex: BiologicalSex
    var birthDate: Date
    /// Stored in cm internally; displayed as ft/in in the UI.
    var heightCm: Double
    /// Stored in kg internally; displayed as lbs in the UI.
    var startingWeightKg: Double
    var goalWeightKg: Double
    /// Optional body fat percentage (0-100). When set, BMR uses Katch-McArdle (lean mass
    /// based) instead of Mifflin-St Jeor for a more accurate estimate.
    var bodyFatPercent: Double?
    var stepsTier: StepsTier
    var workoutHoursTier: WorkoutHoursTier
    var trainingGoal: TrainingGoal
    var recompFocus: RecompFocus
    /// Desired weight change rate in kg/week (positive for gain, negative for loss).
    var weeklyRateKg: Double
    var dietPreference: DietPreference
    var unitSystem: UnitSystem = UnitSystem.usCustomary

    /// Manual overrides; if nil, computed targets are used.
    var manualCalorieTarget: Int?
    var manualProteinTarget: Int?
    var manualCarbTarget: Int?
    var manualFatTarget: Int?
    var manualFiberTarget: Int?

    /// Optional additions permit lightweight migration of the existing store.
    var healthMaintenanceCalories: Double?
    var healthEnergyDayCount: Int?
    var healthEnergyWindowStart: Date?
    var healthEnergyWindowEnd: Date?

    var hasHealthMaintenance: Bool {
        guard let value = healthMaintenanceCalories else { return false }
        return value.isFinite && value > 0
    }

    var dailyWaterTargetOz: Int

    /// When enabled, yesterday's calorie overshoot trims today's budget (capped at
    /// 15% of the daily target — research favors small, spread-out corrections over
    /// harsh next-day restriction, since weekly energy balance is what drives results).
    var rolloverExcessCalories: Bool = true

    /// Fraction of the daily budget that a rollover correction may not exceed.
    static let rolloverCapFraction = 0.15

    init(
        id: UUID = UUID(),
        hasCompletedOnboarding: Bool = false,
        sex: BiologicalSex = .male,
        birthDate: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date(),
        heightCm: Double = 175,
        startingWeightKg: Double = 75,
        goalWeightKg: Double = 70,
        bodyFatPercent: Double? = nil,
        stepsTier: StepsTier = .tier7to9k,
        workoutHoursTier: WorkoutHoursTier = .oneToThree,
        trainingGoal: TrainingGoal = .cut,
        recompFocus: RecompFocus = .maintenance,
        weeklyRateKg: Double = -0.5,
        dietPreference: DietPreference = .classic,
        dailyWaterTargetOz: Int = 84,
        rolloverExcessCalories: Bool = true,
        unitSystem: UnitSystem = .usCustomary
    ) {
        self.id = id
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.sex = sex
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.startingWeightKg = startingWeightKg
        self.goalWeightKg = goalWeightKg
        self.bodyFatPercent = bodyFatPercent
        self.stepsTier = stepsTier
        self.workoutHoursTier = workoutHoursTier
        self.trainingGoal = trainingGoal
        self.recompFocus = recompFocus
        self.weeklyRateKg = weeklyRateKg
        self.dietPreference = dietPreference
        self.dailyWaterTargetOz = dailyWaterTargetOz
        self.rolloverExcessCalories = rolloverExcessCalories
        self.unitSystem = unitSystem
    }
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
    var servings: Double = 1.0
    var mealType: MealType
    var loggedAt: Date
    var source: LogSource
    /// JPEG data for photo-sourced logs, shown as a thumbnail in history.
    @Attribute(.externalStorage) var photoData: Data?
    var notes: String?
    var savedFoodID: UUID?
    var recipeIngredientsData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double = 0,
        servingDescription: String = "1 serving",
        servings: Double = 1.0,
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
        self.servings = servings
        self.mealType = mealType
        self.loggedAt = loggedAt
        self.source = source
        self.photoData = photoData
        self.notes = notes
    }
}
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
}
@Model
final class WeightEntry {
    var id: UUID
    var weightKg: Double
    var recordedAt: Date

    init(id: UUID = UUID(), weightKg: Double, recordedAt: Date = Date()) {
        self.id = id
        self.weightKg = weightKg
        self.recordedAt = recordedAt
    }
}
@Model
final class WaterEntry {
    var id: UUID
    var amountOz: Int
    var recordedAt: Date

    init(id: UUID = UUID(), amountOz: Int, recordedAt: Date = Date()) {
        self.id = id
        self.amountOz = amountOz
        self.recordedAt = recordedAt
    }
}
@Model
final class WorkoutLog {
    var id: UUID
    var workoutType: WorkoutType
    var startedAt: Date
    var durationSeconds: Int
    var steps: Int
    var caloriesBurned: Int
    var distanceMeters: Double

    init(
        id: UUID = UUID(),
        workoutType: WorkoutType = .other,
        startedAt: Date = Date(),
        durationSeconds: Int = 0,
        steps: Int = 0,
        caloriesBurned: Int = 0,
        distanceMeters: Double = 0
    ) {
        self.id = id
        self.workoutType = workoutType
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.steps = steps
        self.caloriesBurned = caloriesBurned
        self.distanceMeters = distanceMeters
    }
}
}

enum PrecisionFueliSchema: VersionedSchema {
static var versionIdentifier = Schema.Version(3, 0, 0)
static var models: [any PersistentModel.Type] { [UserProfile.self, FoodLog.self, SavedMeal.self, WeightEntry.self, WaterEntry.self, WorkoutLog.self] }
@Model
final class UserProfile {
    var id: UUID
    var hasCompletedOnboarding: Bool = false
    var sex: BiologicalSex
    var birthDate: Date
    /// Stored in cm internally; displayed as ft/in in the UI.
    var heightCm: Double
    /// Stored in kg internally; displayed as lbs in the UI.
    var startingWeightKg: Double
    var goalWeightKg: Double
    /// Optional body fat percentage (0-100). When set, BMR uses Katch-McArdle (lean mass
    /// based) instead of Mifflin-St Jeor for a more accurate estimate.
    var bodyFatPercent: Double?
    var stepsTier: StepsTier
    var workoutHoursTier: WorkoutHoursTier
    var trainingGoal: TrainingGoal
    var recompFocus: RecompFocus
    /// Desired weight change rate in kg/week (positive for gain, negative for loss).
    var weeklyRateKg: Double
    var dietPreference: DietPreference
    var unitSystem: UnitSystem = UnitSystem.usCustomary

    /// Manual overrides; if nil, computed targets are used.
    var manualCalorieTarget: Int?
    var manualProteinTarget: Int?
    var manualCarbTarget: Int?
    var manualFatTarget: Int?
    var manualFiberTarget: Int?

    /// Optional additions permit lightweight migration of the existing store.
    var healthMaintenanceCalories: Double?
    var healthEnergyDayCount: Int?
    var healthEnergyWindowStart: Date?
    var healthEnergyWindowEnd: Date?

    var hasHealthMaintenance: Bool {
        guard let value = healthMaintenanceCalories else { return false }
        return value.isFinite && value > 0
    }

    var dailyWaterTargetOz: Int

    /// When enabled, yesterday's calorie overshoot trims today's budget (capped at
    /// 15% of the daily target — research favors small, spread-out corrections over
    /// harsh next-day restriction, since weekly energy balance is what drives results).
    var rolloverExcessCalories: Bool = true

    /// Fraction of the daily budget that a rollover correction may not exceed.
    static let rolloverCapFraction = 0.15

    init(
        id: UUID = UUID(),
        hasCompletedOnboarding: Bool = false,
        sex: BiologicalSex = .male,
        birthDate: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date(),
        heightCm: Double = 175,
        startingWeightKg: Double = 75,
        goalWeightKg: Double = 70,
        bodyFatPercent: Double? = nil,
        stepsTier: StepsTier = .tier7to9k,
        workoutHoursTier: WorkoutHoursTier = .oneToThree,
        trainingGoal: TrainingGoal = .cut,
        recompFocus: RecompFocus = .maintenance,
        weeklyRateKg: Double = -0.5,
        dietPreference: DietPreference = .classic,
        dailyWaterTargetOz: Int = 84,
        rolloverExcessCalories: Bool = true,
        unitSystem: UnitSystem = .usCustomary
    ) {
        self.id = id
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.sex = sex
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.startingWeightKg = startingWeightKg
        self.goalWeightKg = goalWeightKg
        self.bodyFatPercent = bodyFatPercent
        self.stepsTier = stepsTier
        self.workoutHoursTier = workoutHoursTier
        self.trainingGoal = trainingGoal
        self.recompFocus = recompFocus
        self.weeklyRateKg = weeklyRateKg
        self.dietPreference = dietPreference
        self.dailyWaterTargetOz = dailyWaterTargetOz
        self.rolloverExcessCalories = rolloverExcessCalories
        self.unitSystem = unitSystem
    }
}
@Model
final class FoodLog {
    var id: UUID
    var name: String
    var calories: Int
    var caloriesExact: Double?
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double = 0
    var servingDescription: String
    var servings: Double = 1.0
    var mealType: MealType
    var loggedAt: Date
    var source: LogSource
    /// JPEG data for photo-sourced logs, shown as a thumbnail in history.
    @Attribute(.externalStorage) var photoData: Data?
    var notes: String?
    var savedFoodID: UUID?
    var recipeIngredientsData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double = 0,
        servingDescription: String = "1 serving",
        servings: Double = 1.0,
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
        self.servings = servings
        self.mealType = mealType
        self.loggedAt = loggedAt
        self.source = source
        self.photoData = photoData
        self.notes = notes
    }
}
@Model
final class SavedMeal {
    var id: UUID
    var name: String
    var calories: Int
    var caloriesExact: Double?
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
}
@Model
final class WeightEntry {
    var id: UUID
    var weightKg: Double
    var recordedAt: Date

    init(id: UUID = UUID(), weightKg: Double, recordedAt: Date = Date()) {
        self.id = id
        self.weightKg = weightKg
        self.recordedAt = recordedAt
    }
}
@Model
final class WaterEntry {
    var id: UUID
    var amountOz: Int
    var recordedAt: Date

    init(id: UUID = UUID(), amountOz: Int, recordedAt: Date = Date()) {
        self.id = id
        self.amountOz = amountOz
        self.recordedAt = recordedAt
    }
}
@Model
final class WorkoutLog {
    var id: UUID
    var workoutType: WorkoutType
    var startedAt: Date
    var durationSeconds: Int
    var steps: Int
    var caloriesBurned: Int
    var distanceMeters: Double

    init(
        id: UUID = UUID(),
        workoutType: WorkoutType = .other,
        startedAt: Date = Date(),
        durationSeconds: Int = 0,
        steps: Int = 0,
        caloriesBurned: Int = 0,
        distanceMeters: Double = 0
    ) {
        self.id = id
        self.workoutType = workoutType
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.steps = steps
        self.caloriesBurned = caloriesBurned
        self.distanceMeters = distanceMeters
    }
}
}

enum CurrentFueliSchema: VersionedSchema {
 static var versionIdentifier = Schema.Version(4, 0, 0)
 static var models: [any PersistentModel.Type] { [UserProfile.self, FoodLog.self, SavedMeal.self, WeightEntry.self, WaterEntry.self, WorkoutLog.self] }
}
enum FueliMigrationPlan: SchemaMigrationPlan {
 static var schemas: [any VersionedSchema.Type] { [LegacyFueliSchema.self, HealthSetupFueliSchema.self, LibraryPreviewFueliSchema.self, PrePrecisionFueliSchema.self, PrecisionFueliSchema.self, CurrentFueliSchema.self] }
 static var stages: [MigrationStage] {
  [.lightweight(fromVersion: LegacyFueliSchema.self, toVersion: HealthSetupFueliSchema.self),
   .lightweight(fromVersion: HealthSetupFueliSchema.self, toVersion: LibraryPreviewFueliSchema.self),
   .custom(fromVersion: LibraryPreviewFueliSchema.self, toVersion: PrePrecisionFueliSchema.self, willMigrate: nil, didMigrate: { context in
       for favorite in try context.fetch(FetchDescriptor<PrePrecisionFueliSchema.SavedMeal>()) { favorite.isFavorite = true }
       try context.save()
   }),
   .lightweight(fromVersion: PrePrecisionFueliSchema.self, toVersion: PrecisionFueliSchema.self),
   .lightweight(fromVersion: PrecisionFueliSchema.self, toVersion: CurrentFueliSchema.self)]
 }
}
