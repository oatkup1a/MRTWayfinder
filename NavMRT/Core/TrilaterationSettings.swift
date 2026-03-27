import Foundation

enum TrilaterationSettings {
    private static let receiverHeightKey = "navmrt.receiverHeightMeters"

    static func receiverHeightMeters() -> Double {
        let stored = UserDefaults.standard.object(forKey: receiverHeightKey) as? Double
        return stored ?? 1.0
    }
}
