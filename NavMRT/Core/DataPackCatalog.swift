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
        DataPackOption(id: "silom", name: "Si Lom"),
        DataPackOption(id: "lumphini", name: "Lumphini"),
    ]

    static func pack(by id: String) -> DataPackOption? {
        packs.first(where: { $0.id == id })
    }

    static func selectedPackId() -> String {
        let stored = UserDefaults.standard.string(forKey: storageKey)
        return pack(by: stored ?? "")?.id ?? defaultPackId
    }
}
