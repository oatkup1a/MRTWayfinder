import Combine
import Foundation
import Observation

@Observable
final class NavigationEngine {
    enum Status: Equatable {
        case idle
        case navigating
        case offRoute
        case rerouting
        case arrived
    }

    struct NavInstruction: Equatable {
        let text: String
        let distanceToNext: Double
    }

    private(set) var status: Status = .idle
    private(set) var currentPosition: PositionFix?
    private(set) var route: [Graph.Node] = []
    private(set) var currentSegmentIndex: Int = 0
    private(set) var instruction: NavInstruction?
    private(set) var distanceToDestination: Double = 0

    private let destinationId: String
    private let beaconDriver: BeaconDriver
    private let graph: Graph
    private let fingerprints: [Fingerprint]
    private let beaconRegistry: BeaconRegistry

    private var cancellable: AnyCancellable?
    private var offRouteStreak: Int = 0

    private let arrivalThreshold: Double = 1.5
    private let offRouteThreshold: Double = 3.0
    private let offRouteConfirmCount: Int = 3

    init(
        destinationId: String,
        beaconDriver: BeaconDriver,
        graph: Graph,
        fingerprints: [Fingerprint],
        beaconRegistry: BeaconRegistry
    ) {
        self.destinationId = destinationId
        self.beaconDriver = beaconDriver
        self.graph = graph
        self.fingerprints = fingerprints
        self.beaconRegistry = beaconRegistry
    }

