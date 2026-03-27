import Foundation

struct GraphRouter {

    static func buildAdjacency(from graph: Graph) -> [String: [(neighbor: String, cost: Double)]] {
        var adj: [String: [(String, Double)]] = [:]

        for edge in graph.edges {
            adj[edge.from, default: []].append((edge.to, edge.len))
            adj[edge.to, default: []].append((edge.from, edge.len)) // undirected
        }

        return adj
    }

    static func shortestPath(
        from startId: String,
        to goalId: String,
        in graph: Graph
    ) -> [Graph.Node] {
        let adj = buildAdjacency(from: graph)

        var dist: [String: Double] = [:]
        var prev: [String: String] = [:]
        var unvisited = Set(graph.nodes.map { $0.id })

        for node in unvisited {
            dist[node] = Double.greatestFiniteMagnitude
        }
        dist[startId] = 0

        func nearestUnvisited() -> String? {
            unvisited.min { (a, b) in
                (dist[a] ?? .greatestFiniteMagnitude) <
                (dist[b] ?? .greatestFiniteMagnitude)
            }
        }

        while let current = nearestUnvisited() {
            unvisited.remove(current)
            if current == goalId { break }

            guard let neighbors = adj[current] else { continue }

            let currentDist = dist[current] ?? .greatestFiniteMagnitude

            for (n, cost) in neighbors {
                let alt = currentDist + cost
                if alt < (dist[n] ?? .greatestFiniteMagnitude) {
                    dist[n] = alt
                    prev[n] = current
                }
            }
        }

        // Reconstruct path
        guard dist[goalId] != nil, dist[goalId] != .greatestFiniteMagnitude else {
            return []
        }

        var pathIds: [String] = []
        var u: String? = goalId

        while let nodeId = u {
            pathIds.append(nodeId)
            u = prev[nodeId]
        }

        pathIds.reverse()

        // Map IDs back to nodes
        let nodeMap = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        return pathIds.compactMap { nodeMap[$0] }
    }

    static func nearestNode(
        toX x: Double,
        y: Double,
        floor: String,
        in graph: Graph
    ) -> Graph.Node? {
        var best: Graph.Node?
        var bestDist = Double.greatestFiniteMagnitude

        for node in graph.nodes where node.floor == floor {
            let dx = node.x - x
            let dy = node.y - y
            let d2 = dx*dx + dy*dy
            if d2 < bestDist {
                bestDist = d2
                best = node
            }
        }
        return best
    }
}


struct StationJourneyPlan {
    let startStation: String
    let destinationStation: String
    let platformSide: String
    let boardingHint: String
    let stopCount: Int
    let destinationExitGate: String

    var steps: [String] {
        let stopPluralSuffix = stopCount == 1 ? "" : "s"
        return [
            "Start at the entrance of \(startStation).",
            "Go to the \(platformSide) platform side and use \(boardingHint).",
            "Board the train heading toward \(destinationStation).",
            "Stay on the train for \(stopCount) stop\(stopPluralSuffix).",
            "You have reached \(destinationStation). Exit the train.",
            "Follow signs to \(destinationExitGate) and go up to the station exit."
        ]
    }
}

struct StationJourneyPlanner {
    struct MockStationGuide {
        let preferredPlatformSide: String
        let boardingHint: String
        let exitGate: String
    }

    struct MockRouteGuide {
        let stopCount: Int
        let inStationPath: [String]
    }

    // Temporary mocked station metadata (by node id).
    private static let mockStationGuideById: [String: MockStationGuide] = [
        "N1": MockStationGuide(
            preferredPlatformSide: "left",
            boardingHint: "the left-side escalator",
            exitGate: "Exit Gate 1"
        ),
        "N2": MockStationGuide(
            preferredPlatformSide: "right",
            boardingHint: "the right-side escalator",
            exitGate: "Exit Gate 2"
        ),
        "E1": MockStationGuide(
            preferredPlatformSide: "left",
            boardingHint: "the center escalator",
            exitGate: "Exit Gate 3"
        )
    ]

