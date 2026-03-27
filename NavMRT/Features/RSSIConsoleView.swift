import Combine
import SwiftUI

struct RSSIConsoleView: View {
    @AppStorage("navmrt.useMockBeacons") private var useMockBeacons: Bool = true

    @StateObject private var mockBM = MockBeaconManager()
    @StateObject private var realBM = BeaconManager()

    // Stable stream for the view (does not change when mode flips)
    @State private var readingsSubject = CurrentValueSubject<
        [BeaconReading], Never
    >([])
    @State private var forwardCancellable: AnyCancellable?

    private var uiPublisher: AnyPublisher<[BeaconReading], Never> {
        readingsSubject
            .map { $0.sorted { $0.id < $1.id } }
            .removeDuplicates(by: { a, b in
                guard a.count == b.count else { return false }
                for i in 0..<a.count {
                    if a[i].id != b[i].id { return false }
                    if a[i].rssi != b[i].rssi { return false }
                }
                return true
            })
            .receive(on: RunLoop.main)
            .throttle(
                for: .milliseconds(200),
                scheduler: RunLoop.main,
                latest: true
            )
            .eraseToAnyPublisher()
    }

    private func attachForwarder() {
        forwardCancellable?.cancel()

        let upstream: AnyPublisher<[BeaconReading], Never> =
            useMockBeacons ? mockBM.latestPublisher : realBM.latestPublisher

        forwardCancellable =
            upstream
            .receive(on: RunLoop.main)
            .sink { readings in
                readingsSubject.send(readings)
            }
    }

    private func startActive() {
        // stop both first (prevents double streams)
        mockBM.stop()
        realBM.stop()

        readingsSubject.send([])
        attachForwarder()

        if useMockBeacons {
            mockBM.start()
        } else {
            realBM.configure(
                beacons: DataStore.shared.beacons,
                includeUnregisteredBeacons: true
            )
            print("Starting REAL beacons with \(DataStore.shared.beacons.beacons.count) constraints")
            realBM.start()
        }
    }

    private func stopActive() {
        mockBM.stop()
        realBM.stop()
        forwardCancellable?.cancel()
        readingsSubject.send([])
    }

    // Buffer + derived UI
    @State private var buffer = BeaconSignalBuffer(
        windowSeconds: 3.0,
        maxSamplesPerBeacon: 25
    )
    @State private var sorted: [BeaconStats] = []
    @State private var bestOverlap: Int = 0
    @State private var readingCount: Int = 0
    @State private var knnFix: PositionFix?
    @State private var trilaterationFix: PositionFix?
    @State private var selectedReferenceLabel: String =
        DataStore.shared.fingerprints.first?.label ?? ""

    private let places = DataStore.shared.places

    @State private var lastOverlapUpdate = Date.distantPast
    private let overlapEvery: TimeInterval = 0.5

