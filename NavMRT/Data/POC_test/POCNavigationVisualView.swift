import SwiftUI
import Combine

/// Enhanced POC Navigation with Full-Screen Visual Map
/// Features: Real-time position tracking, animated path progress, beacon signal strength
struct POCNavigationVisualView: View {
    
    // MARK: - Beacon Positioning
    
    @StateObject private var driver: BeaconDriver
    @State private var buffer = BeaconSignalBuffer(
        windowSeconds: 3.0,
        maxSamplesPerBeacon: 25
    )
    
    // Data sources
    let beacons = DataStore.shared.beacons
    let fingerprints = DataStore.shared.fingerprints
    
    // MARK: - Navigation State
    
    @State private var path: [Graph.Node] = []
    @State private var instructions: [POCNavigationInstructions.Instruction] = []
    @State private var currentSegmentIndex: Int = 0
    
    // MARK: - Position State
    
    @State private var currentPosition: (x: Double, y: Double)?
    @State private var positionConfidence: Double = 0.0
    @State private var lastGoodFixAt: Date = .distantPast
    @State private var positionLost: Bool = false
    
    // MARK: - UI State
    
    @State private var isNavigating: Bool = false
    @State private var instructionText: String = "Press Start to begin navigation"
    @State private var distanceToNext: Double?
    @State private var showCompletionAlert: Bool = false
    @State private var debugText: String = "—"
    @State private var showDebugInfo: Bool = false
    @State private var currentBeaconReadings: [BeaconReading] = []
    
    // MARK: - Configuration
    
    let arrivalThreshold: Double = 1.5
    let offRouteThreshold: Double = 5.0
    let minBeaconsForFix: Int = 2
    let minConfidenceForGuidance: Double = 0.01
    let announceCooldown: TimeInterval = 2.0
    
    @State private var lastAnnounce: Date = .distantPast
    @State private var offRouteStreak: Int = 0
    let offRouteConfirmCount: Int = 3
    
    // MARK: - Services
    
    private let speech = Speech()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("navmrt.useMockBeacons") private var useMockBeacons: Bool = false
    
    // MARK: - Init
    
