import Foundation

final class DataStore {
    static let shared = DataStore()
    private init() {}

    private let selectedPackId = DataPackCatalog.selectedPackId()

    private var selectedPack: DataPackOption {
        DataPackCatalog.pack(by: selectedPackId)
            ?? DataPackOption(id: DataPackCatalog.defaultPackId, name: "Sam Yan")
    }

    func load<T: Decodable>(_ name: String, as type: T.Type) -> T {
        let resourceName =
            if let prefix = selectedPack.filePrefix {
                "\(prefix)_\(name)"
            } else {
                name
            }

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json") else {
            fatalError(
                "Missing file \(resourceName).json in app bundle for data pack \(selectedPackId). Check file name & Target Membership."
            )
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            fatalError("Failed to decode \(resourceName).json: \(error)")
        }
    }

    lazy var beacons: BeaconRegistry = {
        let registry = load("beacons", as: BeaconRegistry.self)

        print("Loaded beacons from JSON for data pack \(selectedPackId):")
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
