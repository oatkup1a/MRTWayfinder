import Foundation

struct DataPackOption: Identifiable, Hashable {
    let id: String
    let name: String

    var filePrefix: String? {
        id == "samyan" ? nil : id
    }
}

enum DataPackCatalog {
    static let defaultPackId = "samyan"
    static let storageKey = "navmrt.dataPack"

    static let packs: [DataPackOption] = [
        DataPackOption(id: "samyan", name: "Sam Yan"),
        DataPackOption(id: "house_test", name: "House Test"),
        DataPackOption(id: "square_room", name: "Square Room (3m)"),
        DataPackOption(id: "poc_test", name: "POC Navigation Test"),
        DataPackOption(id: "silom", name: "Si Lom"),
        DataPackOption(id: "lumphini", name: "Lumphini"),
        DataPackOption(id: "S1_straight", name: "Section 1-Straight"),
        DataPackOption(id: "S2_turn", name: "Section 2-Turn"),
        DataPackOption(id: "S3_zigzag", name: "Section 3-Zigzag"),
        DataPackOption(id: "S4_floorchange", name: "Section 4-Floor Change"),
    ]

    static func pack(by id: String) -> DataPackOption? {
        packs.first(where: { $0.id == id })
    }

    static func selectedPackId() -> String {
        let stored = UserDefaults.standard.string(forKey: storageKey)
        return pack(by: stored ?? "")?.id ?? defaultPackId
    }
}
