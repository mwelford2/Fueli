import Foundation
import SwiftData
import Testing
@testable import Fueli

struct RigorousDomainTests {
    @Test(arguments: 1...128)
    func nutrientScalingConservesAmountsAndNeverMutatesReference(_ seed: Int) throws {
        let calories = Double(seed) * 17.125
        let reference = try ServingNutrition(calories: calories, protein: Double(seed) * 0.875,
            carbohydrates: Double(seed) * 1.125, fat: Double(seed) * 0.3125, fiber: Double(seed) * 0.125)
        for multiplier in [0.01, 0.125, 0.5, 1, 2.5, 100] {
            let total = try reference.scaled(by: multiplier)
            #expect(abs(total.calories - calories * multiplier) < 0.0000001)
            #expect(abs(total.protein / multiplier - reference.protein) < 0.0000001)
            #expect(reference.calories == calories)
            let a = try reference.scaled(by: multiplier * 0.25)
            let b = try reference.scaled(by: multiplier * 0.75)
            #expect(abs(total.carbohydrates - a.carbohydrates - b.carbohydrates) < 0.0000001)
        }
    }

    @Test(arguments: 0..<100)
    func everyGTINPositionRejectsSingleDigitCorruption(_ seed: Int) throws {
        for length in [8, 12, 13] {
            let prefix = (0..<(length - 1)).map { ($0 * 7 + seed * 3) % 10 }
            let weights = (0..<(length - 1)).map { (length - $0).isMultiple(of: 2) ? 3 : 1 }
            let check = (10 - zip(prefix, weights).reduce(0) { $0 + $1.0 * $1.1 } % 10) % 10
            let digits = prefix + [check]
            let code = digits.map(String.init).joined()
            let normalized = try RetailBarcode(code)
            #expect(normalized.canonical == (length == 12 ? "0" + code : code))
            for index in digits.indices {
                var broken = digits; broken[index] = (broken[index] + 1) % 10
                #expect((try? RetailBarcode(broken.map(String.init).joined())) == nil)
            }
        }
    }

    @Test func barcodeFormatAndUnicodeAreNeverGuessed() throws {
        #expect(throws: (any Swift.Error).self) { try RetailBarcode("96385074", format: .upca) }
        #expect(throws: (any Swift.Error).self) { try RetailBarcode("036000291452", format: .ean13) }
        for payload in ["", "0", "123", " 036000291452", "036000291452\n", "٠٣٦٠٠٠٢٩١٤٥٢", "０３６０００２９１４５２"] {
            #expect((try? RetailBarcode(payload)) == nil)
            #expect(!RetailBarcode.validChecksum(payload))
        }
    }

    @Test func allUPCEExpansionBranchesAndBothNumberSystems() throws {
        for system in ["0", "1"] {
            for last in 0...9 {
                let body = system + "42526" + String(last)
                let expandedBody: String
                if last <= 2 { expandedBody = system + "42" + String(last) + "0000526" }
                else if last == 3 { expandedBody = system + "4250000026" }
                else if last == 4 { expandedBody = system + "4252000006" }
                else { expandedBody = system + "425260000" + String(last) }
                let sum = expandedBody.enumerated().reduce(0) { $0 + $1.element.wholeNumberValue! * ($1.offset.isMultiple(of: 2) ? 3 : 1) }
                let check = String((10 - sum % 10) % 10)
                #expect(try RetailBarcode(body + check, format: .upce).canonical == "0" + expandedBody + check)
            }
        }
    }

