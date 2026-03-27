import Combine
import CoreBluetooth
import CoreLocation
import Foundation

final class BeaconManager: NSObject, ObservableObject, BeaconSource {
    var isRunning: Bool { startRequested && isRanging }

    private var startRequested = false

    private let mapQueue = DispatchQueue(label: "navmrt.beacon.latestMap")

    @Published var latest: [BeaconReading] = []
    @Published private(set) var statusText: String = "Idle"

    var latestPublisher: AnyPublisher<[BeaconReading], Never> {
        $latest.eraseToAnyPublisher()
    }

    private let locationManager = CLLocationManager()
    private lazy var bluetoothManager = CBCentralManager(
        delegate: self,
        queue: mapQueue
    )
    private var constraints: [CLBeaconIdentityConstraint] = []
    private var isRanging = false
    private var isBluetoothScanning = false
    private var latestMap: [String: BeaconReading] = [:]
    private var registeredBeaconIds: Set<String> = []
    private var includeUnregisteredBeacons = false
    private var loggedUnregisteredBeaconIds: Set<String> = []
    private var unknownManufacturerLogCount = 0
    private var publishTimer: Timer?
    private let publishInterval: TimeInterval = 0.2  // 5 Hz

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func configure(
        beacons registry: BeaconRegistry,
        includeUnregisteredBeacons: Bool = false
    ) {
        self.includeUnregisteredBeacons = includeUnregisteredBeacons
        loggedUnregisteredBeaconIds.removeAll()

        var uniqueUUIDs: [UUID: CLBeaconIdentityConstraint] = [:]
        var nextRegisteredIds = Set<String>()

        for b in registry.beacons {
            guard let uuid = Self.parseUUID(b.uuid) else {
                print("Invalid UUID in beacons.json for id=\(b.id): \(b.uuid)")
                continue
            }

            let canonicalUUID = uuid.uuidString.uppercased()
            let fullId = "\(canonicalUUID):\(b.major):\(b.minor)"
            nextRegisteredIds.insert(fullId)
            uniqueUUIDs[uuid] = CLBeaconIdentityConstraint(uuid: uuid)
        }

        registeredBeaconIds = nextRegisteredIds
        constraints = Array(uniqueUUIDs.values)

        print(
            "BeaconManager.configure: ranging \(constraints.count) UUIDs for \(registeredBeaconIds.count) registered beacons"
        )
        setStatusText(
            "Configured \(constraints.count) UUIDs / \(registeredBeaconIds.count) beacon IDs"
        )
    }

    func start() {
        guard !constraints.isEmpty else {
            print(
                "BeaconManager.start: no constraints (did you call configure?)"
            )
            setStatusText("No beacon constraints configured")
            return
        }

        startRequested = true

        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            setStatusText("Requesting location permission")
            locationManager.requestWhenInUseAuthorization()
            return
        }

        guard status == .authorizedWhenInUse || status == .authorizedAlways
        else {
            print("BeaconManager.start: not authorized (\(status.rawValue))")
            setStatusText("Location permission denied")
            return
        }

        startRangingNow()
    }

    private func startRangingNow() {
        guard startRequested else { return }
        guard !isRanging else { return }
        isRanging = true
        setStatusText("Starting scan")

        mapQueue.async {
            self.latestMap.removeAll()
            self.loggedUnregisteredBeaconIds.removeAll()
            self.unknownManufacturerLogCount = 0
            self.publishLatest([])
        }

        for c in constraints {
            locationManager.startRangingBeacons(satisfying: c)
        }
        startBluetoothScanningIfPossible()

        publishTimer?.invalidate()

        let timer = Timer(
            timeInterval: publishInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }

            self.mapQueue.async { [weak self] in
                guard let self else { return }
                guard self.isRanging else { return }

                let now = Date()
                self.latestMap = self.latestMap.filter {
                    now.timeIntervalSince($0.value.ts) < 2.0
                }

                let snapshot = self.latestMap.values.sorted { $0.id < $1.id }
                guard self.isRanging else { return }
                self.publishLatest(snapshot)
            }
        }

        publishTimer = timer
        RunLoop.main.add(timer, forMode: .common)

    }

    func stop() {
        startRequested = false

        guard isRanging else {
            publishLatest([])
            setStatusText("Stopped")
            return
        }

        isRanging = false

        for c in constraints {
            locationManager.stopRangingBeacons(satisfying: c)
        }
        stopBluetoothScanning()

        publishTimer?.invalidate()
        publishTimer = nil

        mapQueue.async {
            self.latestMap.removeAll()
            self.unknownManufacturerLogCount = 0
            self.publishLatest([])
        }
        setStatusText("Stopped")
    }

}

extension BeaconManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        print("Location auth:", status.rawValue)
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            setStatusText("Location authorized")
        case .denied, .restricted:
            setStatusText("Location permission denied")
        case .notDetermined:
            setStatusText("Waiting for location permission")
        @unknown default:
            setStatusText("Location status unknown")
        }

        guard startRequested else { return }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            startRangingNow()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didRange beacons: [CLBeacon],
        satisfying constraint: CLBeaconIdentityConstraint
    ) {
        print("didRange called, count:", beacons.count)

        let now = Date()

        mapQueue.async { [weak self] in
            guard let self else { return }
            guard self.isRanging else { return }

            for cl in beacons {
                guard cl.rssi != 0 else { continue }

                let reading = BeaconReading(from: cl, ts: now)
                self.ingest(reading)
            }
        }
    }
}

