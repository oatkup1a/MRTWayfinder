import Combine
import SwiftUI

struct FingerprintCollectorView: View {
    @AppStorage("navmrt.useMockBeacons") private var useMockBeacons: Bool = true

    @StateObject private var driver = BeaconDriver(initialMode: .mock)
    @State private var buffer = BeaconSignalBuffer(
        windowSeconds: 3.0,
        maxSamplesPerBeacon: 25
    )

    @State private var selectedNodeId: String =
        DataStore.shared.graph.nodes.first?.id ?? ""
    @State private var latestVector: [String: Double] = [:]
    @State private var snapshots: [CollectedFingerprint] = []

    private let graph = DataStore.shared.graph
    private let places = DataStore.shared.places
    private let beacons = DataStore.shared.beacons

    var body: some View {
        List {
            Section("Capture Point") {
                Picker("Reference point", selection: $selectedNodeId) {
                    ForEach(graph.nodes, id: \.id) { node in
                        Text(nodeDisplayLabel(node.id)).tag(node.id)
                    }
                }
                .pickerStyle(.navigationLink)

                if let node = selectedNode {
                    Text(
                        String(
                            format: "Target location: (%.1f, %.1f, %@)",
                            node.x,
                            node.y,
                            node.floor
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Text("Visible beacons ready for capture: \(latestVector.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Capture fingerprint") {
                    captureFingerprint()
                }
                .disabled(selectedNode == nil || latestVector.count < 3)
            }

            Section("Instructions") {
                Text("Stand still at the chosen point for 15 to 30 seconds before capturing.")
                Text("Hold the phone in the orientation you expect users to carry it.")
                Text("Capture each reference point at least 3 times and keep the best or average set.")
            }

            Section("Current medians") {
                if latestVector.isEmpty {
                    Text("No stable beacon vector yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(latestVector.keys.sorted(), id: \.self) { id in
                        HStack {
                            Text(shortId(id))
                                .font(.system(.footnote, design: .monospaced))
                            Spacer()
                            Text(String(format: "%.1f dBm", latestVector[id] ?? -100))
                                .font(.system(.footnote, design: .monospaced))
                        }
                    }
                }
            }

            Section("Captured fingerprints") {
                if snapshots.isEmpty {
                    Text("No captured fingerprints yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshots) { snapshot in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(nodeDisplayLabel(snapshot.label))
                                .font(.headline)
                            Text(
                                String(
                                    format: "(%.1f, %.1f, %@)  %d beacons",
                                    snapshot.loc.x,
                                    snapshot.loc.y,
                                    snapshot.loc.floor,
                                    snapshot.rssi.count
                                )
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Export") {
                if snapshots.isEmpty {
                    Text("Capture at least one fingerprint to export JSON.")
                        .foregroundStyle(.secondary)
                } else {
                    ShareLink(
                        "Share fingerprints.json",
                        item: exportedJSONString,
                        preview: SharePreview("fingerprints.json")
                    )
                    Text(exportedJSONString)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Fingerprint Collector")
        .onAppear { startActive() }
        .onDisappear {
            driver.stop()
            buffer.reset()
        }
        .onChange(of: useMockBeacons) { _, _ in
            snapshots.removeAll()
            startActive()
        }
        .onReceive(driver.latestPublisher.receive(on: RunLoop.main)) { readings in
            let now = Date()
            buffer.ingest(readings, now: now)
            buffer.pruneStale(now: now, staleAfter: 5.0)
            latestVector = buffer.medianVector(minSamples: 5, maxAge: 2.0, now: now)
        }
    }

    private var selectedNode: Graph.Node? {
        graph.nodes.first(where: { $0.id == selectedNodeId })
    }

    private func startActive() {
        driver.stop()
        buffer = BeaconSignalBuffer(windowSeconds: 3.0, maxSamplesPerBeacon: 25)
        latestVector = [:]
        driver.configureReal(registry: beacons)
        driver.configureMockJourney(
            startId: StationCatalog.stations.first?.id ?? "S01",
            goalId: StationCatalog.stations.last?.id ?? "S03"
        )
        driver.setMode(useMockBeacons ? .mock : .real, startIfRunning: false)
        driver.start()
    }

    private func captureFingerprint() {
        guard let node = selectedNode else { return }
        let rounded = latestVector.mapValues { Int($0.rounded()) }

        let snapshot = CollectedFingerprint(
            label: node.id,
            loc: .init(x: node.x, y: node.y, floor: node.floor),
            rssi: rounded
        )

        snapshots.removeAll { $0.label == snapshot.label }
        snapshots.append(snapshot)
        snapshots.sort { left, right in
            graph.nodes.firstIndex(where: { $0.id == left.label }) ?? 0
                < graph.nodes.firstIndex(where: { $0.id == right.label }) ?? 0
        }
    }

    private func nodeDisplayLabel(_ nodeId: String) -> String {
        places[nodeId]?.name ?? nodeId
    }

    private func shortId(_ id: String) -> String {
        let parts = id.split(separator: ":")
        guard parts.count == 3 else { return id }
        return "\(parts[0].prefix(8))…:\(parts[1]):\(parts[2])"
    }

    private var exportedJSONString: String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshots)
            return String(decoding: data, as: UTF8.self)
        } catch {
            return "[]"
        }
    }
}

private struct CollectedFingerprint: Identifiable, Encodable {
    struct Loc: Encodable {
        let x: Double
        let y: Double
        let floor: String
    }

    var id: String { label }
    let label: String
    let loc: Loc
    let rssi: [String: Int]
}