    // Temporary mocked station metadata (by display name).
    private static let mockStationGuideByName: [String: MockStationGuide] = [
        "Sam Yan": MockStationGuide(
            preferredPlatformSide: "left",
            boardingHint: "the left-side escalator",
            exitGate: "Exit Gate 1"
        ),
        "Si Lom": MockStationGuide(
            preferredPlatformSide: "right",
            boardingHint: "the right-side escalator",
            exitGate: "Exit Gate 2"
        ),
        "Lumphini": MockStationGuide(
            preferredPlatformSide: "left",
            boardingHint: "the center escalator",
            exitGate: "Exit Gate 3"
        )
    ]

    // Temporary mocked route metadata (by startId->goalId).
    private static let mockRouteGuide: [String: MockRouteGuide] = [
        "N1->N2": MockRouteGuide(stopCount: 1, inStationPath: ["N1", "N2"]),
        "N1->E1": MockRouteGuide(stopCount: 2, inStationPath: ["N1", "N2", "E1"]),
        "N2->E1": MockRouteGuide(stopCount: 1, inStationPath: ["N2", "E1"])
    ]

    static func buildPlan(
        startId: String,
        startName: String,
        destinationId: String,
        destinationName: String
    ) -> StationJourneyPlan {
        let startGuide = mockGuide(forId: startId, name: startName)
        let destinationGuide = mockGuide(forId: destinationId, name: destinationName)

        let defaultPlatformSide = fallbackPlatformSide(from: startName, to: destinationName)
        let defaultBoardingHint = "the \(defaultPlatformSide)-side escalator"
        let defaultExitGate = "Exit Gate \(fallbackGateNumber(for: destinationId + destinationName))"

        return StationJourneyPlan(
            startStation: startName,
            destinationStation: destinationName,
            platformSide: startGuide?.preferredPlatformSide ?? defaultPlatformSide,
            boardingHint: startGuide?.boardingHint ?? defaultBoardingHint,
            stopCount: mockedStopCount(startId: startId, destinationId: destinationId),
            destinationExitGate: destinationGuide?.exitGate ?? defaultExitGate
        )
    }

    private static func mockGuide(forId id: String, name: String) -> MockStationGuide? {
        mockStationGuideById[id] ?? mockStationGuideByName[name]
    }

    static func mockedInStationPath(for routeKey: String) -> [String] {
        mockRoute(for: routeKey)?.inStationPath ?? ["N1", "N2", "E1"]
    }

    static func mockedDetailedJourneySteps(startName: String, destinationName: String) -> [String] {
        [
            "Start at the entrance of \(startName).",
            "Walk straight to the ticket gate, then keep to the tactile path and turn right.",
            "Go down the correct escalator to the platform level.",
            "Move to the correct side of the platform and face train direction for \(destinationName).",
            "Board the train when doors open.",
            "Stay on board and wait until the train reaches \(destinationName).",
            "Arrived at \(destinationName). Leave the train.",
            "Follow the signs to the exit, go up the escalator, and continue to the gate.",
            "You are now at the destination exit. Navigation complete."
        ]
    }

    private static func mockedStopCount(startId: String, destinationId: String) -> Int {
        if let guide = mockRoute(for: "\(startId)->\(destinationId)") {
            return guide.stopCount
        }
        let checksum = stableChecksum("\(startId)->\(destinationId)")
        return max(1, (checksum % 6) + 1)
    }

    private static func mockRoute(for routeKey: String) -> MockRouteGuide? {
        if let guide = mockRouteGuide[routeKey] {
            return guide
        }

        let parts = routeKey.split(separator: "->", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        let reverseKey = "\(parts[1])->\(parts[0])"
        guard let reverseGuide = mockRouteGuide[reverseKey] else { return nil }

        return MockRouteGuide(
            stopCount: reverseGuide.stopCount,
            inStationPath: Array(reverseGuide.inStationPath.reversed())
        )
    }

    private static func fallbackPlatformSide(from start: String, to destination: String) -> String {
        start.localizedCompare(destination) == .orderedAscending ? "left" : "right"
    }

    private static func fallbackGateNumber(for stationKey: String) -> Int {
        (stableChecksum(stationKey) % 4) + 1
    }

    private static func stableChecksum(_ text: String) -> Int {
        text.unicodeScalars.reduce(0) { partial, scalar in
            (partial * 31 + Int(scalar.value)) % 10_000
        }
    }
}