private extension BeaconManager {
    func startBluetoothScanningIfPossible() {
        guard !isBluetoothScanning else { return }

        switch bluetoothManager.state {
        case .poweredOn:
            print("BeaconManager: starting CoreBluetooth scan")
            bluetoothManager.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            isBluetoothScanning = true
            setStatusText("Scanning with CoreLocation + Bluetooth")
        case .unknown, .resetting:
            print("BeaconManager: Bluetooth not ready yet")
            setStatusText("Bluetooth not ready")
        case .unsupported:
            print("BeaconManager: Bluetooth unsupported on this device")
            setStatusText("Bluetooth unsupported")
        case .unauthorized:
            print("BeaconManager: Bluetooth unauthorized")
            setStatusText("Bluetooth permission denied")
        case .poweredOff:
            print("BeaconManager: Bluetooth is powered off")
            setStatusText("Bluetooth is off")
        @unknown default:
            print("BeaconManager: Bluetooth state unknown")
            setStatusText("Bluetooth state unknown")
        }
    }

    func stopBluetoothScanning() {
        guard isBluetoothScanning else { return }
        bluetoothManager.stopScan()
        isBluetoothScanning = false
    }

    func ingest(_ reading: BeaconReading) {
        let isRegistered = registeredBeaconIds.contains(reading.id)
        guard isRegistered || includeUnregisteredBeacons else {
            if loggedUnregisteredBeaconIds.insert(reading.id).inserted {
                print("Ignoring unregistered beacon:", reading.id)
            }
            return
        }

        if isRegistered {
            print("Beacon detected:", reading.id, reading.rssi)
            setStatusText("Detected registered beacon")
        } else if loggedUnregisteredBeaconIds.insert(reading.id).inserted {
            print("Unregistered beacon detected:", reading.id)
            setStatusText("Detected unregistered beacon")
        }

        latestMap[reading.id] = reading
    }

    func setStatusText(_ text: String) {
        if Thread.isMainThread {
            statusText = text
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.statusText = text
            }
        }
    }

    func publishLatest(_ readings: [BeaconReading]) {
        if Thread.isMainThread {
            latest = readings
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.latest = readings
            }
        }
    }

    static func parseUUID(_ rawValue: String) -> UUID? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let uuid = UUID(uuidString: trimmed) {
            return uuid
        }

        let hex = trimmed.replacingOccurrences(of: "-", with: "")
        guard
            hex.count == 32,
            hex.range(of: "^[0-9A-Fa-f]{32}$", options: .regularExpression)
                != nil
        else {
            return nil
        }

        let canonical =
            "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: canonical)
    }

    static func parseKnownBeaconManufacturerData(
        _ data: Data,
        rssi: NSNumber,
        now: Date
    ) -> BeaconReading? {
        let bytes = [UInt8](data)
        // Standard iBeacon layout is:
        // companyId(2) + 0x02 + 0x15 + uuid(16) + major(2) + minor(2) + txPower(1)
        // Some beacon firmwares emit the same layout with a non-Apple company ID,
        // which CoreLocation ignores but we can still decode via CoreBluetooth.
        if
            bytes.count >= 25,
            bytes[2] == 0x02,
            bytes[3] == 0x15
        {
            return beaconReading(
                uuidBytes: Array(bytes[4..<20]),
                majorMSB: bytes[20],
                majorLSB: bytes[21],
                minorMSB: bytes[22],
                minorLSB: bytes[23],
                rssi: rssi.intValue,
                now: now
            )
        }

        // AltBeacon: manufacturer(2) + 0xBEAC(2) + beaconId(20) + txPower + mfgReserved
        if
            bytes.count >= 26,
            bytes[2] == 0xBE,
            bytes[3] == 0xAC
        {
            return beaconReading(
                uuidBytes: Array(bytes[4..<20]),
                majorMSB: bytes[20],
                majorLSB: bytes[21],
                minorMSB: bytes[22],
                minorLSB: bytes[23],
                rssi: rssi.intValue,
                now: now
            )
        }

        return nil
    }

    static func beaconReading(
        uuidBytes: [UInt8],
        majorMSB: UInt8,
        majorLSB: UInt8,
        minorMSB: UInt8,
        minorLSB: UInt8,
        rssi: Int,
        now: Date
    ) -> BeaconReading? {
        guard uuidBytes.count == 16 else { return nil }

        let uuidString = String(
            format: "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5],
            uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9],
            uuidBytes[10], uuidBytes[11], uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        )

        let major = Int(majorMSB) << 8 | Int(majorLSB)
        let minor = Int(minorMSB) << 8 | Int(minorLSB)

        return BeaconReading(
            id: "\(uuidString):\(major):\(minor)",
            rssi: rssi,
            ts: now
        )
    }
}

extension BeaconManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard isRanging else { return }
        if central.state == .poweredOn {
            startBluetoothScanningIfPossible()
        } else {
            stopBluetoothScanning()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isRanging else { return }
        guard RSSI.intValue != 0 else { return }
        guard
            let manufacturerData =
                advertisementData[CBAdvertisementDataManufacturerDataKey]
                as? Data
        else {
            return
        }
        guard
            let reading = Self.parseKnownBeaconManufacturerData(
                manufacturerData,
                rssi: RSSI,
                now: Date()
            )
        else {
            if unknownManufacturerLogCount < 5 {
                unknownManufacturerLogCount += 1
                let prefix = manufacturerData.prefix(8).map {
                    String(format: "%02X", $0)
                }.joined(separator: " ")
                print(
                    "BLE advertisement with manufacturer data did not match iBeacon/AltBeacon. bytes=\(manufacturerData.count) prefix=\(prefix)"
                )
            }
            return
        }

        ingest(reading)
    }
}
