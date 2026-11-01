import Foundation
import SwiftData
import CoreMotion

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? "Male" : "Female" }
}

/// Average daily step count bucket — drives the NEAT (non-exercise activity
/// thermogenesis) contribution to TDEE, independent of formal workouts.
enum StepsTier: String, Codable, CaseIterable, Identifiable {
    case tier3to5k, tier5to7k, tier7to9k, tier9to11k, tier11to13k, tier13kPlus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tier3to5k: return "3,000–5,000 steps"
        case .tier5to7k: return "5,000–7,000 steps"
        case .tier7to9k: return "7,000–9,000 steps"
        case .tier9to11k: return "9,000–11,000 steps"
        case .tier11to13k: return "11,000–13,000 steps"
        case .tier13kPlus: return "13,000+ steps"
        }
    }

    /// Representative daily step count used for the NEAT estimate.
    var representativeSteps: Double {
        switch self {
        case .tier3to5k: return 4000
        case .tier5to7k: return 6000
        case .tier7to9k: return 8000
        case .tier9to11k: return 10000
        case .tier11to13k: return 12000
        case .tier13kPlus: return 14000
        }
    }

    /// Returns the tier whose range contains the given average daily step count.
    static func matching(steps: Double) -> StepsTier {
        switch steps {
        case ..<5_000:          return .tier3to5k
        case 5_000..<7_000:     return .tier5to7k
        case 7_000..<9_000:     return .tier7to9k
        case 9_000..<11_000:    return .tier9to11k
        case 11_000..<13_000:   return .tier11to13k
        default:                return .tier13kPlus
        }
    }
}

//func avgStepsOver(days: Int){
//    let pedometer = CMPedometer()
//    let cal = Calendar.current
//    let today = Date()
//    
//    let group = DispatchGroup()
//    var totalSteps = 0
//    var daysWithData = 0
//    let lock = NSLock()
//    
//    for offset in 0..<days {
//        // guard is if date calculation works fine, keep going, if it fails continue (skip this iteration)
//        guard let start = cal.date(byAdding: .day, value: -offset - 1, to: today),
//              let end = cal.date(byAdding: .day, value: -offset, to: today)
//                else { continue }
//        
//        // group is because pedometer queries are asynchronous, groups just track them and notify when all are finished.
//        group.enter()
//        pedometer.queryPedometerData(from: start, to: end) { data, error in
//            // defer just defer the instructions inside until the current scope is left
//            defer { group.leave() }
//            guard let data = data else { return }
//            
//            // Since the queries can run on multiple threads at a time, lock ensures multiple different things can't modify the same piece of data. It does this by making everything wait before the stuff inside the lock is done running.
//            lock.lock()
//            defer { lock.unlock() } // Guards against some error not letting code reach the unlock stage
//            totalSteps += data.numberOfSteps.intValue
//            daysWithData += 1
//            lock.unlock()
//            
//            
//        }
//        
//    }
//    
//    group.notify(queue: .main) { [weak self] in
//        guard daysWithData > 0 else {
//            self?.averageSteps = 0
//            return
//        }
//        self?.averageSteps = Double(totalSteps)/Double(daysWithData)
//        
//    }
//}

/// Hours spent doing formal exercise per week — drives the EAT (exercise activity
/// thermogenesis) contribution to TDEE, separate from everyday NEAT/steps.
enum WorkoutHoursTier: String, Codable, CaseIterable, Identifiable {
    case zeroToOne, oneToThree, threeToFive, sixToEight, eightPlus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .zeroToOne: return "0–1 hours/week"
        case .oneToThree: return "1–3 hours/week"
        case .threeToFive: return "3–5 hours/week"
        case .sixToEight: return "6–8 hours/week"
        case .eightPlus: return "8+ hours/week"
        }
    }

    /// Representative weekly workout hours used for the EAT estimate.
    var representativeHours: Double {
        switch self {
        case .zeroToOne: return 0.5
        case .oneToThree: return 2
        case .threeToFive: return 4
        case .sixToEight: return 7
        case .eightPlus: return 9
        }
    }
}

/// Training goal, matching common bodybuilding/fitness framing (e.g. TrainBloom-style
/// calculators) rather than plain "lose/maintain/gain".
enum TrainingGoal: String, Codable, CaseIterable, Identifiable {
    case cut, bulk, recomp

