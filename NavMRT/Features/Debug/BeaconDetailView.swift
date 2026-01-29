import SwiftUI

struct BeaconDetailView: View {
    let beaconId: String
    let samples: [RSSISample]

    private let ts: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var shortId: String {
        let parts = beaconId.split(separator: ":")
        guard parts.count == 3 else { return beaconId }
        return "\(parts[0].prefix(8))…:\(parts[1]):\(parts[2])"
    }

    private var lastSeen: Date? { samples.last?.ts }
    private var latestRaw: Int? { samples.last?.raw }
    private var latestEma: Double? { samples.last?.ema }

    var body: some View {
        List {
            Section("Beacon") {
                Text(shortId).font(.system(.body, design: .monospaced))
                Text(beaconId)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Section("Latest") {
                if let t = lastSeen {
                    Text("Last seen: \(ts.string(from: t))")
                } else {
                    Text("Last seen: —")
                }
                Text("Raw: \(latestRaw.map(String.init) ?? "—")")
                Text(
                    latestEma.map { String(format: "EMA: %.1f", $0) }
                        ?? "EMA: —"
                )
            }

            Section("Recent samples") {
                if samples.isEmpty {
                    Text("No samples yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(samples.reversed()) { s in
                        HStack {
                            Text(ts.string(from: s.ts))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("raw \(s.raw)")
                                .font(.system(.caption, design: .monospaced))
                            Text(String(format: "ema %.1f", s.ema))
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
        }
        .navigationTitle("Beacon Detail")
    }
}
