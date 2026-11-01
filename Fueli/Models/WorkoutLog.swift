import Foundation
import SwiftData

enum WorkoutType: String, Codable, CaseIterable, Identifiable {
    case running, walking, cycling, swimming, weightLifting, hiit, yoga, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .weightLifting: return "Weight Lifting"
        case .hiit: return "HIIT"
        case .yoga: return "Yoga"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "figure.outdoor.cycle"
        case .swimming: return "figure.pool.swim"
        case .weightLifting: return "dumbbell.fill"
        case .hiit: return "figure.highintensity.intervaltraining"
        case .yoga: return "figure.yoga"
        case .other: return "bolt.heart.fill"
        }
    }

    /// MET (Metabolic Equivalent of Task) used for calorie estimation.
    var met: Double {
        switch self {
        case .running: return 9.8
        case .walking: return 3.5
        case .cycling: return 7.5
        case .swimming: return 8.0
        case .weightLifting: return 5.0
        case .hiit: return 10.0
        case .yoga: return 2.5
        case .other: return 5.0
        }
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
