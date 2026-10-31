import Foundation
import Testing
@testable import CalClone

@MainActor
struct HealthActivityTests {
    @Test func activeEnergyReplacesBothActivityEstimates() {
        let p = UserProfile()
        let bmr = p.bmr(currentWeightKg: 75)
        #expect(abs(p.tdee(currentWeightKg: 75, liveStepsToday: 20000, activeEnergyCalories: 321.5) - bmr - 321.5) < 0.00001)
        #expect(p.tdee(currentWeightKg: 75, activeEnergyCalories: 0) == bmr)
    }
    @Test func unavailableAndInvalidDataUseConfiguredEstimate() {
        let p = UserProfile()
        let expected = p.bmr(currentWeightKg: 75) + p.neatCalories() + p.eatCalories
        #expect(p.tdee(currentWeightKg: 75) == expected)
        #expect(p.tdee(currentWeightKg: 75, activeEnergyCalories: .nan) == expected)
        #expect(p.tdee(currentWeightKg: 75, activeEnergyCalories: -1) == expected)
    }
    @Test func manualTargetRemainsFixed() {
        let p = UserProfile()
        p.manualCalorieTarget = 2200
        #expect(p.calorieTarget(currentWeightKg: 75, activeEnergyCalories: 900) == 2200)
    }
    @Test func macroAndFiberTargetsUseSameActivityBudget() {
        let p = UserProfile()
        let low = p.macroTargets(currentWeightKg: 75, activeEnergyCalories: 100)
        let high = p.macroTargets(currentWeightKg: 75, activeEnergyCalories: 1000)
        #expect(high.carbs > low.carbs)
        #expect(p.fiberTarget(currentWeightKg: 75, activeEnergyCalories: 1000) > p.fiberTarget(currentWeightKg: 75, activeEnergyCalories: 100))
    }
    @Test func calendarDayHandlesDSTAndClampsToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        let past = try #require(HealthKitService.dayInterval(containing: day, now: tomorrow, calendar: calendar))
        #expect(past.duration == 23 * 3600)
        let noon = day.addingTimeInterval(10 * 3600)
        #expect(HealthKitService.dayInterval(containing: day, now: noon, calendar: calendar)?.end == noon)
        #expect(HealthKitService.dayInterval(containing: tomorrow, now: noon, calendar: calendar) == nil)
    }
}
