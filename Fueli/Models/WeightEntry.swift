import Foundation
import SwiftData

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