    init() {
        _driver = StateObject(wrappedValue: BeaconDriver(initialMode: .mock))
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Full-screen map view
            fullScreenMapView
            
            // Floating UI overlay
            VStack {
                // Top info bar
                topInfoBar
                    .padding()
                
                Spacer()
                
                // Bottom instruction card
                bottomInstructionCard
                    .padding()
            }
        }
        .navigationTitle("Visual Navigation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDebugInfo.toggle()
                } label: {
                    Image(systemName: showDebugInfo ? "info.circle.fill" : "info.circle")
                }
            }
        }
        .alert("Navigation Complete", isPresented: $showCompletionAlert) {
            Button("OK") {
                stopNavigation()
                dismiss()
            }
        } message: {
            Text("You have successfully arrived at Point B!")
        }
        .sheet(isPresented: $showDebugInfo) {
            debugSheet
        }
        .onAppear {
            setupPath()
            syncBeaconMode()
        }
        .onChange(of: useMockBeacons) { _, _ in
            syncBeaconMode()
        }
        .onReceive(driver.latestPublisher) { readings in
            currentBeaconReadings = readings
            processBeaconReadings(readings)
        }
    }
    
    // MARK: - Visual Map View
    
    private var fullScreenMapView: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let mapWidth: Double = 6.0
            let mapHeight: Double = 6.0
            
            // Reserve space: top bar (80px) + bottom card (150px) = 230px total
            let topBarSpace: CGFloat = 80
            let bottomCardSpace: CGFloat = 150
            let availableHeight = size.height - topBarSpace - bottomCardSpace
            
            let scale = min(size.width / mapWidth, availableHeight / mapHeight)
            
            // Position map: center it in the available space between top and bottom
            let mapActualHeight = mapHeight * scale
            let verticalOffset = topBarSpace + (availableHeight - mapActualHeight) / 2
            
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(.systemGray6), Color(.systemGray5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                // Map content group - positioned with offset from top
                ZStack {
                    // Grid
                    gridView(size: CGSize(width: size.width, height: mapActualHeight), scale: scale, mapWidth: mapWidth, mapHeight: mapHeight)
                    
                    // Beacons with signal strength
                    beaconViews(size: CGSize(width: size.width, height: mapActualHeight), scale: scale)
                    
                    // Navigation path
                    pathViews(size: CGSize(width: size.width, height: mapActualHeight), scale: scale)
                    
                    // Current position with heading
                    currentPositionView(size: CGSize(width: size.width, height: mapActualHeight), scale: scale)
                }
                .frame(height: mapActualHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(x: 20, y: verticalOffset - 30)
                
                // Compass/scale indicator - keep in original position
                mapLegend
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding()
            }
        }
    }
    
    private func gridView(size: CGSize, scale: Double, mapWidth: Double, mapHeight: Double) -> some View {
        Path { path in
            for x in stride(from: 0.0, through: mapWidth, by: 1.0) {
                let screenX = x * scale
                path.move(to: CGPoint(x: screenX, y: 0))
                path.addLine(to: CGPoint(x: screenX, y: size.height))
            }
            for y in stride(from: 0.0, through: mapHeight, by: 1.0) {
                let screenY = size.height - (y * scale)
                path.move(to: CGPoint(x: 0, y: screenY))
                path.addLine(to: CGPoint(x: size.width, y: screenY))
            }
        }
        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
    }
    
    private func beaconViews(size: CGSize, scale: Double) -> some View {
        ForEach(beacons.beacons, id: \.id) { beacon in
            let beaconId = "\(beacon.uuid.uppercased()):\(beacon.major):\(beacon.minor)"
            let signalStrength = currentBeaconReadings.first(where: { $0.id == beaconId })?.rssi ?? -100
            let isActive = signalStrength > -100
            
            ZStack {
                // Signal ripple effect
                if isActive {
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                        .frame(width: 40, height: 40)
                    
                    Circle()
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        .frame(width: 60, height: 60)
                }
                
                // Beacon marker
                Circle()
                    .fill(isActive ? Color.blue : Color.gray)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                
                // RSSI label
                if isActive && showDebugInfo {
                    Text("\(signalStrength)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(2)
                        .background(Color.blue)
                        .cornerRadius(4)
                        .offset(y: -15)
                }
            }
            .position(
                x: beacon.x * scale,
                y: size.height - (beacon.y * scale)
            )
        }
    }
    
    private func pathViews(size: CGSize, scale: Double) -> some View {
        Group {
            if !path.isEmpty {
                // Path line
                Path { pathShape in
                    let firstNode = path[0]
                    pathShape.move(to: CGPoint(
                        x: firstNode.x * scale,
                        y: size.height - (firstNode.y * scale)
                    ))
                    
                    for node in path.dropFirst() {
                        pathShape.addLine(to: CGPoint(
                            x: node.x * scale,
                            y: size.height - (node.y * scale)
                        ))
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [Color.green, Color.yellow, Color.red],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
                
                // Progress indicator on path
                if let pos = currentPosition, currentSegmentIndex < path.count {
                    let progress = CGFloat(currentSegmentIndex) / CGFloat(max(1, path.count - 1))
                    
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .position(
                            x: pos.x * scale,
                            y: size.height - (pos.y * scale)
                        )
                }
                
                // Start marker
                if let start = path.first {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 32, height: 32)
                        Text("A")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                    }
                    .position(
                        x: start.x * scale,
                        y: size.height - (start.y * scale)
                    )
                }
                
                // Goal marker
                if let goal = path.last {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 32, height: 32)
                        Image(systemName: "flag.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                    .position(
                        x: goal.x * scale,
                        y: size.height - (goal.y * scale)
                    )
                }
            }
        }
    }
    
    private func currentPositionView(size: CGSize, scale: Double) -> some View {
        Group {
            if let pos = currentPosition {
                ZStack {
                    // Accuracy circle
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    // Pulsing ring
                    Circle()
                        .stroke(statusColor.opacity(0.5), lineWidth: 3)
                        .frame(width: 30, height: 30)
                        .scaleEffect(isNavigating ? 1.2 : 1.0)
                        .opacity(isNavigating ? 0.3 : 0.8)
                        .animation(
                            Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                            value: isNavigating
                        )
                    
                    // Position dot
                    Circle()
                        .fill(statusColor)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 3)
                        )
                    
                    // Direction indicator (if moving)
                    if currentSegmentIndex < path.count {
                        let target = path[currentSegmentIndex]
                        let dx = target.x - pos.x
                        let dy = target.y - pos.y
                        let angle = atan2(dy, dx)
                        
                        Image(systemName: "location.north.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .rotationEffect(.radians(angle - .pi / 2))
                    }
                }
                .position(
                    x: pos.x * scale,
                    y: size.height - (pos.y * scale)
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pos.x)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pos.y)
            }
        }
    }
    
    private var mapLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("POC Test Environment")
                .font(.caption.bold())
            
            HStack(spacing: 8) {
                Circle().fill(Color.blue).frame(width: 8, height: 8)
                Text("Beacons").font(.caption2)
            }
            
            HStack(spacing: 8) {
                Rectangle()
                    .fill(LinearGradient(colors: [.green, .red], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 20, height: 4)
                Text("Path").font(.caption2)
            }
            
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text("Your Position").font(.caption2)
            }
            
            Divider()
            
            Text("Mode: \(useMockBeacons ? "Mock" : "Real")")
                .font(.caption2)
                .foregroundColor(useMockBeacons ? .orange : .green)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemBackground).opacity(0.95))
                .shadow(radius: 5)
        )
    }
    
    // MARK: - UI Overlays
    
    private var topInfoBar: some View {
        HStack {
            // Progress indicator
            VStack(alignment: .leading, spacing: 4) {
                Text("Step \(currentSegmentIndex + 1)/\(instructions.count)")
                    .font(.caption.bold())
                
                ProgressView(value: progress)
                    .tint(statusColor)
                    .frame(width: 100)
            }
            
            Spacer()
            
            // Signal strength
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: signalIcon)
                        .font(.caption)
                    Text("\(currentBeaconReadings.count)")
                        .font(.caption.bold())
                }
                .foregroundColor(signalColor)
                
                Text("beacons")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground).opacity(0.95))
                .shadow(radius: 5)
        )
    }
    
    private var bottomInstructionCard: some View {
        VStack(spacing: 12) {
            // Instruction text
            Text(instructionText)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            
            // Distance indicator
            if let distance = distanceToNext {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.forward")
                    Text(String(format: "%.1f m", distance))
                        .font(.title3.bold())
                }
                .foregroundColor(statusColor)
            }
            
            // Controls
            HStack(spacing: 12) {
                if !isNavigating {
                    Button {
                        startNavigation()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                } else {
                    Button {
                        speech.say(instructionText)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.headline)
                            .padding()
                            .background(Color(.systemGray5))
                            .cornerRadius(10)
                    }
                    
                    Button {
                        stopNavigation()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground).opacity(0.95))
                .shadow(radius: 10)
        )
    }
    
    private var debugSheet: some View {
        NavigationStack {
            List {
                Section("Position") {
                    if let pos = currentPosition {
                        LabeledContent("X", value: String(format: "%.2f m", pos.x))
                        LabeledContent("Y", value: String(format: "%.2f m", pos.y))
                        LabeledContent("Confidence", value: String(format: "%.2f", positionConfidence))
                    } else {
                        Text("No position fix")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Beacons (\(currentBeaconReadings.count))") {
                    ForEach(currentBeaconReadings) { reading in
                        HStack {
                            Text(reading.identifierShort)
                                .font(.caption.monospaced())
                            Spacer()
                            Text("\(reading.rssi) dBm")
                                .font(.caption.bold())
                                .foregroundColor(rssiColor(reading.rssi))
                        }
                    }
                }
                
                Section("Navigation") {
                    LabeledContent("Current Segment", value: "\(currentSegmentIndex + 1)/\(path.count)")
                    LabeledContent("Off-route Streak", value: "\(offRouteStreak)")
                    LabeledContent("Status", value: positionLost ? "Lost" : "Good")
                        .foregroundColor(positionLost ? .red : .green)
                }
            }
            .navigationTitle("Debug Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showDebugInfo = false
                    }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var progress: Double {
        guard !instructions.isEmpty else { return 0 }
        return Double(currentSegmentIndex) / Double(instructions.count)
    }
    
    private var statusColor: Color {
        if positionLost {
            return .red
        } else if positionConfidence < minConfidenceForGuidance {
            return .orange
        } else {
            return .purple
        }
    }
    
    private var signalIcon: String {
        let count = currentBeaconReadings.count
        if count >= 4 { return "antenna.radiowaves.left.and.right" }
        else if count >= 2 { return "wifi" }
        else { return "wifi.exclamationmark" }
    }
    
    private var signalColor: Color {
        let count = currentBeaconReadings.count
        if count >= 4 { return .green }
        else if count >= 2 { return .orange }
        else { return .red }
    }
    
    private func rssiColor(_ rssi: Int) -> Color {
        if rssi > -60 { return .green }
        else if rssi > -75 { return .orange }
        else { return .red }
    }
    
    // MARK: - Setup & Navigation Control
    
    private func setupPath() {
        // POC path: Start (0, 0.5) → turn 90° left at (4.5, 0.5) → end at (4.5, 5)
        path = [
            Graph.Node(id: "A", x: 0.0, y: 0.5, floor: "Ground", type: "start"),            // Start at (0, 0.5)
            Graph.Node(id: "Mid1", x: 2.25, y: 0.5, floor: "Ground", type: "waypoint"),    // Midpoint horizontal
            Graph.Node(id: "Junction", x: 4.5, y: 0.5, floor: "Ground", type: "junction"),  // Turn left 90° at (4.5, 0.5)
            Graph.Node(id: "Mid2", x: 4.5, y: 2.75, floor: "Ground", type: "waypoint"),    // Midpoint vertical
            Graph.Node(id: "B", x: 4.5, y: 5.0, floor: "Ground", type: "destination")      // End at (4.5, 5)
        ]
        
        instructions = POCNavigationInstructions.generateInstructions(
            for: path,
            startName: "Point A",
            destinationName: "Point B"
        )
    }
    
    private func syncBeaconMode() {
        let newMode: BeaconDriver.Mode = useMockBeacons ? .mock : .real
        driver.setMode(newMode, startIfRunning: isNavigating)
    }
    
    private func startNavigation() {
        currentSegmentIndex = 0
        isNavigating = true
        offRouteStreak = 0
        positionLost = false
        lastGoodFixAt = .distantPast
        lastAnnounce = .distantPast
        
        buffer = BeaconSignalBuffer(windowSeconds: 3.0, maxSamplesPerBeacon: 25)
        
        driver.configureReal(registry: beacons)
        driver.start()
        
        if !instructions.isEmpty {
            instructionText = instructions[0].spokenText
            speech.say(instructionText)
        }
        
        debugText = "Navigation started"
    }
    
    private func stopNavigation() {
        isNavigating = false
        driver.stop()
        instructionText = "Press Start to begin navigation"
        distanceToNext = nil
        currentPosition = nil
        debugText = "—"
    }
    
    // MARK: - Beacon Processing (same as before)
    
    private func processBeaconReadings(_ readings: [BeaconReading]) {
        guard isNavigating else { return }
        
        let now = Date()
        buffer.ingest(readings, now: now)
        buffer.pruneStale(now: now, staleAfter: 5.0)
        
        let smoothed = buffer.medianVector(minSamples: 3, maxAge: 1.5, now: now)
        
        guard smoothed.count >= minBeaconsForFix else {
            handleWeakSignal()
            return
        }
        
        guard let fix = KNNPositioner.estimate(
            current: smoothed,
            dataset: fingerprints,
            k: 3
        ) else {
            handleWeakSignal()
            return
        }
        
        guard fix.confidence >= minConfidenceForGuidance,
              fix.overlap >= minBeaconsForFix else {
            handleWeakSignal()
            return
        }
        
        currentPosition = (x: fix.x, y: fix.y)
        positionConfidence = fix.confidence
        lastGoodFixAt = Date()
        positionLost = false
        
        updateNavigationProgress(position: (fix.x, fix.y))
    }
    
    private func handleWeakSignal() {
        let now = Date()
        let timeSinceLastFix = now.timeIntervalSince(lastGoodFixAt)
        
        if timeSinceLastFix > 3.0 && !positionLost {
            positionLost = true
            instructionText = "Weak signal. Move closer to beacons."
        }
    }
    
    private func updateNavigationProgress(position: (x: Double, y: Double)) {
        guard currentSegmentIndex < path.count else { return }
        
        let targetNode = path[currentSegmentIndex]
        let dx = targetNode.x - position.x
        let dy = targetNode.y - position.y
        let distance = sqrt(dx * dx + dy * dy)
        
        distanceToNext = distance
        
        if distance <= arrivalThreshold {
            advanceToNextWaypoint()
            offRouteStreak = 0
        } else {
            updateProximityInstruction(distance: distance, target: targetNode)
            checkOffRoute(position: position)
        }
    }
    
    private func advanceToNextWaypoint() {
        currentSegmentIndex += 1
        
        if currentSegmentIndex >= instructions.count {
            handleArrival()
        } else {
            let nextInstruction = instructions[currentSegmentIndex]
            instructionText = nextInstruction.spokenText
            announceIfNeeded(instructionText)
        }
    }
    
    private func updateProximityInstruction(distance: Double, target: Graph.Node) {
        guard currentSegmentIndex < instructions.count else { return }
        
        let instruction = instructions[currentSegmentIndex]
        
        if let position = currentPosition {
            let proximityText = POCNavigationInstructions.generateProximityInstruction(
                currentPosition: position,
                targetNode: target,
                instruction: instruction
            )
            instructionText = proximityText
        }
    }
    
    private func checkOffRoute(position: (x: Double, y: Double)) {
        guard currentSegmentIndex < path.count - 1 else { return }
        
        let from = path[currentSegmentIndex]
        let to = path[currentSegmentIndex + 1]
        
        let distToSegment = distanceFromPointToLineSegment(
            point: position,
            lineStart: (from.x, from.y),
            lineEnd: (to.x, to.y)
        )
        
        if distToSegment > offRouteThreshold {
            offRouteStreak += 1
            if offRouteStreak >= offRouteConfirmCount {
                handleOffRoute()
            }
        } else {
            offRouteStreak = 0
        }
    }
    
    private func handleOffRoute() {
        let now = Date()
        if now.timeIntervalSince(lastAnnounce) > 5.0 {
            Haptics.warn()
        }
    }
    
    private func handleArrival() {
        instructionText = "You have arrived at Point B!"
        speech.say(instructionText)
        showCompletionAlert = true
    }
    
    private func announceIfNeeded(_ text: String) {
        let now = Date()
        if now.timeIntervalSince(lastAnnounce) >= announceCooldown {
            speech.say(text)
            lastAnnounce = now
        }
    }
    
    private func distanceFromPointToLineSegment(
        point: (x: Double, y: Double),
        lineStart: (x: Double, y: Double),
        lineEnd: (x: Double, y: Double)
    ) -> Double {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let lengthSquared = dx * dx + dy * dy
        
        if lengthSquared == 0 {
            let pdx = point.x - lineStart.x
            let pdy = point.y - lineStart.y
            return sqrt(pdx * pdx + pdy * pdy)
        }
        
        let t = max(0, min(1,
            ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSquared
        ))
        
        let projX = lineStart.x + t * dx
        let projY = lineStart.y + t * dy
        
        let distX = point.x - projX
        let distY = point.y - projY
        
        return sqrt(distX * distX + distY * distY)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        POCNavigationVisualView()
    }
}