    var id: String { rawValue }
    var label: String {
        switch self {
        case .cut: return "Cut (lose fat)"
        case .bulk: return "Bulk (gain muscle)"
        case .recomp: return "Body Recomposition"
        }
    }
}

/// Recomp doesn't have one standard calorie direction, so it's broken into its own
/// sub-choice: lean gain (mini bulk), true maintenance, or fat loss (mini cut) while
/// prioritizing protein/training to reshape body composition.
enum RecompFocus: String, Codable, CaseIterable, Identifiable {
    case leanGain, maintenance, fatLoss

    var id: String { rawValue }
    var label: String {
        switch self {
        case .leanGain: return "Gaining lean mass"
        case .maintenance: return "Maintenance"
        case .fatLoss: return "Losing fat"
        }
    }
}

enum DietPreference: String, Codable, CaseIterable, Identifiable {
    case classic, keto, vegan, vegetarian, paleo

    var id: String { rawValue }
    var label: String {
        switch self {
        case .classic: return "Classic"
        case .keto: return "Keto"
        case .vegan: return "Vegan"
        case .vegetarian: return "Vegetarian"
        case .paleo: return "Paleo"
        }
    }

    /// Target macro split as fractions of total calories: (protein, carbs, fat).
    var macroSplit: (protein: Double, carbs: Double, fat: Double) {
        switch self {
        case .classic: return (0.30, 0.40, 0.30)
        case .keto: return (0.30, 0.05, 0.65)
        case .vegan, .vegetarian: return (0.25, 0.50, 0.25)
        case .paleo: return (0.35, 0.25, 0.40)
        }
    }
}

// MARK: - Units

/// Display unit system. All values are stored metric (kg/cm) or in oz for water;
/// this only affects how they're shown and entered.
enum UnitSystem: String, Codable, CaseIterable, Identifiable {
    case usCustomary, metric

    var id: String { rawValue }
    var label: String { self == .usCustomary ? "US (lbs, ft, oz)" : "Metric (kg, cm, ml)" }
    var weightUnit: String { self == .usCustomary ? "lbs" : "kg" }
    var waterUnit: String { self == .usCustomary ? "oz" : "ml" }
}

// MARK: - Unit conversion helpers (stored in metric, displayed per unit system)

