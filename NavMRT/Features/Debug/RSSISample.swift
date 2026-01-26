import Foundation

struct RSSISample: Identifiable {
    let id = UUID()
    let ts: Date
    let raw: Int
    let ema: Double
}
