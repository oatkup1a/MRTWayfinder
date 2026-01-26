import Foundation

struct RSSIDebugRow: Identifiable {
    let id: String  // beacon id "uuid:major:minor"
    let raw: Int
    let ema: Double
    let lastSeen: Date

    var shortId: String {
        let parts = id.split(separator: ":")
        guard parts.count == 3 else { return id }
        let uuid8 = parts[0].prefix(8)
        return "\(uuid8)…:\(parts[1]):\(parts[2])"
    }
}
