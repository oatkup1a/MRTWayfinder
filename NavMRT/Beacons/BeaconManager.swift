import Combine
import CoreLocation
import Foundation

final class BeaconManager: NSObject, ObservableObject, BeaconSource {
    var isRunning: Bool = false
    
    @Published var latest: [BeaconReading] = []

    var latestPublisher: AnyPublisher<[BeaconReading], Never> {
        $latest.eraseToAnyPublisher()
    }

    private let locationManager = CLLocationManager()
    private var constraints: [CLBeaconIdentityConstraint] = []
    private var isRanging = false
    private var latestMap: [String: BeaconReading] = [:]
    private var publishTimer: Timer?
    private let publishInterval: TimeInterval = 0.2  // 5 Hz

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func configure(beacons registry: BeaconRegistry) {
        constraints = registry.beacons.compactMap { b in
            guard let uuid = UUID(uuidString: b.uuid) else {
                print("Invalid UUID in beacons.json for id=\(b.id): \(b.uuid)")
                return nil
            }
            return CLBeaconIdentityConstraint(
                uuid: uuid,
                major: CLBeaconMajorValue(b.major),
                minor: CLBeaconMinorValue(b.minor)
            )
        }
    }

    func start() {

        guard !constraints.isEmpty else {
            print(
                "BeaconManager.start: no constraints (did you call configure?)"
            )
            return
        }

        guard !isRanging else { return }
        isRanging = true

        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            // ranging will start after authorization callback
            return
        }

        guard status == .authorizedWhenInUse || status == .authorizedAlways
        else {
            print("BeaconManager.start: not authorized (\(status.rawValue))")
            return
        }

        startRangingNow()

        latestMap.removeAll()
        latest = []

        publishTimer?.invalidate()
        publishTimer = Timer.scheduledTimer(
            withTimeInterval: publishInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            let now = Date()

            // optional: remove stale readings
            self.latestMap = self.latestMap.filter {
                now.timeIntervalSince($0.value.ts) < 2.0
            }

            self.latest = Array(self.latestMap.values)
        }
    }

    private func startRangingNow() {
        latestMap.removeAll()
        latest = []

        for c in constraints {
            locationManager.startRangingBeacons(satisfying: c)
        }

        publishTimer?.invalidate()
        publishTimer = Timer.scheduledTimer(
            withTimeInterval: publishInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            let now = Date()
            self.latestMap = self.latestMap.filter {
                now.timeIntervalSince($0.value.ts) < 2.0
            }
            self.latest = self.latestMap.values.sorted { $0.id < $1.id }
        }
    }

    func stop() {
        guard isRanging else { return }
        isRanging = false
        for c in constraints {
            locationManager.stopRangingBeacons(satisfying: c)
        }
        publishTimer?.invalidate()
        publishTimer = nil
        latestMap.removeAll()

        latest = []
    }
}

extension BeaconManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        print("Location auth:", status.rawValue)

        if status == .authorizedWhenInUse || status == .authorizedAlways {
            startRangingNow()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didRange beacons: [CLBeacon],
        satisfying constraint: CLBeaconIdentityConstraint
    ) {
        let now = Date()
        for cl in beacons where cl.rssi != 0 {
            let r = BeaconReading(from: cl)
            latestMap[r.id] = BeaconReading(id: r.id, rssi: r.rssi, ts: now)
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("Beacon ranging error:", error.localizedDescription)
    }
}
