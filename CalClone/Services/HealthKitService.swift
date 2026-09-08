import Foundation
import HealthKit

/// Reads activity and body data from HealthKit (steps, active/resting energy, workouts,
/// distance, body weight, height) to personalize calorie and macro targets.
///
/// HealthKit itself requires the app to be signed with a paid Apple Developer Program
/// team — a free/personal-team build can't include the entitlement at all. To keep the
/// app buildable and usable either way, every entry point here checks
/// `HKHealthStore.isHealthDataAvailable()` first and simply no-ops (returns nil/0/false)
/// when HealthKit isn't available — whether that's because the device doesn't support it,
/// the build lacks the entitlement, or the user denied access. Callers should already have
/// a non-HealthKit fallback (see `PedometerService`) and just prefer this data when present.
@Observable
final class HealthKitService {
    static let shared = HealthKitService()
    private init() {}

    private let store = HKHealthStore()

    private(set) var isAuthorized = false
    var todaySteps: Int = 0
    var todayActiveEnergy: Int = 0
    var todayRestingEnergy: Int = 0
    var todayDistanceMeters: Double = 0

    /// Whether HealthKit can be used at all on this build/device — false on a build
    /// signed without the HealthKit entitlement (e.g. a free-team local build) or on
    /// devices that don't support Health data.
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let active = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(active) }
        if let resting = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned) { types.insert(resting) }
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(distance) }
        if let weight = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(weight) }
        if let height = HKObjectType.quantityType(forIdentifier: .height) { types.insert(height) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    private var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        if let weight = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(weight) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    /// Requests read/share access. Safe to call even when HealthKit is unavailable —
    /// it just returns false without prompting.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            isAuthorized = true
            return true
        } catch {
            isAuthorized = false
            return false
        }
    }

    /// Refreshes today's steps, active energy, resting energy, and distance in one pass.
    /// No-ops when HealthKit is unavailable, leaving previously fetched values untouched.
    func refreshToday() async {
        guard isAvailable else { return }
        async let steps = sumToday(.stepCount, unit: .count())
        async let active = sumToday(.activeEnergyBurned, unit: .kilocalorie())
        async let resting = sumToday(.basalEnergyBurned, unit: .kilocalorie())
        async let distance = sumToday(.distanceWalkingRunning, unit: .meter())

        let (stepsValue, activeValue, restingValue, distanceValue) = await (steps, active, resting, distance)
        todaySteps = Int(stepsValue ?? 0)
        todayActiveEnergy = Int(activeValue ?? 0)
        todayRestingEnergy = Int(restingValue ?? 0)
        todayDistanceMeters = distanceValue ?? 0
    }

    /// Most recent body weight sample, in kg. Returns nil if unavailable, unauthorized, or no data exists.
    func latestWeightKg() async -> Double? {
        guard isAvailable, let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return nil }
        guard let sample = await latestSample(for: type) else { return nil }
        return sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    /// Most recent height sample, in cm. Returns nil if unavailable, unauthorized, or no data exists.
    func latestHeightCm() async -> Double? {
        guard isAvailable, let type = HKObjectType.quantityType(forIdentifier: .height) else { return nil }
        guard let sample = await latestSample(for: type) else { return nil }
        return sample.quantity.doubleValue(for: .meterUnit(with: .centi))
    }

    /// Writes a workout back to Health. No-ops silently when HealthKit is unavailable.
    func saveWorkout(type: WorkoutType, start: Date, end: Date, caloriesBurned: Int, distanceMeters: Double) async {
        guard isAvailable else { return }
        let workout = HKWorkout(
            activityType: type.hkActivityType,
            start: start,
            end: end,
            duration: end.timeIntervalSince(start),
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: Double(caloriesBurned)),
            totalDistance: distanceMeters > 0 ? HKQuantity(unit: .meter(), doubleValue: distanceMeters) : nil,
            metadata: nil
        )
        try? await store.save(workout)
    }

    // MARK: - Query helpers

    private func sumToday(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func latestSample(for type: HKQuantityType) async -> HKQuantitySample? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKQuantitySample)
            }
            store.execute(query)
        }
    }
}

private extension WorkoutType {
    var hkActivityType: HKWorkoutActivityType {
        switch self {
        case .running: return .running
        case .walking: return .walking
        case .cycling: return .cycling
        case .swimming: return .swimming
        case .weightLifting: return .traditionalStrengthTraining
        case .hiit: return .highIntensityIntervalTraining
        case .yoga: return .yoga
        case .other: return .other
        }
    }
}
