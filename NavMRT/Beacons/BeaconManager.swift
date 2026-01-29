import Combine
import CoreLocation
import Foundation

final class BeaconManager: NSObject, ObservableObject, BeaconSource {
    var isRunning: Bool { startRequested && isRanging }

    private var startRequested = false

    private let mapQueue = DispatchQueue(label: "navmrt.beacon.latestMap")

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

        startRequested = true

        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            return
        }

        guard status == .authorizedWhenInUse || status == .authorizedAlways
        else {
            print("BeaconManager.start: not authorized (\(status.rawValue))")
            return
        }

        startRangingNow()
    }

    private func startRangingNow() {
        guard startRequested else { return }
        guard !isRanging else { return }
        isRanging = true

        mapQueue.async {
            self.latestMap.removeAll()
            DispatchQueue.main.async { self.latest = [] }
        }

        for c in constraints {
            locationManager.startRangingBeacons(satisfying: c)
        }

        publishTimer?.invalidate()
        publishTimer = Timer.scheduledTimer(
            withTimeInterval: publishInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }

            self.mapQueue.async { [weak self] in
                guard let self else { return }
                guard self.isRanging else { return }  // stop() might have run

                let now = Date()
                self.latestMap = self.latestMap.filter {
                    now.timeIntervalSince($0.value.ts) < 2.0
                }

                let snapshot = self.latestMap.values.sorted { $0.id < $1.id }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard self.isRanging else { return }
                    self.latest = snapshot
                }
            }
        }
    }

    func stop() {
        startRequested = false

        guard isRanging else {
            latest = []
            return
        }

        isRanging = false

        for c in constraints {
            locationManager.stopRangingBeacons(satisfying: c)
        }

        publishTimer?.invalidate()
        publishTimer = nil

        mapQueue.async {
            self.latestMap.removeAll()
            DispatchQueue.main.async { self.latest = [] }
        }
    }

}

extension BeaconManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        print("Location auth:", status.rawValue)

        guard startRequested else { return }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            startRangingNow()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("Beacon ranging error:", error.localizedDescription)
    }

}
