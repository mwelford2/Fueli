import Foundation
import CoreMotion

@Observable
final class PedometerService {
    static let shared = PedometerService()
    private init() {}

    private let pedometer = CMPedometer()

    var todaySteps: Int = 0
    var workoutSteps: Int = 0
    var workoutDistanceMeters: Double = 0
    private(set) var isTrackingWorkout = false

    var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    func startDayTracking() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        let start = Calendar.current.startOfDay(for: Date())
        pedometer.startUpdates(from: start) { [weak self] data, error in
            guard let data, error == nil else { return }
            Task { @MainActor [weak self] in
                self?.todaySteps = data.numberOfSteps.intValue
            }
        }
    }

    /// Queries CMPedometer for total steps across the past `days` complete calendar
    /// days and returns the per-day average. Returns nil when the pedometer is
    /// unavailable or the query fails.
    func queryAverageSteps(overPastDays days: Int) async -> Double? {
        guard CMPedometer.isStepCountingAvailable() else { return nil }
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -days, to: end) else { return nil }
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                guard let data, error == nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: Double(data.numberOfSteps.intValue) / Double(days))
            }
        }
    }

    func startWorkoutSession() {
        guard CMPedometer.isStepCountingAvailable(), !isTrackingWorkout else { return }
        // Switch pedometer from day-tracking to workout-session mode.
        pedometer.stopUpdates()
        isTrackingWorkout = true
        workoutSteps = 0
        workoutDistanceMeters = 0
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let data, error == nil else { return }
            Task { @MainActor [weak self] in
                self?.workoutSteps = data.numberOfSteps.intValue
                self?.workoutDistanceMeters = data.distance?.doubleValue ?? 0
            }
        }
    }

    func stopWorkoutSession() -> (steps: Int, distanceMeters: Double) {
        pedometer.stopUpdates()
        isTrackingWorkout = false
        let result = (workoutSteps, workoutDistanceMeters)
        startDayTracking()
        return result
    }

    /// MET-based calorie estimate: MET × weight_kg × duration_hours.
    static func workoutCalories(met: Double, weightKg: Double, durationSeconds: Int) -> Int {
        max(0, Int((met * weightKg * Double(durationSeconds) / 3600.0).rounded()))
    }
}
