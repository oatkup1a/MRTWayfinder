import CoreLocation
import Foundation

struct BeaconReading: Identifiable {
    let id: String
    let rssi: Int
    let ts: Date

    var identifierShort: String {
        let parts = id.split(separator: ":")
        guard parts.count == 3 else { return id }
        let uuid = parts[0].prefix(8)
        return "\(uuid)...\(parts[1]):\(parts[2])"
    }
}

extension BeaconReading {
    init(from cl: CLBeacon, ts: Date) {
        let uuid = cl.uuid.uuidString.uppercased()
        let id = "\(uuid):\(cl.major.intValue):\(cl.minor.intValue)"
        self.id = id
        self.rssi = cl.rssi
        self.ts = ts
    }
}
