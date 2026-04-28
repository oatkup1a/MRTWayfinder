import Combine
import SwiftUI

struct NavTestRunView: View {
    let destinationId: String

    @AppStorage("navmrt.dataPack") private var dataPackId: String = DataPackCatalog.defaultPackId
    @AppStorage("navmrt.useMockBeacons") private var useMockBeacons: Bool = true

    @State private var engine: NavigationEngine?
    @State private var beaconDriver: BeaconDriver?
    @State private var beaconRegistry: BeaconRegistry?
    @State private var graph: Graph?
    @State private var hasStarted = false

    var body: some View {
        VStack(spacing: 0) {
            statusBar

            GeometryReader { geometry in
                if let registry = beaconRegistry, let graph = graph, let engine = engine {
                    NavigationMapView(
                        engine: engine,
                        beaconRegistry: registry,
                        graph: graph,
                        displayFloor: displayFloor,
                        frameSize: geometry.size
                    )
                } else {
                    ContentUnavailableView("Loading...", systemImage: "map")
                }
            }
            .background(Color(.systemGray6))

            if let engine = engine {
                instructionBar(engine: engine)
            }

            controlBar
        }
        .navigationTitle("Navigation")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadDataAndPrepare() }
        .onDisappear { engine?.stop() }
    }

    // MARK: - Display Floor

    private var displayFloor: String {
        engine?.currentPosition?.floor ?? beaconRegistry?.beacons.first?.floor ?? "G"
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            if let engine = engine {
                Circle()
                    .fill(statusColor(engine.status))
                    .frame(width: 10, height: 10)
                Text(statusText(engine.status))
                    .font(.subheadline.bold())

                Text(displayFloor)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())

                Spacer()
                Text(String(format: "%.0fm remaining", engine.distanceToDestination))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Preparing...")
                    .font(.subheadline)
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    // MARK: - Instruction Bar

    private func instructionBar(engine: NavigationEngine) -> some View {
        HStack {
            Image(systemName: instructionIcon(engine: engine))
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)
            Text(engine.instruction?.text ?? "Calculating route...")
                .font(.subheadline.bold())
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                engine?.repeatInstruction()
            } label: {
                Label("Repeat", systemImage: "arrow.counterclockwise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }
            .disabled(!hasStarted)

            Button {
                if hasStarted {
                    engine?.stop()
                    hasStarted = false
                } else {
                    engine?.start()
                    hasStarted = true
                }
            } label: {
                Label(
                    hasStarted ? "Stop" : "Start",
                    systemImage: hasStarted ? "stop.circle.fill" : "location.circle.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(hasStarted ? Color.red : Color.blue)
                .foregroundStyle(.white)
                .cornerRadius(12)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Data Loading

    private func loadDataAndPrepare() {
        let pack = DataPackCatalog.pack(by: dataPackId)
            ?? DataPackOption(id: DataPackCatalog.defaultPackId, name: "Sam Yan")

        func resource(_ name: String) -> String {
            if let prefix = pack.filePrefix { "\(prefix)_\(name)" } else { name }
        }

        guard let beaconsURL = Bundle.main.url(forResource: resource("beacons"), withExtension: "json"),
              let graphURL = Bundle.main.url(forResource: resource("graph"), withExtension: "json"),
              let fpURL = Bundle.main.url(forResource: resource("fingerprints"), withExtension: "json")
        else { return }

        do {
            let registry = try JSONDecoder().decode(BeaconRegistry.self, from: Data(contentsOf: beaconsURL))
            let loadedGraph = try JSONDecoder().decode(Graph.self, from: Data(contentsOf: graphURL))
            let fingerprints = try JSONDecoder().decode([Fingerprint].self, from: Data(contentsOf: fpURL))

            self.beaconRegistry = registry
            self.graph = loadedGraph

            let driver = BeaconDriver(initialMode: useMockBeacons ? .mock : .real)
            driver.configureReal(registry: registry)

            if useMockBeacons {
                let mockLabels = buildMockPath(
                    destinationId: destinationId,
                    graph: loadedGraph,
                    fingerprints: fingerprints
                )
                if mockLabels.count >= 2 {
                    driver.configureMockPath(labels: mockLabels, fingerprints: fingerprints)
                } else if let startNode = loadedGraph.nodes.first {
                    driver.configureMockJourney(startId: startNode.id, goalId: destinationId)
                }
            }

            self.beaconDriver = driver
            self.engine = NavigationEngine(
                destinationId: destinationId,
                beaconDriver: driver,
                graph: loadedGraph,
                fingerprints: fingerprints,
                beaconRegistry: registry
            )
        } catch {
            print("NavTestRunView: failed to load data: \(error)")
        }
    }

    private func buildMockPath(
        destinationId: String,
        graph: Graph,
        fingerprints: [Fingerprint]
    ) -> [String] {
        let allPaths = graph.nodes.compactMap { node -> (path: [Graph.Node], cost: Double)? in
            guard node.id != destinationId else { return nil }
            let path = GraphRouter.shortestPath(from: node.id, to: destinationId, in: graph)
            guard path.count >= 2 else { return nil }
            var cost = 0.0
            for i in 0..<(path.count - 1) {
                let dx = path[i + 1].x - path[i].x
                let dy = path[i + 1].y - path[i].y
                cost += sqrt(dx * dx + dy * dy)
            }
            return (path, cost)
        }
        guard let longest = allPaths.max(by: { $0.cost < $1.cost }) else { return [] }

        return longest.path.compactMap { node in
            nearestFingerprintLabel(x: node.x, y: node.y, floor: node.floor, fingerprints: fingerprints)
        }
    }

    private func nearestFingerprintLabel(
        x: Double, y: Double, floor: String, fingerprints: [Fingerprint]
    ) -> String? {
        fingerprints
            .filter { $0.loc.floor == floor }
            .min(by: {
                let d0 = ($0.loc.x - x) * ($0.loc.x - x) + ($0.loc.y - y) * ($0.loc.y - y)
                let d1 = ($1.loc.x - x) * ($1.loc.x - x) + ($1.loc.y - y) * ($1.loc.y - y)
                return d0 < d1
            })?.label
    }

    private func reloadBeaconMode() {
        guard let driver = beaconDriver else { return }
        let wasRunning = hasStarted
        if wasRunning { engine?.stop() }
        driver.setMode(useMockBeacons ? .mock : .real, startIfRunning: false)
        if wasRunning {
            engine?.start()
            hasStarted = true
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: NavigationEngine.Status) -> Color {
        switch status {
        case .idle: .gray
        case .navigating: .green
        case .offRoute: .orange
        case .rerouting: .yellow
        case .arrived: .blue
        }
    }

    private func statusText(_ status: NavigationEngine.Status) -> String {
        switch status {
        case .idle: "Ready"
        case .navigating: "Navigating"
        case .offRoute: "Off Route"
        case .rerouting: "Rerouting..."
        case .arrived: "Arrived"
        }
    }

    private func instructionIcon(engine: NavigationEngine) -> String {
        guard let instruction = engine.instruction else { return "arrow.up" }
        if instruction.text.contains("elevator") { return "elevator.fill" }
        if instruction.text.contains("stairs") { return "figure.stairs" }
        if instruction.text.contains("left") { return "arrow.turn.up.left" }
        if instruction.text.contains("right") { return "arrow.turn.up.right" }
        if instruction.text.contains("U-turn") { return "arrow.uturn.down" }
        if instruction.text.contains("arrived") || instruction.text.contains("destination") { return "flag.fill" }
        return "arrow.up"
    }
}

// MARK: - Navigation Map

struct NavigationMapView: View {
    let engine: NavigationEngine
    let beaconRegistry: BeaconRegistry
    let graph: Graph
    let displayFloor: String
    let frameSize: CGSize

    private var floorBeacons: [Beacon] {
        beaconRegistry.beacons.filter { $0.floor == displayFloor }
    }

    private var floorNodes: [Graph.Node] {
        graph.nodes.filter { $0.floor == displayFloor }
    }

    private var transform: MapTransform {
        MapTransform(beacons: floorBeacons, frameSize: frameSize)
    }

    var body: some View {
        ZStack {
            MeterGrid(transform: transform)

            routeOverlay

            ForEach(floorBeacons, id: \.compositeId) { beacon in
                SmallBeaconMarker(beacon: beacon, transform: transform)
            }

            graphNodeMarkers

            if let pos = engine.currentPosition, pos.floor == displayFloor {
                NavigationPositionMarker(
                    position: snappedPosition(pos),
                    transform: transform
                )
            }

            if let dest = graph.nodes.first(where: { $0.id == engine.route.last?.id ?? "" }),
               dest.floor == displayFloor {
                DestinationMarker(node: dest, transform: transform)
            }
        }
    }

    // MARK: - Route Overlay

    private var routeOverlay: some View {
        Canvas { context, _ in
            let route = engine.route
            guard route.count >= 2 else { return }
            let seg = engine.currentSegmentIndex

            for i in 0..<(route.count - 1) {
                guard route[i].floor == displayFloor && route[i + 1].floor == displayFloor else { continue }

                let a = transform.toScreen(x: route[i].x, y: route[i].y)
                let b = transform.toScreen(x: route[i + 1].x, y: route[i + 1].y)

                var path = Path()
                path.move(to: a)
                path.addLine(to: b)

                let color: Color
                let width: CGFloat
                if i < seg {
                    color = .gray.opacity(0.3)
                    width = 2
                } else {
                    color = .blue
                    width = 4
                }

                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }

    // MARK: - Graph Node Markers

    private var graphNodeMarkers: some View {
        ForEach(floorNodes, id: \.id) { node in
            let pt = transform.toScreen(x: node.x, y: node.y)
            Circle()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
                .overlay(
                    Text(node.id)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .offset(y: -12)
                )
                .position(pt)
        }
    }

    // MARK: - Snap to Route

    private func snappedPosition(_ pos: PositionFix) -> PositionFix {
        let route = engine.route
        guard route.count >= 2 else { return pos }

        var bestX = pos.x
        var bestY = pos.y
        var bestDist = Double.greatestFiniteMagnitude

        for i in 0..<(route.count - 1) {
            let ax = route[i].x, ay = route[i].y
            let bx = route[i + 1].x, by = route[i + 1].y
            let (px, py, d) = projectOntoSegment(
                px: pos.x, py: pos.y,
                ax: ax, ay: ay, bx: bx, by: by
            )
            if d < bestDist {
                bestDist = d
                bestX = px
                bestY = py
            }
        }

        return PositionFix(
            x: bestX, y: bestY,
            floor: pos.floor,
            confidence: pos.confidence,
            overlap: pos.overlap,
            ts: pos.ts
        )
    }

    private func projectOntoSegment(
        px: Double, py: Double,
        ax: Double, ay: Double,
        bx: Double, by: Double
    ) -> (x: Double, y: Double, dist: Double) {
        let abx = bx - ax, aby = by - ay
        let apx = px - ax, apy = py - ay
        let ab2 = abx * abx + aby * aby
        guard ab2 > 0 else {
            let d = sqrt(apx * apx + apy * apy)
            return (ax, ay, d)
        }
        let t = max(0, min(1, (apx * abx + apy * aby) / ab2))
        let projX = ax + t * abx
        let projY = ay + t * aby
        let dx = px - projX, dy = py - projY
        return (projX, projY, sqrt(dx * dx + dy * dy))
    }
}

// MARK: - Small Beacon Marker

struct SmallBeaconMarker: View {
    let beacon: Beacon
    let transform: MapTransform

    var body: some View {
        let pt = transform.toScreen(x: beacon.x, y: beacon.y)
        Image(systemName: "antenna.radiowaves.left.and.right")
            .font(.system(size: 8))
            .foregroundStyle(.gray.opacity(0.5))
            .position(pt)
    }
}

// MARK: - Navigation Position Marker

struct NavigationPositionMarker: View {
    let position: PositionFix
    let transform: MapTransform
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        let pt = transform.toScreen(x: position.x, y: position.y)
        ZStack {
            Circle()
                .fill(Color.green.opacity(0.25))
                .frame(width: 30, height: 30)
                .scaleEffect(pulseScale)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: pulseScale
                )

            Circle()
                .fill(Color.green)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
        }
        .position(pt)
        .onAppear { pulseScale = 1.4 }
    }
}

// MARK: - Destination Marker

struct DestinationMarker: View {
    let node: Graph.Node
    let transform: MapTransform

    var body: some View {
        let pt = transform.toScreen(x: node.x, y: node.y)
        Circle()
            .fill(Color.blue)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .position(pt)
    }
}
