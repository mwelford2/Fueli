import Foundation
import Testing
import SwiftData
@testable import CalClone

@MainActor
struct HealthEnergyPlanTests {
    private let end = Date(timeIntervalSince1970: 1800000000)
    private func days(_ count: Int, active: Double? = 500, resting: Double? = 1800, coverage: Double = 1) -> [HealthKitService.DailyEnergy] {
        (1...count).map { .init(date: end.addingTimeInterval(-Double($0) * 86400), active: active, resting: resting, restingCoverage: coverage) }
    }
    @Test func averageIncludesRestingAndExcludesMissingOrPartialDays() throws {
        let records = days(7) + [.init(date: end.addingTimeInterval(-8 * 86400), active: nil, resting: 1800, restingCoverage: 1),
                                .init(date: end.addingTimeInterval(-9 * 86400), active: 200, resting: nil, restingCoverage: 0.2)]
        let average = try #require(HealthKitService.averageTotalEnergy(records, before: end))
        #expect(average.calories == 2300)
        #expect(average.days == 7)
        #expect(HealthKitService.averageTotalEnergy(days(6), before: end) == nil)
        #expect(HealthKitService.averageTotalEnergy(days(7, resting: nil), before: end) == nil)
    }
    @Test func dailyAggregateSamplesRemainEligible() {
        #expect(HealthKitService.averageTotalEnergy(days(7, coverage: 0), before: end)?.calories == 2300)
    }
    @Test func zeroActiveIsValidButInvalidEnergyAndTodayAreRejected() {
        #expect(HealthKitService.averageTotalEnergy(days(7, active: 0), before: end)?.calories == 1800)
        #expect(HealthKitService.averageTotalEnergy(days(7, active: .nan), before: end) == nil)
        #expect(HealthKitService.averageTotalEnergy(days(7, resting: -1), before: end) == nil)
        let today = HealthKitService.DailyEnergy(date: end, active: 500, resting: 1800, restingCoverage: 1)
        #expect(HealthKitService.averageTotalEnergy(days(6) + [today], before: end) == nil)
    }
    @Test func coverageDoesNotDoubleCountOverlappingDevices() {
        let day = DateInterval(start: end, duration: 86400)
        let half = DateInterval(start: end, duration: 43200)
        #expect(HealthKitService.coverage([half, half], in: day) == 0.5)
        #expect(HealthKitService.coverage([day, half], in: day) == 1)
    }
    @Test func healthTotalReplacesBMRStepsExerciseAndToday() {
        let p = UserProfile()
        p.healthMaintenanceCalories = 2500
        #expect(p.tdee(currentWeightKg: 75, liveStepsToday: 25000, activeEnergyCalories: 900) == 2500)
        p.manualCalorieTarget = 2200
        #expect(p.calorieTarget(currentWeightKg: 75) == 2200)
    }
    @Test func goalDirectionAndCaps() {
        let p = UserProfile()
        p.trainingGoal = .cut; p.weeklyRateKg = -5
        #expect(p.dailyCalorieDelta(maintenance: 2000, weightKg: 75) == -500)
        p.trainingGoal = .bulk; p.weeklyRateKg = 5
        #expect(p.dailyCalorieDelta(maintenance: 2000, weightKg: 75) == 200)
        p.trainingGoal = .recomp; p.recompFocus = .maintenance
        #expect(p.dailyCalorieDelta(maintenance: 2000, weightKg: 75) == 0)
        p.recompFocus = .leanGain
        #expect(p.dailyCalorieDelta(maintenance: 2000, weightKg: 75) == 100)
        p.recompFocus = .fatLoss
        #expect(p.dailyCalorieDelta(maintenance: 2000, weightKg: 75) == -200)
        p.birthDate = Date()
        #expect(p.dailyCalorieDelta(maintenance: 2000, weightKg: 75) == 0)
    }
    @Test func profileEnergySnapshotPersists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        func configuration() -> ModelConfiguration { ModelConfiguration(url: url) }
        do {
            let container = try ModelContainer(for: UserProfile.self, configurations: configuration())
            let p = UserProfile()
            p.healthMaintenanceCalories = 2345.75
            p.healthEnergyDayCount = 9
            p.healthEnergyWindowEnd = end
            container.mainContext.insert(p)
            try container.mainContext.save()
        }
        let reopened = try ModelContainer(for: UserProfile.self, configurations: configuration())
        let profiles = try reopened.mainContext.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.healthMaintenanceCalories == 2345.75)
        #expect(profiles.first?.healthEnergyDayCount == 9)
        #expect(profiles.first?.healthEnergyWindowEnd == end)
    }
    @Test func manualTotalBurnReplacesHealthActivityAndRestingEstimates() {
        let p = UserProfile()
        p.healthMaintenanceCalories = 3000
        p.manualMaintenanceCalories = 2500.5
        #expect(p.hasManualMaintenance)
        #expect(p.hasMaintenanceAverage)
        #expect(p.tdee(currentWeightKg: 75, liveStepsToday: 30000, activeEnergyCalories: 1200) == 2500.5)
        #expect(p.maintenanceSourceLabel == "Manually entered average total burn")
        p.manualCalorieTarget = 2200
        #expect(p.calorieTarget(currentWeightKg: 75) == 2200)
        p.manualCalorieTarget = nil
        p.manualMaintenanceCalories = nil
        #expect(p.tdee(currentWeightKg: 75) == 3000)
        p.useActivityEstimates()
        #expect(!p.hasMaintenanceAverage)
        #expect(p.healthEnergyDayCount == nil)
    }
    @Test func eachGoalUsesManualBurnAndRecalculatesWhenGoalChanges() {
        let p = UserProfile(startingWeightKg: 75, weeklyRateKg: -0.5)
        p.manualMaintenanceCalories = 2500
        p.trainingGoal = .cut
        #expect(p.calorieTarget(currentWeightKg: 75) == 1950)
        p.trainingGoal = .bulk
        #expect(p.calorieTarget(currentWeightKg: 75) == 2750)
        p.trainingGoal = .recomp
        p.recompFocus = .maintenance
        #expect(p.calorieTarget(currentWeightKg: 75) == 2500)
        p.recompFocus = .leanGain
        #expect(p.calorieTarget(currentWeightKg: 75) == 2625)
        p.recompFocus = .fatLoss
        #expect(p.calorieTarget(currentWeightKg: 75) == 2250)
        #expect(p.dailyCalorieDelta(maintenance: 10000, weightKg: 75) == -500)
        p.birthDate = Date()
        #expect(p.calorieTarget(currentWeightKg: 75) == 2500)
    }
    @Test func invalidManualBurnCannotOverrideAValidBaseline() {
        let p = UserProfile()
        p.healthMaintenanceCalories = 2400
        for value in [Double.nan, .infinity, -.infinity, -10, 0, 499.99, 15000.01] {
            #expect(!UserProfile.isValidManualBurn(value))
            p.manualMaintenanceCalories = value
            #expect(!p.hasManualMaintenance)
            #expect(p.tdee(currentWeightKg: 75) == 2400)
        }
        #expect(UserProfile.isValidManualBurn(500))
        #expect(UserProfile.isValidManualBurn(2500.75))
        #expect(UserProfile.isValidManualBurn(15000))
    }
    @Test func manualBurnPersistsIndependentlyFromIntakeOverride() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".store")
        let schema = Schema(versionedSchema: CurrentFueliSchema.self)
        func seed() throws {
            let container = try ModelContainer(for: schema, migrationPlan: FueliMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: url))
            let profile = UserProfile()
            profile.manualMaintenanceCalories = 2475.25
            profile.healthMaintenanceCalories = 2345.75
            profile.manualCalorieTarget = 2100
            container.mainContext.insert(profile)
            try container.mainContext.save()
        }
        try seed()
        let reopened = try ModelContainer(for: schema, migrationPlan: FueliMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: url))
        let profiles = try reopened.mainContext.fetch(FetchDescriptor<UserProfile>())
        let profile = try #require(profiles.first)
        #expect(profile.manualMaintenanceCalories == 2475.25)
        #expect(profile.healthMaintenanceCalories == 2345.75)
        #expect(profile.tdee(currentWeightKg: 75) == 2475.25)
        #expect(profile.calorieTarget(currentWeightKg: 75) == 2100)
    }

}
