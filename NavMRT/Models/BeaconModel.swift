import Foundation
struct BeaconRegistry: Decodable {
  let station: String
  let floor: String
  let beacons: [Beacon]
}
struct Beacon: Decodable, Hashable {
  let id: String
  let uuid: String
  let major: Int
  let minor: Int
  let txPower: Int
  let x: Double
  let y: Double
  let z: Double?
  let area: String?
}

extension Beacon {
  var compositeId: String {
    "\(uuid.uppercased()):\(major):\(minor)"
  }
}
