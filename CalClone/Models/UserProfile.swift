import Foundation
import SwiftData

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
}

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
    var hasCompletedOnboarding: Bool
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

    /// TDEE = BMR + NEAT (steps) + EAT (workouts), rather than one blended multiplier —
    /// this avoids overestimating calories for people who work out a lot but are otherwise
    /// sedentary, and underestimating for people who are on their feet all day but train less.
    func tdee(currentWeightKg: Double, liveStepsToday: Int? = nil) -> Double {
        bmr(currentWeightKg: currentWeightKg) + neatCalories(liveStepsToday: liveStepsToday) + eatCalories
    }

    /// Effective daily kcal delta from maintenance, derived from goal + (for recomp) focus.
    private func dailyCalorieDelta() -> Double {
        switch trainingGoal {
        case .cut, .bulk:
            return (weeklyRateKg * 7700) / 7
        case .recomp:
            switch recompFocus {
            case .leanGain: return 200
            case .maintenance: return 0
            case .fatLoss: return -300
            }
        }
    }

    /// Daily calorie target factoring in the training goal (cut/bulk/recomp). Pass today's
    /// live step count when available to refine the NEAT contribution.
    func calorieTarget(currentWeightKg: Double, liveStepsToday: Int? = nil) -> Int {
        if let manual = manualCalorieTarget { return manual }
        let target = tdee(currentWeightKg: currentWeightKg, liveStepsToday: liveStepsToday) + dailyCalorieDelta()
        return max(1200, Int(target.rounded()))
    }

    func macroTargets(currentWeightKg: Double, liveStepsToday: Int? = nil) -> (protein: Int, carbs: Int, fat: Int) {
        if let p = manualProteinTarget, let c = manualCarbTarget, let f = manualFatTarget {
            return (p, c, f)
        }
        let calories = Double(calorieTarget(currentWeightKg: currentWeightKg, liveStepsToday: liveStepsToday))

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

    func fiberTarget(currentWeightKg: Double, liveStepsToday: Int? = nil) -> Int {
        if let manual = manualFiberTarget { return manual }
        let calories = Double(calorieTarget(currentWeightKg: currentWeightKg, liveStepsToday: liveStepsToday))
        return Int((calories * Self.fiberGramsPer1000Kcal / 1000).rounded())
    }
}
