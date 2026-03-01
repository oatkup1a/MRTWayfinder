import SwiftUI

struct RouteSelectionView: View {
    struct StationOption: Identifiable {
        let id: String
        let name: String
        let anchorNodeId: String
    }

    @StateObject private var store = RouteStore.shared

    @State private var startId: String = ""
    @State private var goalId: String = ""

    private let stations: [StationOption] = [
        StationOption(id: "SAMYAN", name: "Sam Yan", anchorNodeId: "N1"),
        StationOption(id: "SILOM", name: "Si Lom", anchorNodeId: "N2"),
        StationOption(id: "LUMPHINI", name: "Lumphini", anchorNodeId: "E1")
    ]

    private let legacyNodeToStationId: [String: String] = [
        "N1": "SAMYAN",
        "N2": "SILOM",
        "E1": "LUMPHINI"
    ]

    private var currentRoute: RoutePair {
        RoutePair(startId: startId, goalId: goalId)
    }

    private var canStart: Bool {
        !startId.isEmpty && !goalId.isEmpty && startId != goalId
    }

    var body: some View {
        Form {
            if !store.favorites.isEmpty {
                Section("Favorites") {
                    ForEach(store.favorites) { r in
                        NavigationLink {
                            navigatorView(for: r)
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
                            navigatorView(for: r)
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
                        Text(station.name).tag(station.id)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section("To Station") {
                Picker("Destination station", selection: $goalId) {
                    Text("Select destination station").tag("")
                    ForEach(stations) { station in
                        Text(station.name).tag(station.id)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section {
                NavigationLink {
                    navigatorView(for: currentRoute)
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
        .navigationTitle("Route Selection")
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
        legacyNodeToStationId[id] ?? id
    }

    private func station(by id: String) -> StationOption? {
        let normalized = canonicalStationId(id)
        return stations.first(where: { $0.id == normalized })
    }

    private func stationName(_ id: String) -> String {
        station(by: id)?.name ?? id
    }

    private func routeTitle(_ r: RoutePair) -> String {
        "\(stationName(r.startId)) → \(stationName(r.goalId))"
    }

    @ViewBuilder
    private func navigatorView(for route: RoutePair) -> some View {
        let normalizedStartId = canonicalStationId(route.startId)
        let normalizedGoalId = canonicalStationId(route.goalId)

        let startStation = station(by: normalizedStartId) ?? stations[0]
        let goalStation = station(by: normalizedGoalId) ?? stations[1]

        NavigatorView(
            startId: startStation.anchorNodeId,
            goalId: goalStation.anchorNodeId,
            startDisplayName: startStation.name,
            goalDisplayName: goalStation.name,
            routeStartSelectionId: normalizedStartId,
            routeGoalSelectionId: normalizedGoalId
        )
    }
}
