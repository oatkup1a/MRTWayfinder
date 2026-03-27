import SwiftUI

struct RouteSelectionView: View {
    @StateObject private var store = RouteStore.shared

    @State private var startId: String = ""
    @State private var goalId: String = ""

    private var currentRoute: RoutePair {
        RoutePair(startId: startId, goalId: goalId)
    }

    private var canStart: Bool {
        !startId.isEmpty && !goalId.isEmpty && startId != goalId
    }

    private let stations = StationCatalog.stations

    var body: some View {
        Form {
            if !store.favorites.isEmpty {
                Section("Favorites") {
                    ForEach(store.favorites) { r in
                        NavigationLink {
                            StationRouteDestinationView(route: r)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routeTitle(r))
                                Text("Station to station route")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !store.recents.isEmpty {
                Section {
                    ForEach(store.recents) { r in
                        NavigationLink {
                            StationRouteDestinationView(route: r)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routeTitle(r))
                                Text("Station to station route")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button(role: .destructive) {
                        store.clearRecents()
                    } label: {
                        Text("Clear recents")
                    }
                } header: {
                    Text("Recent")
                }
            }

            Section("From Station") {
                Picker("Start station", selection: $startId) {
                    Text("Select start station").tag("")
                    ForEach(stations) { station in
                        Text(station.displayLabel).tag(station.id)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section("To Station") {
                Picker("Destination station", selection: $goalId) {
                    Text("Select destination station").tag("")
                    ForEach(stations) { station in
                        Text(station.displayLabel).tag(station.id)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section {
                NavigationLink {
                    StationRouteDestinationView(route: currentRoute)
                } label: {
                    Text("Start guided navigation")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(!canStart)

                Button {
                    guard canStart else { return }
                    store.toggleFavorite(currentRoute)
                } label: {
                    Text(store.isFavorite(currentRoute) ? "Remove from favorites" : "Add to favorites")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(!canStart)
            }
        }
        .navigationTitle("Manual Selection")
        .onAppear {
            if startId.isEmpty { startId = stations.first?.id ?? "" }
            if goalId.isEmpty { goalId = stations.dropFirst().first?.id ?? "" }

            if startId == goalId,
               let alt = stations.first(where: { $0.id != startId }) {
                goalId = alt.id
            }
        }
        .onChange(of: startId) { _, newValue in
            if newValue == goalId,
               let alt = stations.first(where: { $0.id != newValue }) {
                goalId = alt.id
            }
        }
        .onChange(of: goalId) { _, newValue in
            if newValue == startId,
               let alt = stations.first(where: { $0.id != newValue }) {
                startId = alt.id
            }
        }
    }

    private func canonicalStationId(_ id: String) -> String {
        StationCatalog.canonicalStationId(id)
    }

    private func station(by id: String) -> StationOption? {
        StationCatalog.station(by: canonicalStationId(id))
    }

    private func stationName(_ id: String) -> String {
        station(by: id)?.displayLabel ?? id
    }

    private func routeTitle(_ r: RoutePair) -> String {
        "\(stationName(r.startId)) → \(stationName(r.goalId))"
    }
}
