import Foundation

struct BeaconStats {
    let id: String
    let rawLatest: Int
    let ema: Double
    let median: Double
    let mean: Double
    let stdDev: Double
    let sampleCount: Int
    let lastSeen: Date
}

final class BeaconSignalBuffer {

    struct Sample {
        let ts: Date
        let rssi: Int
        let ema: Double
    }

    private var samples: [String: [Sample]] = [:]
    private let ema = RSSIEMA(alpha: 0.3)

    private let windowSeconds: TimeInterval
    private let maxSamplesPerBeacon: Int

    init(windowSeconds: TimeInterval = 3.0, maxSamplesPerBeacon: Int = 25) {
        self.windowSeconds = windowSeconds
        self.maxSamplesPerBeacon = maxSamplesPerBeacon
    }

    func ingest(_ readings: [BeaconReading], now: Date = Date()) {
        assert(Thread.isMainThread)
        for r in readings {
            let e = ema.update(id: r.id, rssi: r.rssi)
            samples[r.id, default: []].append(
                Sample(ts: now, rssi: r.rssi, ema: e)
            )
            trim(id: r.id, now: now)
        }
    }

    func pruneStale(now: Date = Date(), staleAfter: TimeInterval = 5.0) {
        assert(Thread.isMainThread)
        samples = samples.filter { (_, arr) in
            guard let last = arr.last?.ts else { return false }
            return now.timeIntervalSince(last) < staleAfter
        }
    }

    func stats(for id: String) -> BeaconStats? {
        guard let arr = samples[id], let last = arr.last else { return nil }
        let values = arr.map { Double($0.rssi) }
        let mean = values.reduce(0.0, +) / Double(values.count)
        let variance: Double
        
        if values.count > 1 {
            let squaredDiffSum = values.reduce(0.0) { $0 + pow($1 - mean, 2) }
            variance = squaredDiffSum / Double(values.count - 1)
        } else {
            variance = 0.0
        }
        
        let std = sqrt(variance)
        let med = median(values)

        return BeaconStats(
            id: id,
            rawLatest: last.rssi,
            ema: last.ema,
            median: med,
            mean: mean,
            stdDev: std,
            sampleCount: arr.count,
            lastSeen: last.ts
        )
    }

    func allStatsSorted(by sort: (BeaconStats, BeaconStats) -> Bool)
        -> [BeaconStats]
    {
        assert(Thread.isMainThread)
        let ids = samples.keys
        let list = ids.compactMap { stats(for: $0) }
        return list.sorted(by: sort)
    }

    /// Use this as KNN input: median RSSI per beacon.
    func medianVector(
        minSamples: Int = 3,
        maxAge: TimeInterval = 1.5,
        now: Date = Date()
    ) -> [String: Double] {
        assert(Thread.isMainThread)
        var out: [String: Double] = [:]
        for (id, arr) in samples {
            guard let last = arr.last else { continue }
            if now.timeIntervalSince(last.ts) > maxAge { continue }
            if arr.count < minSamples { continue }

            let values = arr.map { Double($0.rssi) }
            out[id] = median(values)
        }
        return out
    }

    func sampleHistory(for id: String) -> [Sample] {
        samples[id] ?? []
    }
    
    func reset() {
        assert(Thread.isMainThread)
        samples.removeAll()
        ema.reset()
    }

    // MARK: - Helpers

    private func trim(id: String, now: Date) {
        guard var arr = samples[id] else { return }

        // keep only within time window
        let cutoff = now.addingTimeInterval(-windowSeconds)
        if let firstKeep = arr.firstIndex(where: { $0.ts >= cutoff }) {
            if firstKeep > 0 { arr.removeFirst(firstKeep) }
        } else {
            // all are older
            arr.removeAll()
        }

        // cap count
        if arr.count > maxSamplesPerBeacon {
            arr.removeFirst(arr.count - maxSamplesPerBeacon)
        }

        samples[id] = arr
    }

    private func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return -100 }
        let s = xs.sorted()
        let n = s.count
        if n % 2 == 1 {
            return s[n / 2]
        } else {
            return (s[n / 2 - 1] + s[n / 2]) / 2.0
        }
    }
}

extension BeaconStats {
    var shortId: String {
        let parts = id.split(separator: ":")
        guard parts.count == 3 else { return id }
        let uuid = parts[0].prefix(8)
        return "\(uuid)…:\(parts[1]):\(parts[2])"
    }
}
