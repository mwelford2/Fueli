import Foundation
import HealthKit

/// HealthKit read access is private: a completed permission request does not prove
/// access was granted. No readable samples is represented as nil, not zero.
@MainActor
@Observable
final class HealthKitService {
    static let shared = HealthKitService()
    init(store: HKHealthStore = HKHealthStore()) { self.store = store }

    private let store: HKHealthStore
    private(set) var historySummary = "No readable completed-day energy history has been checked yet."

    private(set) var isAuthorized = false
    var todaySteps: Int = 0
    var todayActiveEnergy: Int = 0
    var todayRestingEnergy: Int = 0
    var todayDistanceMeters: Double = 0

    /// Hardware support only; this does not check provisioning entitlements or read permission.
    var isAvailable: Bool {
        #if HEALTHKIT_DISABLED
        return false
        #else
        return HKHealthStore.isHealthDataAvailable()
        #endif
    }

    nonisolated static func isEmptyHealthResult(_ error: Swift.Error) -> Bool {
        let error = error as NSError
        return error.domain == HKErrorDomain && error.code == HKError.Code.errorNoData.rawValue
    }
    var hasRequestedActiveEnergy: Bool {
        UserDefaults.standard.bool(forKey: "healthKitActiveEnergyRequested")
    }

    /// Requests only the data used by the dashboard. No write permission is needed.
    func connectActiveEnergy() async throws {
        guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthActivityError.unavailable
        }
        try await store.requestAuthorization(toShare: [], read: [type])
        UserDefaults.standard.set(true, forKey: "healthKitActiveEnergyRequested")
    }

    struct EnergySource: Identifiable, Equatable {
        let id: String
        let name: String
        var hasActiveEnergy: Bool
        var hasRestingEnergy: Bool

        var dataDescription: String {
            switch (hasActiveEnergy, hasRestingEnergy) {
            case (true, true): return "Active + resting energy observed"
            case (true, false): return "Active energy only observed"
            case (false, true): return "Resting energy only observed"
            default: return "No energy data observed"
            }
        }
    }

    static func mergeEnergySources(active: [EnergySource], resting: [EnergySource]) -> [EnergySource] {
        var sources: [String: EnergySource] = [:]
        for entry in active + resting {
            if var existing = sources[entry.id] {
                existing.hasActiveEnergy = existing.hasActiveEnergy || entry.hasActiveEnergy
                existing.hasRestingEnergy = existing.hasRestingEnergy || entry.hasRestingEnergy
                sources[entry.id] = existing
            } else { sources[entry.id] = entry }
        }
        return sources.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Observed readable data is not a claim that an account is currently connected.
    func recentEnergySources(now: Date = Date()) async throws -> [EnergySource] {
        guard isAvailable else { throw HealthActivityError.unavailable }
        let start = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        @Sendable func sources(for identifier: HKQuantityTypeIdentifier) async throws -> [EnergySource] {
            try await withCheckedThrowingContinuation { continuation in
                let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
                let query = HKSourceQuery(sampleType: HKQuantityType(identifier), samplePredicate: predicate) { _, sources, error in
                    if let error, !Self.isEmptyHealthResult(error) { continuation.resume(throwing: error); return }
                    continuation.resume(returning: (sources ?? []).map {
                        EnergySource(id: $0.bundleIdentifier, name: $0.name,
                            hasActiveEnergy: identifier == .activeEnergyBurned,
                            hasRestingEnergy: identifier == .basalEnergyBurned)
                    })
                }
                store.execute(query)
            }
        }
        async let active = sources(for: .activeEnergyBurned)
        async let resting = sources(for: .basalEnergyBurned)
        return try await Self.mergeEnergySources(active: active, resting: resting)
    }

    struct DailyEnergy {
        let date: Date
        let active: Double?
        let resting: Double?
        let restingCoverage: Double
    }
    struct EnergyAverage {
        let calories: Double
        let days: Int
        let start: Date
        let end: Date
    }

    /// Engineering quality gate, not a clinically validated wearable accuracy threshold.
    static func averageTotalEnergy(_ days: [DailyEnergy], before end: Date) -> EnergyAverage? {
        let valid = days.filter {
            guard $0.date < end, let active = $0.active, let resting = $0.resting else { return false }
            return active.isFinite && active >= 0 && resting.isFinite && resting > 0 &&
                $0.restingCoverage.isFinite
        }
        guard valid.count >= 7, let first = valid.map(\.date).min() else { return nil }
        let average = valid.reduce(0) { $0 + $1.active! + $1.resting! } / Double(valid.count)
        guard average.isFinite else { return nil }
        return EnergyAverage(calories: average, days: valid.count, start: first, end: end)
    }

    /// Merge overlaps so multiple devices cannot inflate apparent wear-time coverage.
    static func coverage(_ intervals: [DateInterval], in day: DateInterval) -> Double {
        let clipped = intervals.compactMap { interval -> DateInterval? in
            let start = max(interval.start, day.start), end = min(interval.end, day.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        var covered = 0.0
        var previousEnd = day.start
        for interval in clipped {
            covered += max(0, interval.end.timeIntervalSince(max(previousEnd, interval.start)))
            previousEnd = max(previousEnd, interval.end)
        }
        return day.duration > 0 ? min(1, covered / day.duration) : 0
    }

    func connectTotalEnergy() async throws {
        guard isAvailable else { throw HealthActivityError.unavailable }
        let types: Set<HKObjectType> = [HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned)]
        try await store.requestAuthorization(toShare: [], read: types)
        UserDefaults.standard.set(true, forKey: "healthKitTotalEnergyRequested")
        UserDefaults.standard.set(true, forKey: "healthKitActiveEnergyRequested")
    }

    /// Last 14 complete local-calendar days, never today's incomplete total.
    func averageTotalEnergy(now: Date = Date()) async throws -> EnergyAverage? {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -14, to: end) else { return nil }
        async let active = dailyEnergy(.activeEnergyBurned, start: start, end: end)
        async let resting = dailyEnergy(.basalEnergyBurned, start: start, end: end)
        let basal = HKQuantityType(.basalEnergyBurned)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let intervals: [DateInterval] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: basal, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error, !Self.isEmptyHealthResult(error) { continuation.resume(throwing: error); return }
                continuation.resume(returning: (samples ?? []).map { DateInterval(start: $0.startDate, end: $0.endDate) })
            }
            store.execute(query)
        }
        let (activeDays, restingDays) = try await (active, resting)
        let days: [DailyEnergy] = (0..<14).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start),
                  let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            return DailyEnergy(date: date, active: activeDays[date], resting: restingDays[date],
                restingCoverage: Self.coverage(intervals, in: DateInterval(start: date, end: next)))
        }
        let activeCount = days.filter { $0.active != nil }.count
        let restingCount = days.filter { $0.resting != nil }.count
        let pairedCount = days.filter { $0.active != nil && ($0.resting ?? 0) > 0 }.count
        historySummary = "Last 14 completed days: \(activeCount) with active energy, \(restingCount) with resting energy, \(pairedCount) with both. At least 7 paired days are needed for the average. Check Fueli's read permissions for BOTH types in Apple Health."
        return Self.averageTotalEnergy(days, before: end)
    }

    private func dailyEnergy(_ identifier: HKQuantityTypeIdentifier, start: Date, end: Date) async throws -> [Date: Double] {
        guard isAvailable else { throw HealthActivityError.unavailable }
        let type = HKQuantityType(identifier)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error, !Self.isEmptyHealthResult(error) { continuation.resume(throwing: error); return }
                var values: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end.addingTimeInterval(-0.001)) { statistics, _ in
                    if let quantity = statistics.sumQuantity() { values[statistics.startDate] = quantity.doubleValue(for: .kilocalorie()) }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    static func dayInterval(containing date: Date, now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        let start = calendar.startOfDay(for: date)
        guard start <= now, let next = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: min(next, now))
    }

    /// Query HealthKit statistics rather than summing workouts or individual sources.
    /// Active energy excludes resting energy and can already include workouts.
    func activeEnergy(on date: Date) async throws -> Double? {
        guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthActivityError.unavailable
        }
        guard let interval = Self.dayInterval(containing: date), interval.duration > 0 else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error, !Self.isEmptyHealthResult(error) { continuation.resume(throwing: error); return }
                let value = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie())
                continuation.resume(returning: value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
            }
            store.execute(query)
        }
    }

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

private enum HealthActivityError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Apple Health is unavailable in this build or on this device. Free/personal-team builds cannot read Health data; install a build signed with HealthKit enabled. Your configured calorie target is still available." }
}
