import SwiftUI

struct NavigationTestView: View {
    @AppStorage("navmrt.dataPack") private var dataPackId: String = DataPackCatalog.defaultPackId
    @State private var selectedDestination: String?
    @State private var destinations: [(id: String, name: String)] = []

    var body: some View {
        GeometryReader { screen in
            VStack(spacing: 0) {
                List {
                    Section("Destination") {
                        if destinations.isEmpty {
                            Text("No destinations available")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(destinations, id: \.id) { dest in
                                Button {
                                    selectedDestination = dest.id
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(dest.name)
                                            Text(dest.id)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selectedDestination == dest.id {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    }
                }

                NavigationLink {
                    NavTestRunView(destinationId: selectedDestination ?? "")
                } label: {
                    Text("Start Navigation")
                        .font(.system(size: 24, weight: .bold))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .background(selectedDestination != nil ? Color.blue : Color.gray)
                        .foregroundStyle(.white)
                }
                .disabled(selectedDestination == nil)
                .frame(height: screen.size.height * 0.1)
            }
        }
        .navigationTitle("Navigation Test")
        .onChange(of: dataPackId) { _, _ in loadDestinations() }
        .onAppear { loadDestinations() }
    }

    private func loadDestinations() {
        let pack = DataPackCatalog.pack(by: dataPackId)
            ?? DataPackOption(id: DataPackCatalog.defaultPackId, name: "Sam Yan")
        let resourceName = if let prefix = pack.filePrefix {
            "\(prefix)_places"
        } else {
            "places"
        }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let places = try? JSONDecoder().decode(PlaceCatalog.self, from: data) else {
            destinations = []
            selectedDestination = nil
            return
        }
        destinations = places
            .filter { $0.value.destAllowed }
            .map { (id: $0.key, name: $0.value.name) }
            .sorted { $0.id < $1.id }
        if let sel = selectedDestination, !destinations.contains(where: { $0.id == sel }) {
            selectedDestination = nil
        }
    }
}
