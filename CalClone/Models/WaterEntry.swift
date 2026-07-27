import Foundation
import SwiftData

@Model
final class WaterEntry {
    var id: UUID
    var amountOz: Int
    var recordedAt: Date

    init(id: UUID = UUID(), amountOz: Int, recordedAt: Date = Date()) {
        self.id = id
        self.amountOz = amountOz
        self.recordedAt = recordedAt
    }
}
