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
                assert(
                    a[key] != nil && b[key] != nil,
                    "Keys in `common` must exist in both dictionaries"
                )
                let va = a[key]!
                let vb = Double(b[key]!)
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
        // Filter out fingerprints with insufficient overlap (encoded as distance >= 1e9)
        let validScored = scored.filter { $0.d < 1e9 }
            .sorted { $0.d < $1.d }
        guard let first = validScored.first else { return nil }
        let top = Array(validScored.prefix(max(1, k)))

        // Distance-weighted centroid so position can move smoothly even when k > 1.
        // Closer fingerprints contribute more than farther ones.
        let epsilon = 1e-6
        let weighted = top.map { item -> (fp: Fingerprint, weight: Double) in
            let w = 1.0 / (item.d + epsilon)
            return (item.fp, w)
        }
        let weightSum = weighted.reduce(0.0) { $0 + $1.weight }

        let x: Double
        let y: Double
        if weightSum > 0 {
            x = weighted.reduce(0.0) { $0 + $1.fp.loc.x * $1.weight } / weightSum
            y = weighted.reduce(0.0) { $0 + $1.fp.loc.y * $1.weight } / weightSum
        } else {
            // Fallback to simple mean if distances are degenerate.
            let c = Double(top.count)
            x = top.reduce(0.0) { $0 + $1.fp.loc.x } / c
            y = top.reduce(0.0) { $0 + $1.fp.loc.y } / c
        }

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
                // Normal case: compute normalized margin between best and 2nd best.
                margin = max(0.0, min(1.0, (d2 - d1) / d2))
            } else if d1 == 0 && d2 == 0 {
                // Edge case: multiple perfect matches; treat as high confidence.
                margin = 1.0
            } else {
                // Fallback for unexpected non-positive d2 values.
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
