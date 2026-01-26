import SwiftUI

struct NavigatorView: View {
    let startId: String
    let goalId: String

    let places = DataStore.shared.places
    let routeStore = RouteStore.shared

    @AppStorage("navmrt.useMockBeacons") private var useMockBeacons: Bool = true
    @AppStorage("navmrt.autostart") private var autoStartNav: Bool = true
    @State private var isRunning = false

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @AccessibilityFocusState private var focusInstruction: Bool

    // Signal quality / position lost
    let minBeaconsForFix = 2
    let maxSecondsWithoutFix: TimeInterval = 3
    let minConfidenceForGuidance: Double = 0.15
    let minOverlapForGuidance: Int = 2

    @State private var lastGoodFixAt: Date = .distantPast
    @State private var positionLost = false

    // Routing state
    @State private var path: [Graph.Node] = []
    @State private var currentSegmentIndex: Int = 0

    // Off-route config
    let offRouteThresholdMeters: Double = 3.0  // how far from path counts as off-route
    let offRouteConfirmCount: Int = 3  // consecutive updates required
    let offRouteAnnounceCooldown: TimeInterval = 8  // seconds between warnings
    let autoRerouteEnabled: Bool = true

    @State private var offRouteStreak: Int = 0
    @State private var lastOffRouteAnnounce = Date.distantPast

    @State private var expectedFloor: String? = nil
    @State private var lastFloorAnnounce = Date.distantPast
    let floorAnnounceCooldown: TimeInterval = 6

    // Formatting
    private let tsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    // Data / engines
    @State private var buffer = BeaconSignalBuffer(
        windowSeconds: 3.0,
        maxSamplesPerBeacon: 25
    )

    @StateObject private var driver = BeaconDriver(initialMode: .mock)

    let speech = Speech()
    let fps = DataStore.shared.fingerprints
    let graph = DataStore.shared.graph

    // Thresholds / flags
    let arrivalThreshold: Double = 1.5
    @State private var posText = "—"  // dev detail
    @State private var instructionText = "Press Start to begin navigation"  // user text
    @State private var lastAnnounce = Date.distantPast
    @State private var arrived = false

    private func nextNode() -> Graph.Node? {
        let idx = currentSegmentIndex
        guard idx >= 0 && idx < path.count else { return nil }
        return path[idx]
    }

