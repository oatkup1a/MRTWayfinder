import Foundation

struct TrilaterationPositioner {
    private struct Anchor {
        let x: Double
        let y: Double
        let z: Double
        let distance: Double
        let solveDistance: Double
        let rssi: Double
    }

    private struct Point3D {
        let x: Double
        let y: Double
        let z: Double
    }

    static func estimate(
        current: [String: Double],
        registry: BeaconRegistry,
        pathLossExponent: Double = 2.0
    ) -> PositionFix? {
        guard pathLossExponent > 0 else { return nil }
        let receiverHeight = TrilaterationSettings.receiverHeightMeters()

        let beaconById = Dictionary(
            uniqueKeysWithValues: registry.beacons.map {
                (
                    "\($0.uuid.uppercased()):\($0.major):\($0.minor)",
                    $0
                )
            }
        )

        var strongestFloor = "G"
        var strongestRSSI = -Double.greatestFiniteMagnitude

        let anchors = current.compactMap { id, rssi -> Anchor? in
            guard let beacon = beaconById[id] else { return nil }
            if rssi > strongestRSSI {
                strongestRSSI = rssi
                strongestFloor = beacon.floor
            }
            let txPower = BeaconTxPowerStore.shared.effectiveTxPower(for: beacon)
            guard txPower != 0 else { return nil }

            let measuredDistance = rssiToDistance(
                rssi: rssi,
                txPower: Double(txPower),
                pathLossExponent: pathLossExponent
            )
            guard measuredDistance.isFinite, measuredDistance > 0 else { return nil }

            let beaconZ = beacon.z ?? 0.0

            return Anchor(
                x: beacon.x,
                y: beacon.y,
                z: beaconZ,
                distance: measuredDistance,
                solveDistance: correctedPlanarDistance(
                    from: measuredDistance,
                    beaconZ: beaconZ,
                    receiverZ: receiverHeight
                ),
                rssi: rssi
            )
        }
        .sorted { $0.rssi > $1.rssi }

        guard anchors.count >= 3 else { return nil }
        let selected = Array(anchors.prefix(min(6, anchors.count)))
        let point =
            solve3D(using: selected)
            ?? solve2D(using: selected, receiverHeight: receiverHeight)
        guard let point else { return nil }

        let meanResidual =
            selected.reduce(0.0) { partial, anchor in
                let estimated = hypot3D(
                    point.x - anchor.x,
                    point.y - anchor.y,
                    point.z - anchor.z
                )
                return partial + abs(estimated - anchor.distance)
            } / Double(selected.count)

        let confidence = max(0.0, min(1.0, 1.0 - (meanResidual / 8.0)))

        return PositionFix(
            x: point.x,
            y: point.y,
            z: point.z,
            floor: strongestFloor,
            confidence: confidence,
            overlap: selected.count,
            ts: Date()
        )
    }

    private static func solve2D(
        using anchors: [Anchor],
        receiverHeight: Double
    ) -> Point3D? {
        guard anchors.count >= 3 else { return nil }
        let reference = anchors[0]

        var ata11 = 0.0
        var ata12 = 0.0
        var ata22 = 0.0
        var atb1 = 0.0
        var atb2 = 0.0

        for anchor in anchors.dropFirst() {
            let a1 = 2.0 * (anchor.x - reference.x)
            let a2 = 2.0 * (anchor.y - reference.y)
            let b =
                reference.solveDistance * reference.solveDistance
                - anchor.solveDistance * anchor.solveDistance
                - reference.x * reference.x
                + anchor.x * anchor.x
                - reference.y * reference.y
                + anchor.y * anchor.y

            let weight = 1.0 / max(anchor.solveDistance, 0.5)

            ata11 += weight * a1 * a1
            ata12 += weight * a1 * a2
            ata22 += weight * a2 * a2
            atb1 += weight * a1 * b
            atb2 += weight * a2 * b
        }

        let det = ata11 * ata22 - ata12 * ata12
        guard abs(det) > 1e-6 else { return nil }

        let x = (atb1 * ata22 - ata12 * atb2) / det
        let y = (ata11 * atb2 - atb1 * ata12) / det
        return Point3D(x: x, y: y, z: receiverHeight)
    }

    private static func solve3D(using anchors: [Anchor]) -> Point3D? {
        guard anchors.count >= 4 else { return nil }
        let reference = anchors[0]

        var ata = Array(
            repeating: Array(repeating: 0.0, count: 3),
            count: 3
        )
        var atb = Array(repeating: 0.0, count: 3)

        for anchor in anchors.dropFirst() {
            let row = [
                2.0 * (anchor.x - reference.x),
                2.0 * (anchor.y - reference.y),
                2.0 * (anchor.z - reference.z),
            ]
            let b =
                reference.distance * reference.distance
                - anchor.distance * anchor.distance
                - reference.x * reference.x
                + anchor.x * anchor.x
                - reference.y * reference.y
                + anchor.y * anchor.y
                - reference.z * reference.z
                + anchor.z * anchor.z

            let weight = 1.0 / max(anchor.distance, 0.5)

            for i in 0..<3 {
                for j in 0..<3 {
                    ata[i][j] += weight * row[i] * row[j]
                }
                atb[i] += weight * row[i] * b
            }
        }

        guard let solution = solveLinearSystem3x3(ata, atb) else { return nil }
        return Point3D(x: solution[0], y: solution[1], z: solution[2])
    }

    private static func rssiToDistance(
        rssi: Double,
        txPower: Double,
        pathLossExponent: Double
    ) -> Double {
        let ratio = (txPower - rssi) / (10.0 * pathLossExponent)
        return pow(10.0, ratio)
    }

    private static func correctedPlanarDistance(
        from measuredDistance: Double,
        beaconZ: Double,
        receiverZ: Double
    ) -> Double {
        let verticalOffset = receiverZ - beaconZ
        let horizontalSquared =
            measuredDistance * measuredDistance
            - verticalOffset * verticalOffset
        return sqrt(max(horizontalSquared, 0.01))
    }

    private static func hypot3D(_ dx: Double, _ dy: Double, _ dz: Double) -> Double {
        sqrt(dx * dx + dy * dy + dz * dz)
    }

    private static func solveLinearSystem3x3(
        _ a: [[Double]],
        _ b: [Double]
    ) -> [Double]? {
        guard a.count == 3, b.count == 3 else { return nil }
        var augmented = [
            [a[0][0], a[0][1], a[0][2], b[0]],
            [a[1][0], a[1][1], a[1][2], b[1]],
            [a[2][0], a[2][1], a[2][2], b[2]],
        ]

        for pivot in 0..<3 {
            var bestRow = pivot
            var bestValue = abs(augmented[pivot][pivot])

            for row in (pivot + 1)..<3 {
                let value = abs(augmented[row][pivot])
                if value > bestValue {
                    bestValue = value
                    bestRow = row
                }
            }

            guard bestValue > 1e-6 else { return nil }
            if bestRow != pivot {
                augmented.swapAt(bestRow, pivot)
            }

            let pivotValue = augmented[pivot][pivot]
            for column in pivot..<4 {
                augmented[pivot][column] /= pivotValue
            }

            for row in 0..<3 where row != pivot {
                let factor = augmented[row][pivot]
                if abs(factor) <= 1e-9 { continue }
                for column in pivot..<4 {
                    augmented[row][column] -= factor * augmented[pivot][column]
                }
            }
        }

        return [augmented[0][3], augmented[1][3], augmented[2][3]]
    }
}
