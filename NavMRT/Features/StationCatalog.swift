import Foundation

struct StationOption: Identifiable, Hashable {
    let id: String
    let name: String
    let anchorNodeId: String

    var displayLabel: String {
        "\(id): \(name)"
    }
}

enum StationCatalog {
    static let stations: [StationOption] = [
        StationOption(id: "S01", name: "Sam Yan", anchorNodeId: "N1"),
        StationOption(id: "S02", name: "Si Lom", anchorNodeId: "N2"),
        StationOption(id: "S03", name: "Lumphini", anchorNodeId: "E1"),
    ]

    private static let legacyIdToStationId: [String: String] = [
        "N1": "S01",
        "N2": "S02",
        "E1": "S03",
        "SAMYAN": "S01",
        "SILOM": "S02",
        "LUMPHINI": "S03",
        "MRT_SAMYAN": "S01",
        "MRT_SILOM": "S02",
        "MRT_LUMPHINI": "S03",
    ]

    static func canonicalStationId(_ id: String) -> String {
        legacyIdToStationId[id] ?? id
    }

    static func station(by id: String) -> StationOption? {
        let normalized = canonicalStationId(id)
        return stations.first(where: { $0.id == normalized })
    }

    static func stationName(_ id: String) -> String {
        station(by: id)?.displayLabel ?? id
    }
}
