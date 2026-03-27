import SwiftUI
import Combine

struct AutoDetectRouteView: View {
    @AppStorage("navmrt.useMockBeacons") private var useMockBeacons: Bool = true

    @StateObject private var driver = BeaconDriver(initialMode: .mock)
    @State private var buffer = BeaconSignalBuffer(
        windowSeconds: 3.0,
        maxSamplesPerBeacon: 25
    )

    @State private var detectedStationId: String?
    @State private var candidateStationId: String?
    @State private var candidateStationStreak = 0
    @State private var goalId: String = ""
    @State private var detectionMessage = "Scanning nearby beacons..."
    @State private var visibleBeaconCount = 0

    private let confirmationThreshold = 3

    private let fps = DataStore.shared.fingerprints
    private let graph = DataStore.shared.graph
    private let registry = DataStore.shared.beacons

    private var availableDestinations: [StationOption] {
        StationCatalog.stations.filter { $0.id != detectedStationId }
    }

    private var currentRoute: RoutePair? {
        guard
            let detectedStationId,
            !goalId.isEmpty,
            detectedStationId != goalId
        else {
            return nil
        }

        return RoutePair(startId: detectedStationId, goalId: goalId)
    }

    var body: some View {
        Form {
            Section("Current station") {
                if let detectedStationId,
                    let station = StationCatalog.station(by: detectedStationId)
                {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(station.displayLabel)
                            .font(.headline)
                        Text(detectionMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView()
                        Text(detectionMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Visible beacons: \(visibleBeaconCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Scan again") {
                    startDetection()
                }
            }

            Section("Destination") {
                Picker("Destination station", selection: $goalId) {
                    Text("Select destination").tag("")
                    ForEach(availableDestinations) { station in
                        Text(station.displayLabel).tag(station.id)
                    }
                }
                .pickerStyle(.navigationLink)
                .disabled(detectedStationId == nil)
            }

            Section {
                if let currentRoute {
                    NavigationLink {
                        StationRouteDestinationView(route: currentRoute)
                    } label: {
                        Text("Start guided navigation")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } else {
                    Text("Wait for station detection, then choose a destination.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Auto Detect")
        .onAppear {
            startDetection()
        }
        .onDisappear {
            driver.stop()
            buffer.reset()
        }
        .onChange(of: useMockBeacons) { _, _ in
            startDetection()
        }
        .onChange(of: detectedStationId) { _, newValue in
            guard let newValue else { return }
            if goalId.isEmpty || goalId == newValue {
                goalId = availableDestinations.first?.id ?? ""
            }
        }
        .onReceive(driver.latestPublisher.receive(on: RunLoop.main)) {
            readings in
            handleReadings(readings)
        }
    }

    private func startDetection() {
        driver.stop()
        buffer = BeaconSignalBuffer(windowSeconds: 3.0, maxSamplesPerBeacon: 25)
        detectedStationId = nil
        candidateStationId = nil
        candidateStationStreak = 0
        visibleBeaconCount = 0
        detectionMessage =
            useMockBeacons
            ? "Scanning simulated beacons for your current station..."
            : "Scanning nearby beacons for your current station..."

        let mockStart = StationCatalog.stations.first?.id ?? "S01"
        let mockGoal = StationCatalog.stations.last?.id ?? "S03"

        driver.configureReal(registry: DataStore.shared.beacons)
        driver.configureMockJourney(startId: mockStart, goalId: mockGoal)
        driver.setMode(useMockBeacons ? .mock : .real, startIfRunning: false)
        driver.start()
    }

    private func handleReadings(_ readings: [BeaconReading]) {
        let now = Date()
        buffer.ingest(readings, now: now)
        buffer.pruneStale(now: now, staleAfter: 5.0)

        let vec = buffer.medianVector(minSamples: 3, maxAge: 1.5, now: now)
        visibleBeaconCount = vec.count

        guard !vec.isEmpty else {
            detectionMessage =
                if let detectedStationId,
                    let station = StationCatalog.station(by: detectedStationId)
                {
                    "Signal dropped. Keeping \(station.displayLabel) as the last known station."
                } else if useMockBeacons {
                    "Listening to the simulated beacon route..."
                } else {
                    "Listening for station beacons..."
                }
            return
        }

        guard
            let estimate = KNNPositioner.estimate(
                current: vec,
                dataset: fps,
                k: 3
            ),
            estimate.overlap >= 2
        else {
            detectionMessage =
                detectedStationId == nil
                ? "Signal is present, but the station is not stable yet."
                : "Holding the last detected station until the signal becomes stable again."
            return
        }

        guard let detectedStation = detectedStation(for: estimate) else {
            detectionMessage = "A location was estimated, but no station matched it."
            return
        }

        updateDetectedStation(using: detectedStation)
    }

    private func detectedStation(for estimate: PositionFix) -> StationOption? {
        if let station = StationCatalog.station(by: registry.station) {
            return station
        }

        return nearestStation(to: estimate)
    }

    private func nearestStation(to estimate: PositionFix) -> StationOption? {
        StationCatalog.stations
            .compactMap { station -> (station: StationOption, distance: Double)? in
                guard let node = graph.nodes.first(where: {
                    $0.id == station.anchorNodeId && $0.floor == estimate.floor
                }) ?? graph.nodes.first(where: { $0.id == station.anchorNodeId })
                else {
                    return nil
                }

                let dx = node.x - estimate.x
                let dy = node.y - estimate.y
                return (station, sqrt(dx * dx + dy * dy))
            }
            .min(by: { $0.distance < $1.distance })?
            .station
    }

    private func updateDetectedStation(using nearestStation: StationOption) {
        if candidateStationId == nearestStation.id {
            candidateStationStreak += 1
        } else {
            candidateStationId = nearestStation.id
            candidateStationStreak = 1
        }

        if candidateStationStreak >= confirmationThreshold {
            detectedStationId = nearestStation.id
            detectionMessage =
                "Detected \(nearestStation.displayLabel). Choose a destination to continue."
        } else {
            detectionMessage =
                "Verifying \(nearestStation.displayLabel)... (\(candidateStationStreak)/\(confirmationThreshold))"
        }
    }
}
