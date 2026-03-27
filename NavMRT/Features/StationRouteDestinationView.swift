import SwiftUI

struct StationRouteDestinationView: View {
    let route: RoutePair

    var body: some View {
        let normalizedStartId = StationCatalog.canonicalStationId(route.startId)
        let normalizedGoalId = StationCatalog.canonicalStationId(route.goalId)

        let startStation = StationCatalog.station(by: normalizedStartId)
            ?? StationCatalog.stations[0]
        let goalStation = StationCatalog.station(by: normalizedGoalId)
            ?? StationCatalog.stations[1]

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