enum UnitConversion {
    static func kgToLb(_ kg: Double) -> Double { kg * 2.20462262 }
    static func lbToKg(_ lb: Double) -> Double { lb / 2.20462262 }
    static func cmToTotalInches(_ cm: Double) -> Double { cm / 2.54 }
    static func inchesToCm(_ totalInches: Double) -> Double { totalInches * 2.54 }
    static func ozToMl(_ oz: Double) -> Double { oz * 29.5735296 }
    static func mlToOz(_ ml: Double) -> Double { ml / 29.5735296 }
}

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
    var manualMaintenanceCalories: Double?
    var healthMaintenanceCalories: Double?
    var healthEnergyDayCount: Int?
    var healthEnergyWindowStart: Date?
    var healthEnergyWindowEnd: Date?

    var hasHealthMaintenance: Bool {
        guard let value = healthMaintenanceCalories else { return false }
        return value.isFinite && value > 0
    }

    /// An entered full-day total is independent of a manually overridden intake target.
    /// Bounds reject entry mistakes; they are not clinical eligibility thresholds.
    static func isValidManualBurn(_ value: Double) -> Bool {
        value.isFinite && (500...15000).contains(value)
    }

    var hasManualMaintenance: Bool {
        manualMaintenanceCalories.map(Self.isValidManualBurn) ?? false
    }

    var maintenanceAverageCalories: Double? {
        if hasManualMaintenance { return manualMaintenanceCalories }
        return hasHealthMaintenance ? healthMaintenanceCalories : nil
    }

    var hasMaintenanceAverage: Bool { maintenanceAverageCalories != nil }

    var maintenanceSourceLabel: String {
        if hasManualMaintenance { return "Manually entered average total burn" }
        return hasHealthMaintenance ? "Apple Health average total burn" : "Body and activity estimate"
    }

    func useActivityEstimates() {
        manualMaintenanceCalories = nil
        healthMaintenanceCalories = nil
        healthEnergyDayCount = nil
        healthEnergyWindowStart = nil
        healthEnergyWindowEnd = nil
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

    /// Weight in the user's display unit (lbs or kg).
    func displayWeight(_ kg: Double) -> Double {
        unitSystem == .metric ? kg : UnitConversion.kgToLb(kg)
    }

    /// Converts a weight entered in the user's display unit back to kg for storage.
    func weightKg(fromDisplay value: Double) -> Double {
        unitSystem == .metric ? value : UnitConversion.lbToKg(value)
    }

    var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 25
    }

    var heightFeet: Int { Int(UnitConversion.cmToTotalInches(heightCm) / 12) }
    var heightRemainderInches: Int { Int(UnitConversion.cmToTotalInches(heightCm).rounded()) % 12 }
    var startingWeightLb: Double { UnitConversion.kgToLb(startingWeightKg) }
    var goalWeightLb: Double { UnitConversion.kgToLb(goalWeightKg) }
    var weeklyRateLb: Double { UnitConversion.kgToLb(weeklyRateKg) }

    /// Mifflin-St Jeor's sex-specific constant, applied as a hormonal adjustment on top
    /// of the Katch-McArdle lean-mass base — the same blend fitness calculators like
    /// TrainBloom/FitnessStuff use, since lean mass alone doesn't fully capture the small
    /// metabolic difference between sexes at equal lean mass.
    private var sexOffset: Double { sex == .male ? 5 : -161 }

    /// Mifflin-St Jeor BMR (used when body fat % is unknown, so lean mass can't be derived).
    private func mifflinStJeorBMR(currentWeightKg: Double) -> Double {
        (10 * currentWeightKg) + (6.25 * heightCm) - (5 * Double(ageYears)) + sexOffset
    }

    /// Katch-McArdle BMR based on lean body mass, blended with the Mifflin-St Jeor sex
    /// offset — more accurate than total-bodyweight formulas when body fat % is known.
    private func katchMcArdleBMR(currentWeightKg: Double, bodyFatPercent: Double) -> Double {
        let leanMassKg = currentWeightKg * (1 - bodyFatPercent / 100)
        return 370 + (21.6 * leanMassKg) + sexOffset
    }

    func bmr(currentWeightKg: Double) -> Double {
        if let bf = bodyFatPercent {
            return katchMcArdleBMR(currentWeightKg: currentWeightKg, bodyFatPercent: bf)
        }
        return mifflinStJeorBMR(currentWeightKg: currentWeightKg)
    }

    /// NEAT: non-exercise activity thermogenesis, driven by daily step count rather than
    /// a flat "activity level" multiplier. ~0.045 kcal/step approximates the energy cost
    /// of walking regardless of body size differences already captured by BMR.
    private static let kcalPerStep = 0.045

    /// Live step count for today, when available, refines the NEAT estimate;
    /// otherwise falls back to the onboarding steps tier's representative value.
    func neatCalories(liveStepsToday: Int? = nil) -> Double {
        let steps = liveStepsToday.map(Double.init) ?? stepsTier.representativeSteps
        return steps * Self.kcalPerStep
    }

    /// EAT: exercise activity thermogenesis from formal workouts, estimated at ~450
    /// kcal/hour of exercise, averaged across the week into a daily figure — kept separate
    /// from NEAT so someone who trains hard but is otherwise sedentary isn't double-counted
    /// against someone who is very active outside the gym but trains less.
    private static let kcalPerWorkoutHour = 450.0

    var eatCalories: Double {
        (workoutHoursTier.representativeHours * Self.kcalPerWorkoutHour) / 7
    }

    /// Readable HealthKit active energy replaces BOTH estimated NEAT and exercise.
    /// Until Health data is available, retain the configured activity estimate.
    /// BMR remains a full-day estimate while active energy is recorded so far.
    func tdee(currentWeightKg: Double, liveStepsToday: Int? = nil, activeEnergyCalories: Double? = nil) -> Double {
        if let average = maintenanceAverageCalories { return average }
        if let activeEnergyCalories, activeEnergyCalories.isFinite, activeEnergyCalories >= 0 {
            return bmr(currentWeightKg: currentWeightKg) + activeEnergyCalories
        }
        return bmr(currentWeightKg: currentWeightKg) + neatCalories(liveStepsToday: liveStepsToday) + eatCalories
    }

    /// Starting adjustments informed by adult clinical/sport studies; not a prediction
    /// of weekly weight change. See CALORIE_EVIDENCE.md for population limits.
    func dailyCalorieDelta(maintenance: Double, weightKg: Double) -> Double {
        guard ageYears >= 18, maintenance.isFinite, maintenance > 0,
              weightKg.isFinite, weightKg > 0 else { return 0 }
        switch trainingGoal {
        case .cut:
            // The requested rate selects a starting dose; cap at 25%, 750 kcal,
            // and the energy equivalent of 0.7% body mass/week.
            let requested = abs(weeklyRateKg.isFinite ? weeklyRateKg : 0) * 7700 / 7
            return -min(requested, maintenance * 0.25, 750, weightKg * 0.007 * 7700 / 7)
        case .bulk:
            let requested = abs(weeklyRateKg.isFinite ? weeklyRateKg : 0) * 7700 / 7
            return min(requested, maintenance * 0.10)
        case .recomp:
            switch recompFocus {
            case .leanGain: return maintenance * 0.05
            case .maintenance: return 0
            case .fatLoss: return -min(maintenance * 0.10, 500)
            }
        }
    }

    func calorieTarget(currentWeightKg: Double, liveStepsToday: Int? = nil, activeEnergyCalories: Double? = nil) -> Int {
        if let manual = manualCalorieTarget { return manual }
        let maintenance = tdee(currentWeightKg: currentWeightKg, liveStepsToday: liveStepsToday, activeEnergyCalories: activeEnergyCalories)
        return goalCalorieTarget(maintenance: maintenance, weightKg: currentWeightKg)
    }

    /// Shared by the actual target and the draft manual-burn preview.
    /// Explicit food-intake overrides are handled by calorieTarget(), not this preview.
    func goalCalorieTarget(maintenance: Double, weightKg: Double) -> Int {
        let target = maintenance + dailyCalorieDelta(maintenance: maintenance, weightKg: weightKg)
        guard target.isFinite else { return 0 }
        let floor = sex == .male ? 1500 : 1200
        return max(floor, Int(target.rounded()))
    }

    func macroTargets(currentWeightKg: Double, liveStepsToday: Int? = nil, activeEnergyCalories: Double? = nil) -> (protein: Int, carbs: Int, fat: Int) {
        if let p = manualProteinTarget, let c = manualCarbTarget, let f = manualFatTarget {
            return (p, c, f)
        }
        let calories = Double(calorieTarget(currentWeightKg: currentWeightKg, liveStepsToday: liveStepsToday, activeEnergyCalories: activeEnergyCalories))

        // Bulk/recomp lean up protein relative to bodyweight (~1g/lb), matching
        // physique-calculator conventions, then split the remainder by diet preference.
        let bodyweightLb = UnitConversion.kgToLb(currentWeightKg)
        let proteinFloorG = (trainingGoal == .bulk || trainingGoal == .recomp) ? bodyweightLb : bodyweightLb * 0.8

        let split = dietPreference.macroSplit
        let splitProteinG = (calories * split.protein) / 4
        let proteinG = max(proteinFloorG, splitProteinG)

        let remainingCalories = max(0, calories - proteinG * 4)
        let carbFraction = split.carbs / (split.carbs + split.fat)
        let carbsG = (remainingCalories * carbFraction) / 4
        let fatG = (remainingCalories * (1 - carbFraction)) / 9

        return (Int(proteinG.rounded()), Int(carbsG.rounded()), Int(fatG.rounded()))
    }

    /// Institute of Medicine Adequate Intake: 14 g of fiber per 1,000 kcal consumed —
    /// the same rule behind the familiar 38 g (men) / 25 g (women) daily values, but
    /// personalized to this user's calorie target.
    private static let fiberGramsPer1000Kcal = 14.0

    func fiberTarget(currentWeightKg: Double, liveStepsToday: Int? = nil, activeEnergyCalories: Double? = nil) -> Int {
        if let manual = manualFiberTarget { return manual }
        let calories = Double(calorieTarget(currentWeightKg: currentWeightKg, liveStepsToday: liveStepsToday, activeEnergyCalories: activeEnergyCalories))
        return Int((calories * Self.fiberGramsPer1000Kcal / 1000).rounded())
    }
}
