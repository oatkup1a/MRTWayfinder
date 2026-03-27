import Foundation

struct PositionFix {
    let x: Double
    let y: Double
    let z: Double?
    let floor: String
    let confidence: Double
    let overlap: Int
    let ts: Date

    init(
        x: Double,
        y: Double,
        z: Double? = nil,
        floor: String,
        confidence: Double,
        overlap: Int,
        ts: Date
    ) {
        self.x = x
        self.y = y
        self.z = z
        self.floor = floor
        self.confidence = confidence
        self.overlap = overlap
        self.ts = ts
    }
}
