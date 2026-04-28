import Combine
import SwiftUI

struct TxPowerCalibrationView: View {
    @StateObject private var driver = BeaconDriver(initialMode: .real)
    @ObservedObject private var txPowerStore = BeaconTxPowerStore.shared

    @State private var buffer = BeaconSignalBuffer(
        windowSeconds: 3.0,
        maxSamplesPerBeacon: 25
    )
    @State private var statsById: [String: BeaconStats] = [:]
    @State private var selectedBeaconId: String =
        DataStore.shared.beacons.beacons.first?.compositeId ?? ""
    @State private var calibrationBeaconId: String?
    @State private var calibrationStart: Date?
    @State private var calibrationSamples: [Int] = []
    @State private var captureNow = Date()
    @State private var statusMessage = "Place the phone exactly 1 meter from one beacon, then start a capture."

    private let registry = DataStore.shared.beacons
    private let captureDuration: TimeInterval = 20.0
    private let captureTimer = Timer.publish(every: 0.25, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        List {
            Section("Instructions") {
                Text("This tool measures RSSI at 1 meter and saves the median as a runtime txPower override.")
                Text("Power on only the beacon you are calibrating. Keep the phone still for 20 seconds.")
                Text("Overrides are saved locally and used by trilateration immediately.")
            }

            Section("Beacon") {
                Picker("Target beacon", selection: $selectedBeaconId) {
                    ForEach(registry.beacons, id: \.compositeId) { beacon in
                        Text(beaconDisplayLabel(beacon)).tag(beacon.compositeId)
                    }
                }
                .pickerStyle(.navigationLink)
                .disabled(isCapturing)

                if let beacon = selectedBeacon {
                    Text("Default txPower: \(beacon.txPower) dBm")
                        .foregroundStyle(.secondary)
                    Text("Effective txPower: \(txPowerStore.effectiveTxPower(for: beacon)) dBm")
                        .foregroundStyle(.secondary)

                    if let stats = statsById[beacon.compositeId] {
                        Text(
                            String(
                                format: "Live median: %.1f dBm  n=%d  sigma=%.1f",
                                stats.median,
                                stats.sampleCount,
                                stats.stdDev
                            )
                        )
                        .font(.system(.footnote, design: .monospaced))
                    } else {
                        Text("No live signal yet for this beacon.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Capture") {
                if isCapturing {
                    ProgressView(value: captureProgress)
                    Text(captureTitle)
                    Text("Collected samples: \(calibrationSamples.count)")
                        .foregroundStyle(.secondary)

                    Button("Cancel Capture", role: .cancel) {
                        cancelCapture()
                    }
                } else {
                    Button("Start 20s Calibration") {
                        startCapture()
                    }
                    .disabled(!canStartCapture)

                    Button("Save Current Median") {
                        saveCurrentMedian()
                    }
                    .disabled(!canSaveCurrentMedian)

                    Button("Reset Selected Override", role: .destructive) {
                        resetSelectedOverride()
                    }
                    .disabled(!hasSelectedOverride)
                }

                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Saved Overrides") {
                if registry.beacons.allSatisfy({ txPowerStore.override(for: $0.compositeId) == nil }) {
                    Text("No txPower overrides saved yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(registry.beacons, id: \.compositeId) { beacon in
                        if let override = txPowerStore.override(for: beacon.compositeId) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(beaconDisplayLabel(beacon))
                                    Text("Default \(beacon.txPower) dBm -> Override \(override) dBm")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Reset") {
                                    txPowerStore.reset(beaconId: beacon.compositeId)
                                    if selectedBeaconId == beacon.compositeId {
                                        statusMessage = "Reset override for \(beacon.id)."
                                    }
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    Button("Reset All Overrides", role: .destructive) {
                        txPowerStore.resetAll()
                        statusMessage = "Removed all saved txPower overrides."
                    }
                }
            }
        }
        .navigationTitle("TxPower Calibration")
        .onAppear { startScanning() }
        .onDisappear {
            driver.stop()
            buffer.reset()
            cancelCapture()
        }
        .onReceive(driver.latestPublisher.receive(on: RunLoop.main)) { readings in
            let now = Date()
            buffer.ingest(readings, now: now)
            buffer.pruneStale(now: now, staleAfter: 5.0)
            refreshStats()
            collectCalibrationSamples(from: readings)
        }
        .onReceive(captureTimer) { now in
            captureNow = now
            guard let start = calibrationStart else { return }
            if now.timeIntervalSince(start) >= captureDuration {
                finishCapture()
            }
        }
    }

    private var selectedBeacon: Beacon? {
        registry.beacons.first { $0.compositeId == selectedBeaconId }
    }

    private var isCapturing: Bool {
        calibrationStart != nil
    }

    private var canStartCapture: Bool {
        selectedBeacon != nil && statsById[selectedBeaconId] != nil
    }

    private var canSaveCurrentMedian: Bool {
        statsById[selectedBeaconId]?.sampleCount ?? 0 >= 5
    }

    private var hasSelectedOverride: Bool {
        txPowerStore.override(for: selectedBeaconId) != nil
    }

    private var captureProgress: Double {
        guard let start = calibrationStart else { return 0 }
        return min(captureNow.timeIntervalSince(start) / captureDuration, 1.0)
    }

    private var captureTitle: String {
        guard let beacon = registry.beacons.first(where: { $0.compositeId == calibrationBeaconId }) else {
            return "Capturing RSSI samples..."
        }
        return "Capturing \(beacon.id) at 1 meter..."
    }

    private func startScanning() {
        driver.stop()
        buffer = BeaconSignalBuffer(windowSeconds: 3.0, maxSamplesPerBeacon: 25)
        statsById = [:]
        driver.configureReal(registry: registry)
        driver.setMode(.real, startIfRunning: false)
        driver.start()
    }

    private func refreshStats() {
        var next: [String: BeaconStats] = [:]
        for beacon in registry.beacons {
            if let stats = buffer.stats(for: beacon.compositeId) {
                next[beacon.compositeId] = stats
            }
        }
        statsById = next
    }

    private func startCapture() {
        guard canStartCapture else { return }
        calibrationBeaconId = selectedBeaconId
        calibrationStart = Date()
        captureNow = Date()
        calibrationSamples = []

        if let beacon = selectedBeacon {
            statusMessage = "Capturing \(beacon.id). Keep only this beacon powered and hold the phone still."
        }
    }

    private func collectCalibrationSamples(from readings: [BeaconReading]) {
        guard let targetId = calibrationBeaconId else { return }
        let matches = readings.filter { $0.id == targetId }.map(\.rssi)
        if !matches.isEmpty {
            calibrationSamples.append(contentsOf: matches)
        }
    }

    private func finishCapture() {
        guard let targetId = calibrationBeaconId else { return }
        defer { cancelCapture() }

        guard !calibrationSamples.isEmpty else {
            statusMessage = "Capture finished with no samples. Move closer, check beacon power, and try again."
            return
        }

        let median = median(calibrationSamples.map(Double.init))
        let txPower = Int(median.rounded())
        txPowerStore.save(txPower: txPower, for: targetId)

        if let beacon = registry.beacons.first(where: { $0.compositeId == targetId }) {
            statusMessage = "Saved \(txPower) dBm for \(beacon.id) from \(calibrationSamples.count) samples."
        } else {
            statusMessage = "Saved \(txPower) dBm from \(calibrationSamples.count) samples."
        }
    }

    private func cancelCapture() {
        calibrationBeaconId = nil
        calibrationStart = nil
        calibrationSamples = []
    }

    private func saveCurrentMedian() {
        guard let beacon = selectedBeacon, let stats = statsById[beacon.compositeId] else { return }
        let txPower = Int(stats.median.rounded())
        txPowerStore.save(txPower: txPower, for: beacon.compositeId)
        statusMessage = "Saved current median \(txPower) dBm for \(beacon.id)."
    }

    private func resetSelectedOverride() {
        guard let beacon = selectedBeacon else { return }
        txPowerStore.reset(beaconId: beacon.compositeId)
        statusMessage = "Reset override for \(beacon.id)."
    }

    private func beaconDisplayLabel(_ beacon: Beacon) -> String {
        if let area = beacon.area, !area.isEmpty {
            return "\(beacon.id) - \(area) (\(beacon.floor))"
        }
        return beacon.id
    }

    private func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return -100 }
        let sorted = xs.sorted()
        let count = sorted.count
        if count.isMultiple(of: 2) {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        }
        return sorted[count / 2]
    }
}
