import Combine
import Foundation

final class BeaconTxPowerStore: ObservableObject {
    static let shared = BeaconTxPowerStore()

    @Published private(set) var overrides: [String: Int] = [:]

    private let key = "navmrt.txPowerOverrides.v1"

    private init() {
        overrides = load()
    }

    func override(for beaconId: String) -> Int? {
        overrides[beaconId]
    }

    func effectiveTxPower(for beacon: Beacon) -> Int {
        overrides[beacon.compositeId] ?? beacon.txPower
    }

    func save(txPower: Int, for beaconId: String) {
        overrides[beaconId] = txPower
        persist()
    }

    func reset(beaconId: String) {
        overrides.removeValue(forKey: beaconId)
        persist()
    }

    func resetAll() {
        overrides.removeAll()
        persist()
    }

    private func load() -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private func persist() {
        let data = try? JSONEncoder().encode(overrides)
        UserDefaults.standard.set(data, forKey: key)
    }
}
