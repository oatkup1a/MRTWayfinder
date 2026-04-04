import Combine
import Foundation

final class MockBeaconManager: ObservableObject, BeaconSource {
    @Published var latest: [BeaconReading] = []

    var latestPublisher: AnyPublisher<[BeaconReading], Never> {
        $latest.eraseToAnyPublisher()
    }

    private struct Scenario {
        let nodeIds: [String]
        let secondsPerSegment: Int
        let stationWaitSeconds: Int
    }

    private var timer: Timer?
    private var t: Int = 0
    private(set) var isRunning = false

    // Simulated station movement + in-train wait.
    private var scenario = Scenario(
        nodeIds: ["N1", "N2", "E1"],
        secondsPerSegment: 6,
        stationWaitSeconds: 12
    )

    private var fingerprintByLabel: [String: [String: Int]] = [:]
    
    private func loadFingerprints() {
        let pairs: [(String, [String: Int])] = DataStore.shared.fingerprints.compactMap { fp in
            guard let label = fp.label else { return nil }
            return (label, fp.rssi)
        }
        fingerprintByLabel = Dictionary(uniqueKeysWithValues: pairs)
        print("MockBeaconManager loaded \(fingerprintByLabel.count) fingerprints")
    }
    
    func setFingerprints(_ fingerprints: [Fingerprint]) {
        let pairs: [(String, [String: Int])] = fingerprints.compactMap { fp in
            guard let label = fp.label else { return nil }
            return (label, fp.rssi)
        }
        fingerprintByLabel = Dictionary(uniqueKeysWithValues: pairs)
        print("MockBeaconManager set \(fingerprintByLabel.count) fingerprints from external source")
    }

    func configureJourney(startId: String, goalId: String) {
        // Load fingerprints from DataStore if not already set externally
        if fingerprintByLabel.isEmpty {
            loadFingerprints()
        }
        
        let routeKey = "\(startId)->\(goalId)"
        let path = StationJourneyPlanner.mockedInStationPath(for: routeKey)
        let cleaned = path.filter { fingerprintByLabel[$0] != nil }

        if cleaned.count >= 2 {
            scenario = Scenario(
                nodeIds: cleaned,
                secondsPerSegment: 6,
                stationWaitSeconds: 12
            )
        } else {
            // Fallback: use all available fingerprint labels if route planning fails
            let allLabels = Array(fingerprintByLabel.keys)
            if allLabels.count >= 2 {
                scenario = Scenario(
                    nodeIds: allLabels,
                    secondsPerSegment: 3,
                    stationWaitSeconds: 6
                )
                print("MockBeaconManager: Using fallback path with \(allLabels.count) nodes: \(allLabels)")
            } else {
                scenario = Scenario(
                    nodeIds: ["N1", "N2", "E1"],
                    secondsPerSegment: 6,
                    stationWaitSeconds: 12
                )
                print("MockBeaconManager: Warning - no fingerprints available, using default path")
            }
        }

        t = 0
        print("MockBeaconManager configured route \(routeKey) with path \(scenario.nodeIds)")
    }

    func start() {
        guard !isRunning else {
            print("MockBeaconManager.start: already running")
            return
        }

        print("MockBeaconManager.start")
        
        // Load fingerprints if not already loaded
        if fingerprintByLabel.isEmpty {
            loadFingerprints()
        }
        
        isRunning = true
        t = 0

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        guard isRunning else {
            print("MockBeaconManager.stop: not running")
            return
        }
        print("MockBeaconManager.stop")
        timer?.invalidate()
        timer = nil
        isRunning = false
        latest = []
    }

    private func tick() {
        defer { t += 1 }

        guard scenario.nodeIds.count >= 2 else {
            latest = []
            return
        }

        let segmentCount = scenario.nodeIds.count - 1
        let movingDuration = segmentCount * max(1, scenario.secondsPerSegment)
        let totalCycle = movingDuration + max(0, scenario.stationWaitSeconds)
        let cycleTime = totalCycle > 0 ? t % totalCycle : 0

        let now = Date()

        if cycleTime >= movingDuration {
            // Train-wait phase at destination fingerprint.
            let destinationNode = scenario.nodeIds.last!
            latest = readings(at: destinationNode, progress: 1.0, now: now)
            print("Mock phase train-wait at \(destinationNode)")
            return
        }

        let segmentLength = max(1, scenario.secondsPerSegment)
        let segmentIndex = min(segmentCount - 1, cycleTime / segmentLength)
        let segmentProgress = Double(cycleTime % segmentLength) / Double(segmentLength)

        let fromNode = scenario.nodeIds[segmentIndex]
        let toNode = scenario.nodeIds[segmentIndex + 1]

        latest = blendedReadings(
            fromNode: fromNode,
            toNode: toNode,
            progress: segmentProgress,
            now: now
        )

        let pct = Int(segmentProgress * 100)
        print("Mock moving \(fromNode)->\(toNode) \(pct)%")
    }

    private func readings(at nodeId: String, progress: Double, now: Date) -> [BeaconReading] {
        guard let rssiByBeacon = fingerprintByLabel[nodeId] else { return [] }
        let noise = (t % 3) - 1
        return rssiByBeacon
            .map { (id: $0.key, rssi: $0.value + noise + Int(progress * 0.0)) }
            .sorted { $0.id < $1.id }
            .map { BeaconReading(id: $0.id, rssi: $0.rssi, ts: now) }
    }

    private func blendedReadings(
        fromNode: String,
        toNode: String,
        progress: Double,
        now: Date
    ) -> [BeaconReading] {
        guard
            let fromRSSI = fingerprintByLabel[fromNode],
            let toRSSI = fingerprintByLabel[toNode]
        else {
            return readings(at: fromNode, progress: progress, now: now)
        }

        let beaconIds = Set(fromRSSI.keys).union(toRSSI.keys)
        let clamped = min(max(progress, 0), 1)
        let noise = (t % 3) - 1

        return beaconIds
            .map { id -> BeaconReading in
                let start = Double(fromRSSI[id] ?? -90)
                let end = Double(toRSSI[id] ?? -90)
                let blended = Int((start + (end - start) * clamped).rounded()) + noise
                return BeaconReading(id: id, rssi: blended, ts: now)
            }
            .sorted { $0.id < $1.id }
    }
}
