import Foundation

final class DataStore {
    static let shared = DataStore()
    private init() {}

    func load<T: Decodable>(_ name: String, as type: T.Type) -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            fatalError("Missing file \(name).json in app bundle. Check file name & Target Membership.")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            fatalError("Failed to decode \(name).json: \(error)")
        }
    }

    lazy var beacons: BeaconRegistry = {
        let registry = load("beacons", as: BeaconRegistry.self)

        print("Loaded beacons from JSON:")
        for b in registry.beacons {
            print("\(b.uuid):\(b.major):\(b.minor)")
        }

        return registry
    }()

    lazy var fingerprints: [Fingerprint] = load("fingerprints", as: [Fingerprint].self)
    lazy var graph: Graph = load("graph", as: Graph.self)
    lazy var places: PlaceCatalog = load("places", as: PlaceCatalog.self)
}

extension Graph {
    func edgeBetween(_ a: String, _ b: String) -> Edge? {
        edges.first {
            ($0.from == a && $0.to == b) ||
            ($0.from == b && $0.to == a)
        }
    }
}