    @Test func nonfiniteAndExtremeWorkoutInputsCannotTrap() {
        #expect(PedometerService.workoutCalories(met: 8, weightKg: 75, durationSeconds: 1800) == 300)
        for invalid in [Double.nan, .infinity, -.infinity, -1, 1e308] {
            #expect(PedometerService.workoutCalories(met: invalid, weightKg: 75, durationSeconds: 600) == 0)
            #expect(PedometerService.workoutCalories(met: 8, weightKg: invalid, durationSeconds: 600) == 0)
        }
        #expect(PedometerService.workoutCalories(met: 8, weightKg: 75, durationSeconds: Int.max) == 0)
        #expect(PedometerService.workoutCalories(met: 8, weightKg: 75, durationSeconds: -1) == 0)
        for type in WorkoutType.allCases { #expect(type.met > 0 && !type.label.isEmpty && !type.icon.isEmpty) }
    }

    @MainActor @Test(arguments: TrainingGoal.allCases, DietPreference.allCases)
    func allGoalsDietsSexesAndBodySizesKeepComputedMacroEnergyConsistent(_ goal: TrainingGoal, _ diet: DietPreference) {
        for sex in BiologicalSex.allCases {
            let profile = UserProfile(sex: sex, trainingGoal: goal, dietPreference: diet)
            for weight in [40.0, 75, 150, 350] {
                for burn in [500.0, 1500, 2500, 6000, 15000] {
                    profile.manualMaintenanceCalories = burn
                    let target = profile.calorieTarget(currentWeightKg: weight)
                    let macros = profile.macroTargets(currentWeightKg: weight)
                    #expect(target > 0)
                    #expect(macros.protein >= 0 && macros.carbs >= 0 && macros.fat >= 0)
                    #expect(abs(macros.protein * 4 + macros.carbs * 4 + macros.fat * 9 - target) <= 9)
                    let delta = profile.dailyCalorieDelta(maintenance: burn, weightKg: weight)
                    #expect(delta.isFinite)
                    if goal == .cut { #expect(delta <= 0 && delta >= -750 && delta >= -burn * 0.25) }
                    if goal == .bulk { #expect(delta >= 0 && delta <= burn * 0.1) }
                }
            }
        }
    }

    @MainActor @Test func partialOverridesDoNotEraseOtherExplicitUserChoices() {
        let p = UserProfile(); let before = p.macroTargets(currentWeightKg: 75)
        p.manualProteinTarget = 123
        let after = p.macroTargets(currentWeightKg: 75)
        #expect(after.protein == 123 && after.carbs == before.carbs && after.fat == before.fat)
        p.manualCarbTarget = 0; p.manualFatTarget = 45
        #expect(p.macroTargets(currentWeightKg: 75).carbs == 0)
        #expect(p.macroTargets(currentWeightKg: 75).fat == 45)
        p.manualCalorieTarget = -1
        #expect(p.calorieTarget(currentWeightKg: 75) > 0)
        p.healthMaintenanceCalories = 1e308
        #expect(!p.hasHealthMaintenance)
        #expect(p.goalCalorieTarget(maintenance: 1e308, weightKg: 75) == 0)
        #expect(p.macroTargets(currentWeightKg: .nan).protein == 0)
    }

    @Test func unitRoundTripsAndMealTimeBoundaries() throws {
        for value in [0.01, 1, 28.349523125, 75, 1000] {
            #expect(abs(UnitConversion.lbToKg(UnitConversion.kgToLb(value)) - value) < 1e-9)
            #expect(abs(UnitConversion.mlToOz(UnitConversion.ozToMl(value)) - value) < 1e-9)
            #expect(abs(UnitConversion.inchesToCm(UnitConversion.cmToTotalInches(value)) - value) < 1e-9)
        }
        for hour in 0..<24 {
            let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15, hour: hour)))
            let expected: MealType = (4..<11).contains(hour) ? .breakfast : (11..<16).contains(hour) ? .lunch : (16..<21).contains(hour) ? .dinner : .snack
            #expect(MealType.suggested(for: date) == expected)
        }
        for value in [Double.nan, .infinity, -.infinity, -1, 0, 1001] { #expect(!EntryValidation.weightKg(value)) }
    }

    @Test(arguments: ["CASHEWS 4.99", "TOTAL GRAIN CEREAL 3.99", "123456 YGRT 1.99", "CHK BRST BNLS 1.5 LB 8.99", "ORG APPLES 2.99"])
    func foodReceiptRowsAreNotSilentlyDiscarded(_ row: String) {
        let parsed = ReceiptParser.parse(row, confidence: 0.7)
        #expect(!parsed.skip && !parsed.imported)
        #expect(!parsed.name.contains("123456"))
    }

    @Test(arguments: ["SUB TOTAL 11.99", "TOTAL 11.99", "TOTAL DUE 12.45", "TAX 0.46", "CASH 20.00", "VISA ****1234", "COUPON -1.00", "DISCOUNT 0.99", "CHANGE 7.55"])
    func receiptMetadataIsNotFood(_ row: String) { #expect(ReceiptParser.parse(row, confidence: 0.9).skip) }

    @Test func invalidOCRCoordinatesAndConfidenceStayUnresolved() {
        #expect(ReceiptParser.parse("APPLES 2.99", confidence: .nan).confidence == 0)
        let rows = ReceiptParser.reconstruct([
            .init(text: "APPLES", x: 0.1, y: 0.8, height: 0.02, confidence: 0.5),
            .init(text: "2.99", x: 0.8, y: 0.8, height: 0.02, confidence: 0.6),
            .init(text: "BAD", x: .nan, y: 0.8, height: 0.02, confidence: 1)])
        #expect(rows.count == 1 && rows[0].name == "apples" && !rows[0].imported)
    }
}
