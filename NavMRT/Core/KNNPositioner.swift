import Foundation

struct KNNPositioner {
    static func estimate(
        current: [String: Double],
        dataset: [Fingerprint],
        k: Int = 3
    )
        -> PositionFix?

    {
        guard !dataset.isEmpty else { return nil }

        func dist(_ a: [String: Double], _ b: [String: Int]) -> (
            d: Double, overlap: Int
        ) {
            let common = Set(a.keys).intersection(b.keys)
            let overlap = common.count
            guard overlap >= 2 else { return (1e9, overlap) }  // require overlap
            let d = common.reduce(0.0) { s, key in
                let va = a[key] ?? -100
                let vb = Double(b[key] ?? -100)
                let diff = va - vb
                return s + diff * diff
            }
            return (d, overlap)
        }

        let scored = dataset.map {
            fp -> (fp: Fingerprint, d: Double, overlap: Int) in
            let r = dist(current, fp.rssi)
            return (fp, r.d, r.overlap)
        }
        .sorted { $0.d < $1.d }

        guard let first = scored.first, first.d < 1e9 else { return nil }

        let top = Array(scored.prefix(max(1, k)))

        let c = Double(top.count)
        let x = top.reduce(0.0) { $0 + $1.fp.loc.x } / c
        let y = top.reduce(0.0) { $0 + $1.fp.loc.y } / c

        let floor =
            Dictionary(grouping: top, by: { $0.fp.loc.floor })
            .max(by: { $0.value.count < $1.value.count })?.key
            ?? first.fp.loc.floor

        // Confidence: distance margin between best and 2nd best (0..1-ish, higher is better).
        // If only one match is available, we cannot compute a margin, so confidence is 0.
        let margin: Double
        if top.count < 2 {
            margin = 0.0
        } else {
            let d1 = top[0].d
            let d2 = top[1].d
            if d2 > 0 {
                margin = max(0.0, min(1.0, (d2 - d1) / d2))
            } else {
                margin = 0.0
            }
        }
        // Also return overlap of best match
        let overlap = top.first?.overlap ?? 0

        return PositionFix(
            x: x,
            y: y,
            floor: floor,
            confidence: margin,
            overlap: overlap,
            ts: Date()
        )
    }
}
