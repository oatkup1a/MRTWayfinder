import Combine
import SwiftUI

struct RSSIConsoleView: View {
    @AppStorage("navmrt.useMockBeacons") private var useMockBeacons: Bool = true

    @StateObject private var mockBM = MockBeaconManager()
    @StateObject private var realBM = BeaconManager()

    private var activePublisher: AnyPublisher<[BeaconReading], Never> {
        useMockBeacons ? mockBM.latestPublisher : realBM.latestPublisher
    }

    private var uiPublisher: AnyPublisher<[BeaconReading], Never> {
        activePublisher
            .map { $0.sorted { $0.id < $1.id } }
            .removeDuplicates(by: { a, b in
                guard a.count == b.count else { return false }
                for i in 0..<a.count {
                    if a[i].id != b[i].id { return false }
                    if a[i].rssi != b[i].rssi { return false }
                }
                return true
            })
            .throttle(
                for: .milliseconds(200),
                scheduler: RunLoop.main,
                latest: true
            )
            .eraseToAnyPublisher()
    }

    private func startActive() {
        mockBM.stop()
        realBM.stop()

        if useMockBeacons {
            mockBM.start()
        } else {
            realBM.configure(beacons: DataStore.shared.beacons)
            realBM.start()
        }
    }

    private func stopActive() {
        mockBM.stop()
        realBM.stop()
    }

    // NEW
    @State private var buffer = BeaconSignalBuffer(
        windowSeconds: 3.0,
        maxSamplesPerBeacon: 25
    )
    @State private var sorted: [BeaconStats] = []

    @State private var bestOverlap: Int = 0
    @State private var readingCount: Int = 0

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
                Text("Readings: \(readingCount)")
                Text("Best overlap with fingerprints: \(bestOverlap)")
                Text(bestOverlap >= 2 ? "Localizable: YES" : "Localizable: NO")
                    .fontWeight(.semibold)
            }

            Section("Signals") {
                ForEach(sorted, id: \.id) { s in
                    NavigationLink {
                        // adapt to your existing BeaconDetailView
                        // Convert buffer samples to your RSSISample if needed
                        BeaconDetailView(
                            beaconId: s.id,
                            samples: buffer.sampleHistory(for: s.id).map {
                                RSSISample(ts: $0.ts, raw: $0.rssi, ema: $0.ema)
                            }
                        )
                    } label: {
                        HStack(spacing: 12) {
                            Text(
                                BeaconReading(
                                    id: s.id,
                                    rssi: s.rawLatest,
                                    ts: s.lastSeen
                                ).identifierShort
                            )
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
            startActive()
        }

        .onReceive(uiPublisher) { readings in
            let now = Date()
            buffer.ingest(readings, now: now)
            buffer.pruneStale(now: now, staleAfter: 5.0)
            readingCount =
                buffer.medianVector(minSamples: 1, maxAge: 5.0, now: now).count

            // strongest first by median (or ema)
            sorted = buffer.allStatsSorted { $0.median > $1.median }

            // Overlap at 2 Hz
            if now.timeIntervalSince(lastOverlapUpdate) >= overlapEvery {
                lastOverlapUpdate = now

                let fps = DataStore.shared.fingerprints
                let currentKeys = Set(
                    buffer.medianVector(minSamples: 3, maxAge: 1.5, now: now)
                        .keys
                )

                bestOverlap =
                    fps.map { fp in
                        Set(fp.rssi.keys).intersection(currentKeys).count
                    }.max() ?? 0
            }
        }
    }
}