    var body: some View {

        VStack(spacing: 32) {

            // Main instruction (for the passenger)
            Text(instructionText)
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .accessibilityFocused($focusInstruction)
                .accessibilityAddTraits(.isHeader)

            // Secondary debug info – can be hidden later if you want
            Text("Debug: \(posText)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .accessibilityHidden(true)

            Spacer(minLength: 16)

            // Big controls
            VStack(spacing: 16) {
                Button {
                    driver.start()
                    buffer = BeaconSignalBuffer(
                        windowSeconds: 3.0,
                        maxSamplesPerBeacon: 25
                    )
                    isRunning = true
                    speak("Navigation started")
                    instructionText =
                        "Navigation started. Follow the audio instructions."
                } label: {
                    Text("Start navigation")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .disabled(isRunning)
                .accessibilityLabel("Start navigation")
                .accessibilityHint(
                    "Begins guided navigation using audio instructions"
                )

                Button {
                    driver.stop()
                    buffer = BeaconSignalBuffer(
                        windowSeconds: 3.0,
                        maxSamplesPerBeacon: 25
                    )
                    isRunning = false
                    speak("Navigation stopped")
                    instructionText = "Navigation stopped."
                } label: {
                    Text("Stop")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .disabled(!isRunning)
                .accessibilityLabel("Stop navigation")
                .accessibilityHint("Stops navigation and beacon scanning")

                Button {
                    speak(instructionText)
                } label: {
                    Text("Repeat last instruction")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .accessibilityLabel("Repeat instruction")
                .accessibilityHint(
                    "Repeats the last spoken navigation instruction"
                )
            }
            Toggle(isOn: $useMockBeacons) {
                Text(
                    useMockBeacons
                        ? "Using Mock Beacons"
                        : "Using Real Beacons"
                )
            }
            .padding(.top, 8)
            .accessibilityHidden(true)
            .onChange(of: useMockBeacons) { _, newValue in
                let wasRunning = isRunning
                driver.setMode(newValue ? .mock : .real, startIfRunning: wasRunning)
                buffer = BeaconSignalBuffer(windowSeconds: 3.0, maxSamplesPerBeacon: 25)
            }

            Spacer()
        }
        .padding()
        .onAppear {

            driver.configureReal(registry: DataStore.shared.beacons)
            driver.setMode(
                useMockBeacons ? .mock : .real,
                startIfRunning: false
            )

            let p = GraphRouter.shortestPath(
                from: startId,
                to: goalId,
                in: graph
            )
            path = p
            currentSegmentIndex = 0

            if !p.isEmpty {
                routeStore.recordRecent(
                    RoutePair(startId: startId, goalId: goalId)
                )

                print("Routing path: \(p.map { $0.id })")

                // Base (visual) instruction
                instructionText =
                    "Ready to guide from \(placeName(startId)) to \(placeName(goalId))."

                // Auto-start decision
                if autoStartNav && !isRunning {
                    driver.start()
                    buffer = BeaconSignalBuffer(
                        windowSeconds: 3.0,
                        maxSamplesPerBeacon: 25
                    )
                    isRunning = true
                    speak("Navigation started")
                    instructionText =
                        "Navigation started. Follow the audio instructions."
                } else {
                    instructionText = "Ready. Press Start when you are ready."
                }

                // VoiceOver-first announcement
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    focusInstruction = true
                    if voiceOverEnabled {
                        speakRouteSummary()
                    }
                }

            } else {
                print("No path found from \(startId) to \(goalId)")
                instructionText =
                    "Route not available. Please choose a different destination."
            }
        }

        .onDisappear {
            print("NavigatorView disappeared – stop mock")
            driver.stop()
            buffer = BeaconSignalBuffer(
                windowSeconds: 3.0,
                maxSamplesPerBeacon: 25
            )
            isRunning = false
        }
        .onReceive(driver.latestPublisher) { readings in
            handleReadings(readings)
        }
        .navigationTitle("Guided Navigation")
    }

    private func prettyNodeName(_ id: String) -> String {
        // Later: map node IDs to human labels, e.g. "Elevator 1", "Ticket gate"
        switch id {
        case "E1": return "elevator"
        default: return id
        }
    }

    private func speak(_ s: String) {
        speech.say(s)
    }

    private func maybeAnnounce(_ s: String) {
        guard !voiceOverEnabled else { return }  // VO already reads UI text
        if Date().timeIntervalSince(lastAnnounce) > 3 {
            Haptics.tick()
            speech.say(s)
            lastAnnounce = Date()
        }
    }

    private func placeName(_ id: String) -> String {
        places[id]?.name ?? id
    }

    private func speakRouteSummary() {
        let from = placeName(startId)
        let to = placeName(goalId)

        let summary: String
        if autoStartNav {
            summary =
                "Guided navigation. From \(from) to \(to). Navigation will start automatically."
        } else {
            summary =
                "Guided navigation. From \(from) to \(to). Double tap Start to begin."
        }

        instructionText = summary
        speech.say(summary)
    }

    private func overlapCount(
        currentKeys: Set<String>,
        fingerprint: Fingerprint
    ) -> Int {
        let fpKeys = Set(fingerprint.rssi.keys)
        return currentKeys.intersection(fpKeys).count
    }

    private func handleReadings(_ readings: [BeaconReading]) {
        guard isRunning else { return }

        let ts = tsFormatter.string(from: Date())
        print("[\(ts)] Navigator received \(readings.count) readings")

        guard !readings.isEmpty else {
            posText = "—"
            return
        }

        // Build smoothed RSSI vector
        // Feed rolling window buffer (median is used for KNN)
        let now = Date()
        buffer.ingest(readings, now: now)
        buffer.pruneStale(now: now, staleAfter: 5.0)

        let vec = buffer.medianVector(minSamples: 3, maxAge: 1.5, now: now)
        let currentKeys = Set(vec.keys)

        // Quick signal check: overlap with fingerprints
        let bestOverlap =
            fps.map {
                overlapCount(currentKeys: currentKeys, fingerprint: $0)
            }.max() ?? 0

        if bestOverlap < minBeaconsForFix {
            // Not enough information to localize reliably
            if Date().timeIntervalSince(lastGoodFixAt)
                > maxSecondsWithoutFix
            {
                positionLost = true
                let msg =
                    "Signal weak. Please stop and hold your phone still."
                instructionText = msg
                Haptics.warn()
                speak(msg)
            }
            posText = "—"
            return
        }

        guard
            let est = KNNPositioner.estimate(
                current: vec,
                dataset: fps,
                k: 3
            )
        else {
            print("[\(ts)] No estimate")
            posText = "—"
            return
        }

        lastGoodFixAt = est.ts
        positionLost = false

        // If confidence is low, do NOT do off-route / reroute. Still allow basic “signal weak” prompts.
        if est.overlap < minOverlapForGuidance
            || est.confidence < minConfidenceForGuidance
        {
            posText = String(
                format: "(%.1f, %.1f, %@)  conf=%.2f ov=%d",
                est.x,
                est.y,
                est.floor,
                est.confidence,
                est.overlap
            )
            instructionText = "Signal unstable. Please hold your phone steady."
            // Don't speak too often; reuse your existing announcement limiter
            maybeAnnounce("Signal unstable. Please hold your phone steady.")
            return
        }

        // ===== Floor transition mode =====
        if let needFloor = expectedFloor {
            // Keep reminding (rate-limited)
            if Date().timeIntervalSince(lastFloorAnnounce)
                > floorAnnounceCooldown
            {
                lastFloorAnnounce = Date()
                let msg = "Please move to floor \(needFloor)."
                instructionText = msg
                speak(msg)
                Haptics.tick()
            }

            // Exit transition mode once estimator reports we're on the expected floor
            if est.floor == needFloor {
                expectedFloor = nil
                let msg = "Now on floor \(needFloor). Continue."
                instructionText = msg
                speak(msg)
                Haptics.tick()
            }

            // While transitioning, do NOT run normal distance guidance/off-route logic
            return
        }

        // Decide which node we are currently targeting
        guard let target = nextNode() else {
            posText = "Route complete."
            instructionText = "Route complete."
            return
        }

        if arrived { return }

        // Distance to current target node
        let dx = est.x - target.x
        let dy = est.y - target.y
        let dist = sqrt(dx * dx + dy * dy)

        // Segment is from "fromNode" -> "target"
        let fromNode: Graph.Node? =
            (currentSegmentIndex > 0) ? path[currentSegmentIndex - 1] : nil

        if let from = fromNode, est.floor == from.floor,
            est.floor == target.floor
        {
            let dSeg = distancePointToSegment(
                px: est.x,
                py: est.y,
                ax: from.x,
                ay: from.y,
                bx: target.x,
                by: target.y
            )

            if dSeg > offRouteThresholdMeters {
                offRouteStreak += 1
                print(
                    "[\(ts)] Off-route candidate: dSeg=\(String(format: "%.2f", dSeg)) streak=\(offRouteStreak)"
                )
            } else {
                offRouteStreak = 0
            }

            if offRouteStreak >= offRouteConfirmCount
                && Date().timeIntervalSince(lastOffRouteAnnounce)
                    > offRouteAnnounceCooldown
            {

                lastOffRouteAnnounce = Date()
                offRouteStreak = 0

                let warn =
                    "You may be off route. Please stop and reorient. Recalculating."
                instructionText = warn
                Haptics.warn()
                speak(warn)

                if autoRerouteEnabled,
                    let nearest = GraphRouter.nearestNode(
                        toX: est.x,
                        y: est.y,
                        floor: est.floor,
                        in: graph
                    )
                {

                    let newPath = GraphRouter.shortestPath(
                        from: nearest.id,
                        to: goalId,
                        in: graph
                    )

                    if !newPath.isEmpty {
                        path = newPath
                        currentSegmentIndex = 0
                        print(
                            "[\(ts)] Re-routed from \(nearest.id): \(newPath.map { $0.id })"
                        )
                        speak("New route found. Continue.")
                    } else {
                        speak(
                            "Unable to find a new route. Please ask for assistance."
                        )
                    }
                }
            }
        }

        // ====== ARRIVAL AT CURRENT TARGET NODE ======
        if dist <= arrivalThreshold && est.floor == target.floor {
            let isFinal = (currentSegmentIndex == path.count - 1)

            if isFinal {
                if !arrived {
                    arrived = true
                    let msg = "You have arrived at your final destination."
                    print("[\(ts)] \(msg) at node \(placeName(target.id))")
                    posText = "Arrived at \(target.id)"
                    instructionText =
                        "You have arrived at your destination."
                    Haptics.warn()
                    speak(msg)
                }
                return
            } else {
                // Intermediate node: optional turn instruction
                var turnInstruction: String? = nil

                if path.count >= 3 && currentSegmentIndex >= 1 {
                    let prev = path[currentSegmentIndex - 1]
                    let curr = path[currentSegmentIndex]
                    let next = path[currentSegmentIndex + 1]

                    let angle = angleBetween(prev, curr, next)

                    if angle < 30 {
                        turnInstruction = "Continue straight"
                    } else if angle > 150 {
                        turnInstruction = "Make a U-turn"
                    } else {
                        let v1 = (curr.x - prev.x, curr.y - prev.y)
                        let v2 = (next.x - curr.x, next.y - curr.y)
                        let cross = v1.0 * v2.1 - v1.1 * v2.0
                        turnInstruction =
                            cross > 0 ? "Turn left" : "Turn right"
                    }
                }

                let msg =
                    if let turn = turnInstruction {
                        "\(turn). Then proceed to the next segment."
                    } else {
                        "Reached \(target.id). Proceed to the next segment."
                    }

                print("[\(ts)] \(msg)")
                instructionText = msg
                Haptics.tick()
                speak(msg)

                // Advance to next node in the path
                // Determine upcoming segment before advancing
                if currentSegmentIndex + 1 < path.count {
                    let curr = path[currentSegmentIndex]  // the node we just reached (target)
                    let next = path[currentSegmentIndex + 1]  // the next target node

                    // Floor change detected
                    if next.floor != curr.floor {
                        // Determine elevator vs stairs from edge attrs (if present)
                        let edge = edgeBetween(
                            graph: graph,
                            curr.id,
                            next.id
                        )
                        let useElevator = edge?.attrs.elevator ?? false
                        let useStairs = edge?.attrs.stairs ?? false

                        let method: String
                        if useElevator {
                            method = "elevator"
                        } else if useStairs {
                            method = "stairs"
                        } else {
                            method = "lift or stairs"
                        }

                        let msg =
                            "Take the \(method) to floor \(next.floor)."
                        instructionText = msg
                        speak(msg)
                        Haptics.warn()

                        // Enter transition mode; pause normal guidance until floor matches
                        expectedFloor = next.floor

                        // Advance segment index now so nextNode is the node on the new floor
                        currentSegmentIndex += 1
                        return
                    }
                }

                // No floor change: normal advance
                currentSegmentIndex += 1
                return
            }
        }

        // ====== STILL APPROACHING CURRENT TARGET ======
        arrived = false
        let detail = String(
            format: "(%.1f, %.1f, %@)  d=%.1f m to %@  conf=%.2f ov=%d",
            est.x,
            est.y,
            est.floor,
            dist,
            target.id,
            est.confidence,
            est.overlap
        )

        print("[\(ts)] New estimate: \(detail)")
        posText = detail

        let spoken = String(
            format: "%.1f meters to %@",
            dist,
            prettyNodeName(target.id)
        )
        instructionText = spoken

        guard !positionLost else { return }

        maybeAnnounce(spoken)
    }
}

// MARK: - Geometry

func angleBetween(_ a: Graph.Node, _ b: Graph.Node, _ c: Graph.Node) -> Double {
    let v1 = (b.x - a.x, b.y - a.y)
    let v2 = (c.x - b.x, c.y - b.y)
    let dot = v1.0 * v2.0 + v1.1 * v2.1
    let mag1 = sqrt(v1.0 * v1.0 + v1.1 * v1.1)
    let mag2 = sqrt(v2.0 * v2.0 + v2.1 * v2.1)
    guard mag1 > 0 && mag2 > 0 else { return 0 }
    let cosA = min(max(dot / (mag1 * mag2), -1), 1)
    return acos(cosA) * 180 / .pi
}

func distancePointToSegment(
    px: Double,
    py: Double,
    ax: Double,
    ay: Double,
    bx: Double,
    by: Double
) -> Double {
    let abx = bx - ax
    let aby = by - ay
    let apx = px - ax
    let apy = py - ay

    let abLen2 = abx * abx + aby * aby
    if abLen2 == 0 { return sqrt(apx * apx + apy * apy) }

    var t = (apx * abx + apy * aby) / abLen2
    t = max(0, min(1, t))

    let cx = ax + t * abx
    let cy = ay + t * aby
    let dx = px - cx
    let dy = py - cy
    return sqrt(dx * dx + dy * dy)
}

func edgeBetween(graph: Graph, _ a: String, _ b: String) -> Graph.Edge? {
    graph.edges.first {
        ($0.from == a && $0.to == b) || ($0.from == b && $0.to == a)
    }
}