    private let ts: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        Form {
            Section("Mode") {
                Toggle(isOn: $useMockBeacons) {
                    Text(useMockBeacons ? "Mock beacons" : "Real beacons")
                }
            }

            Section("Quality") {
                if !useMockBeacons {
                    Text("Scanner: \(realBM.statusText)")
                }
                Text("Readings: \(readingCount)")
                Text("Best overlap with fingerprints: \(bestOverlap)")
                Text(bestOverlap >= 2 ? "Localizable: YES" : "Localizable: NO")
                    .fontWeight(.semibold)
            }

            Section("Localization Test") {
                Picker("Reference point", selection: $selectedReferenceLabel) {
                    ForEach(referenceLabels, id: \.self) { label in
                        Text(referenceDisplayLabel(for: label)).tag(label)
                    }
                }
                .pickerStyle(.navigationLink)

                if let reference = referenceFingerprint {
                    Text(
                        String(
                            format: "Ground truth: (%.1f, %.1f, %@)",
                            reference.loc.x,
                            reference.loc.y,
                            reference.loc.floor
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Text(referenceDisplayLabel(for: selectedReferenceLabel))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                localizationRow(
                    title: "KNN Fingerprinting",
                    fix: knnFix,
                    reference: referenceFingerprint
                )
                localizationRow(
                    title: "Trilateration",
                    fix: trilaterationFix,
                    reference: referenceFingerprint
                )
            }

            Section("Signals") {
                ForEach(sorted, id: \.id) { s in
                    NavigationLink {
                        BeaconDetailView(
                            beaconId: s.id,
                            samples: buffer.sampleHistory(for: s.id).map {
                                RSSISample(
                                    ts: $0.ts,
                                    raw: $0.rssi,
                                    ema: $0.ema
                                )
                            }
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Text(s.shortId)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("raw \(s.rawLatest)")
                                    .font(
                                        .system(.caption, design: .monospaced)
                                    )
                                Text(
                                    String(
                                        format: "med %.1f  σ %.1f",
                                        s.median,
                                        s.stdDev
                                    )
                                )
                                .font(.system(.caption, design: .monospaced))
                                Text(
                                    String(
                                        format: "n %d  ema %.1f",
                                        s.sampleCount,
                                        s.ema
                                    )
                                )
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                Text(ts.string(from: s.lastSeen))
                                    .font(
                                        .system(.caption2, design: .monospaced)
                                    )
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .opacity(
                            Date().timeIntervalSince(s.lastSeen) < 1.5
                                ? 1.0 : 0.5
                        )
                    }
                }
            }
        }
        .navigationTitle("RSSI Debug")
        .onAppear { startActive() }
        .onDisappear { stopActive() }

        .onChange(of: useMockBeacons) { _, _ in
            buffer = BeaconSignalBuffer(
                windowSeconds: 3.0,
                maxSamplesPerBeacon: 25
            )
            sorted.removeAll()
            bestOverlap = 0
            readingCount = 0
            knnFix = nil
            trilaterationFix = nil
            startActive()
        }

        .onReceive(uiPublisher) { readings in
            let now = Date()

            buffer.ingest(readings, now: now)
            buffer.pruneStale(now: now, staleAfter: 5.0)

            // after ingest+prune (not one tick behind)
            readingCount =
                buffer.medianVector(minSamples: 1, maxAge: 5.0, now: now).count
            let localizationVector = buffer.medianVector(
                minSamples: 3,
                maxAge: 1.5,
                now: now
            )
            knnFix = KNNPositioner.estimate(
                current: localizationVector,
                dataset: DataStore.shared.fingerprints,
                k: 3
            )
            trilaterationFix = TrilaterationPositioner.estimate(
                current: localizationVector,
                registry: DataStore.shared.beacons
            )

            // strongest first by median
            sorted = buffer.allStatsSorted { $0.median > $1.median }

            // Overlap at 2 Hz
            if now.timeIntervalSince(lastOverlapUpdate) >= overlapEvery {
                lastOverlapUpdate = now

                let fps = DataStore.shared.fingerprints
                let currentKeys = Set(
                    localizationVector.keys
                )

                bestOverlap =
                    fps.map { fp in
                        Set(fp.rssi.keys).intersection(currentKeys).count
                    }.max() ?? 0
            }
        }
    }

    private var referenceLabels: [String] {
        DataStore.shared.fingerprints.compactMap(\.label)
    }

    private var referenceFingerprint: Fingerprint? {
        DataStore.shared.fingerprints.first {
            $0.label == selectedReferenceLabel
        }
    }

    @ViewBuilder
    private func localizationRow(
        title: String,
        fix: PositionFix?,
        reference: Fingerprint?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)

            if let fix {
                if let z = fix.z {
                    Text(
                        String(
                            format: "(%.1f, %.1f, %.1f, %@)  conf=%.2f  anchors=%d",
                            fix.x,
                            fix.y,
                            z,
                            fix.floor,
                            fix.confidence,
                            fix.overlap
                        )
                    )
                    .font(.system(.footnote, design: .monospaced))
                } else {
                    Text(
                        String(
                            format: "(%.1f, %.1f, %@)  conf=%.2f  anchors=%d",
                            fix.x,
                            fix.y,
                            fix.floor,
                            fix.confidence,
                            fix.overlap
                        )
                    )
                    .font(.system(.footnote, design: .monospaced))
                }

                if let error = localizationError(fix: fix, reference: reference) {
                    Text(String(format: "Error: %.2f m", error))
                        .font(.footnote)
                        .foregroundStyle(error <= 2.0 ? .green : .orange)
                } else {
                    Text("Error: unavailable")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No estimate yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func localizationError(
        fix: PositionFix,
        reference: Fingerprint?
    ) -> Double? {
        guard let reference else { return nil }
        guard fix.floor == reference.loc.floor else { return nil }
        let dx = fix.x - reference.loc.x
        let dy = fix.y - reference.loc.y
        return sqrt(dx * dx + dy * dy)
    }

    private func referenceDisplayLabel(for label: String) -> String {
        if let name = places[label]?.name {
            return name
        }
        return label
    }
}