    func start() {
        status = .navigating
        cancellable = beaconDriver.latestPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] readings in
                self?.processReadings(readings)
            }
        beaconDriver.start()
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
        beaconDriver.stop()
        status = .idle
    }

    // MARK: - Processing Pipeline

    private func processReadings(_ readings: [BeaconReading]) {
        guard status == .navigating || status == .offRoute || status == .rerouting else { return }

        let rssiMap = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, Double($0.rssi)) })
        guard let fix = KNNPositioner.estimate(current: rssiMap, dataset: fingerprints) else { return }
        currentPosition = fix

        if route.isEmpty {
            computeInitialRoute(from: fix)
        }

        guard !route.isEmpty else { return }

        if checkArrival(fix: fix) {
            status = .arrived
            instruction = NavInstruction(text: "You have arrived at your destination.", distanceToNext: 0)
            stop()
            status = .arrived
            return
        }

        advanceSegment(fix: fix)

        if checkOffRoute(fix: fix) {
            offRouteStreak += 1
            if offRouteStreak >= offRouteConfirmCount {
                status = .rerouting
                reroute(from: fix)
                offRouteStreak = 0
                status = .navigating
            } else {
                status = .offRoute
            }
        } else {
            offRouteStreak = 0
            status = .navigating
        }

        updateInstruction(fix: fix)
        updateDistanceToDestination(fix: fix)
    }

    private func computeInitialRoute(from fix: PositionFix) {
        guard let nearest = GraphRouter.nearestNode(toX: fix.x, y: fix.y, floor: fix.floor, in: graph) else { return }
        route = GraphRouter.shortestPath(from: nearest.id, to: destinationId, in: graph)
        currentSegmentIndex = 0
    }

    private func checkArrival(fix: PositionFix) -> Bool {
        guard let dest = route.last else { return false }
        let dx = fix.x - dest.x
        let dy = fix.y - dest.y
        return sqrt(dx * dx + dy * dy) < arrivalThreshold && fix.floor == dest.floor
    }

    private func advanceSegment(fix: PositionFix) {
        while currentSegmentIndex < route.count - 1 {
            let next = route[currentSegmentIndex + 1]
            let dx = fix.x - next.x
            let dy = fix.y - next.y
            let dist = sqrt(dx * dx + dy * dy)
            if dist < arrivalThreshold {
                currentSegmentIndex += 1
            } else {
                break
            }
        }
    }

    private func checkOffRoute(fix: PositionFix) -> Bool {
        guard currentSegmentIndex < route.count - 1 else { return false }
        let a = route[currentSegmentIndex]
        let b = route[currentSegmentIndex + 1]
        let dist = distancePointToSegment(
            px: fix.x, py: fix.y,
            ax: a.x, ay: a.y,
            bx: b.x, by: b.y
        )
        return dist > offRouteThreshold
    }

    private func reroute(from fix: PositionFix) {
        guard let nearest = GraphRouter.nearestNode(toX: fix.x, y: fix.y, floor: fix.floor, in: graph) else { return }
        let newRoute = GraphRouter.shortestPath(from: nearest.id, to: destinationId, in: graph)
        if !newRoute.isEmpty {
            route = newRoute
            currentSegmentIndex = 0
        }
    }

    private func updateInstruction(fix: PositionFix) {
        guard currentSegmentIndex < route.count - 1 else {
            instruction = NavInstruction(text: "Approaching destination.", distanceToNext: 0)
            return
        }

        let current = route[currentSegmentIndex]
        let next = route[currentSegmentIndex + 1]
        let dx = next.x - fix.x
        let dy = next.y - fix.y
        let distToNext = sqrt(dx * dx + dy * dy)

        if currentSegmentIndex + 2 < route.count {
            let afterNext = route[currentSegmentIndex + 2]
            let turnText = describeTurn(from: current, through: next, to: afterNext)
            let metersText = Int(distToNext)
            instruction = NavInstruction(
                text: "Head straight for \(metersText)m, then \(turnText).",
                distanceToNext: distToNext
            )
        } else {
            let metersText = Int(distToNext)
            instruction = NavInstruction(
                text: "Head straight for \(metersText)m to your destination.",
                distanceToNext: distToNext
            )
        }
    }

    private func updateDistanceToDestination(fix: PositionFix) {
        guard !route.isEmpty, currentSegmentIndex < route.count else {
            distanceToDestination = 0
            return
        }
        var total = 0.0
        let currentNode = route[currentSegmentIndex]
        let dxFirst = fix.x - currentNode.x
        let dyFirst = fix.y - currentNode.y

        if currentSegmentIndex < route.count - 1 {
            let nextNode = route[currentSegmentIndex + 1]
            let dxToNext = fix.x - nextNode.x
            let dyToNext = fix.y - nextNode.y
            total += sqrt(dxToNext * dxToNext + dyToNext * dyToNext)
        } else {
            total += sqrt(dxFirst * dxFirst + dyFirst * dyFirst)
        }

        for i in (currentSegmentIndex + 1)..<(route.count - 1) {
            let a = route[i]
            let b = route[i + 1]
            let edgeDx = b.x - a.x
            let edgeDy = b.y - a.y
            total += sqrt(edgeDx * edgeDx + edgeDy * edgeDy)
        }
        distanceToDestination = total
    }

    // MARK: - Geometry Helpers

    private func distancePointToSegment(px: Double, py: Double, ax: Double, ay: Double, bx: Double, by: Double) -> Double {
        let abx = bx - ax
        let aby = by - ay
        let apx = px - ax
        let apy = py - ay
        let ab2 = abx * abx + aby * aby
        guard ab2 > 0 else { return sqrt(apx * apx + apy * apy) }
        let t = max(0, min(1, (apx * abx + apy * aby) / ab2))
        let projX = ax + t * abx
        let projY = ay + t * aby
        let dx = px - projX
        let dy = py - projY
        return sqrt(dx * dx + dy * dy)
    }

    private func describeTurn(from a: Graph.Node, through b: Graph.Node, to c: Graph.Node) -> String {
        let v1x = b.x - a.x
        let v1y = b.y - a.y
        let v2x = c.x - b.x
        let v2y = c.y - b.y

        let dot = v1x * v2x + v1y * v2y
        let mag1 = sqrt(v1x * v1x + v1y * v1y)
        let mag2 = sqrt(v2x * v2x + v2y * v2y)
        guard mag1 > 0, mag2 > 0 else { return "continue straight" }

        let cosAngle = max(-1, min(1, dot / (mag1 * mag2)))
        let angle = acos(cosAngle) * 180.0 / .pi

        if angle < 30 {
            return "continue straight"
        } else if angle > 150 {
            return "make a U-turn"
        } else {
            let cross = v1x * v2y - v1y * v2x
            return cross > 0 ? "turn left" : "turn right"
        }
    }
}
