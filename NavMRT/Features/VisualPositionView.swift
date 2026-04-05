import Combine
import SwiftUI

struct VisualPositionView: View {
    @AppStorage("navmrt.useMockBeacons") private var useMockBeacons: Bool = true
    @AppStorage("navmrt.pathLossExponent") private var pathLossExponent: Double = 2.0
    @AppStorage("navmrt.dataPack") private var selectedDataPack: String = DataPackCatalog.defaultPackId
    
    @StateObject private var mockBM = MockBeaconManager()
    @StateObject private var realBM = BeaconManager()
    
    @State private var beaconRegistry: BeaconRegistry?
    @State private var currentPosition: PositionFix?
    @State private var currentReadings: [String: Double] = [:]
    @State private var cancellables = Set<AnyCancellable>()
    @State private var isScanning = false
    
    // Position smoothing
    @State private var previousPosition: (x: Double, y: Double)?
    @AppStorage("navmrt.positionSmoothing") private var smoothingFactor: Double = 0.3
    
    private var activeBeaconManager: BeaconSource {
        useMockBeacons ? mockBM : realBM
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("Indoor Position Tracker")
                    .font(.title2.bold())
                
                // Data pack indicator
                if let registry = beaconRegistry {
                    Text("\(registry.station) • \(registry.beacons.count) beacons")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                HStack(spacing: 16) {
                    Label(
                        isScanning ? "Scanning" : "Stopped",
                        systemImage: isScanning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash"
                    )
                    .foregroundStyle(isScanning ? .green : .secondary)
                    
                    if let pos = currentPosition {
                        Label(
                            "Confidence: \(Int(pos.confidence * 100))%",
                            systemImage: "chart.bar.fill"
                        )
                        .foregroundStyle(.blue)
                    }
                }
                .font(.caption)
            }
            .padding()
            
            // Main visualization
            GeometryReader { geometry in
                PositionMapView(
                    beaconRegistry: beaconRegistry,
                    currentPosition: currentPosition,
                    currentReadings: currentReadings,
                    frameSize: geometry.size
                )
            }
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
            
            // Position details
            if let pos = currentPosition {
                VStack(spacing: 8) {
                    HStack {
                        Text("Position:")
                            .font(.headline)
                        Spacer()
                        Text("X: \(pos.x, specifier: "%.2f")m  Y: \(pos.y, specifier: "%.2f")m")
                            .font(.system(.body, design: .monospaced))
                    }
                    
                    if let z = pos.z {
                        HStack {
                            Text("Height:")
                                .font(.headline)
                            Spacer()
                            Text("Z: \(z, specifier: "%.2f")m")
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    
                    HStack {
                        Text("Beacons:")
                            .font(.headline)
                        Spacer()
                        Text("\(pos.overlap) detected")
                            .font(.body)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            } else {
                Text("No position fix available")
                    .foregroundStyle(.secondary)
                    .padding()
            }
            
            // Controls
            HStack(spacing: 16) {
                Button(action: toggleScanning) {
                    Label(
                        isScanning ? "Stop" : "Start",
                        systemImage: isScanning ? "stop.circle.fill" : "play.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isScanning ? Color.red : Color.green)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
                }
                
                Toggle(isOn: $useMockBeacons) {
                    Text("Mock Data")
                        .font(.subheadline)
                }
                .toggleStyle(.switch)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
            .padding(.horizontal)
            
            // Smoothing control
            VStack(spacing: 8) {
                HStack {
                    Text("Position Smoothing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(smoothingFactor * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.blue)
                }
                Slider(value: $smoothingFactor, in: 0...0.9, step: 0.1)
                    .tint(.blue)
                HStack {
                    Text("None")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Heavy")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            
            .padding(.bottom)
        }
        .onAppear {
            loadBeaconRegistry()
            setupBeaconSubscription()
        }
        .onChange(of: useMockBeacons) { _ in
            if isScanning {
                stopScanning()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    startScanning()
                }
            }
            setupBeaconSubscription()
        }
        .onChange(of: selectedDataPack) { _ in
            // Reload beacon registry when data pack changes
            if isScanning {
                stopScanning()
            }
            loadBeaconRegistry()
            if isScanning {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    startScanning()
                }
            }
        }
    }
    
    private func loadBeaconRegistry() {
        // Force reload by creating a fresh DataStore load
        // (DataStore.shared.beacons is cached, so we load directly)
        let selectedPack = DataPackCatalog.pack(by: selectedDataPack) 
            ?? DataPackOption(id: DataPackCatalog.defaultPackId, name: "Sam Yan")
        
        let resourceName: String
        if let prefix = selectedPack.filePrefix {
            resourceName = "\(prefix)_beacons"
        } else {
            resourceName = "beacons"
        }
        
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json") else {
            print("Failed to find \(resourceName).json")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            let registry = try JSONDecoder().decode(BeaconRegistry.self, from: data)
            beaconRegistry = registry
            
            print("Loaded beacon registry from \(resourceName).json:")
            print("  Station: \(registry.station)")
            print("  Beacons: \(registry.beacons.count)")
            
            // Configure real beacon manager
            realBM.configure(beacons: registry, includeUnregisteredBeacons: false)
            
            // Configure mock beacon manager with a simple route through the space
            configureMockBeaconManager()
            
        } catch {
            print("Failed to decode \(resourceName).json: \(error)")
        }
    }
    
    private func configureMockBeaconManager() {
        // Load fingerprints to find valid nodes for the current data pack
        let fingerprintResourceName: String
        let selectedPack = DataPackCatalog.pack(by: selectedDataPack) 
            ?? DataPackOption(id: DataPackCatalog.defaultPackId, name: "Sam Yan")
        
        if let prefix = selectedPack.filePrefix {
            fingerprintResourceName = "\(prefix)_fingerprints"
        } else {
            fingerprintResourceName = "fingerprints"
        }
        
        guard let fpUrl = Bundle.main.url(forResource: fingerprintResourceName, withExtension: "json") else {
            print("No fingerprints found for mock mode")
            return
        }
        
        do {
            let fpData = try Data(contentsOf: fpUrl)
            let fingerprints = try JSONDecoder().decode([Fingerprint].self, from: fpData)
            
            // Pass fingerprints to mock beacon manager
            mockBM.setFingerprints(fingerprints)
            
            let labels = fingerprints.compactMap { $0.label }
            print("Configured MockBeaconManager with \(labels.count) fingerprint labels: \(labels)")
            
            // Configure a simple route if we have at least 2 nodes
            if labels.count >= 2 {
                mockBM.configureJourney(startId: labels[0], goalId: labels.last!)
            }
        } catch {
            print("Failed to load fingerprints: \(error)")
        }
    }
    
    private func setupBeaconSubscription() {
        cancellables.removeAll()
        
        activeBeaconManager.latestPublisher
            .receive(on: DispatchQueue.main)
            .sink { readings in
                updatePosition(from: readings)
            }
            .store(in: &cancellables)
    }
    
    private func updatePosition(from readings: [BeaconReading]) {
        guard let registry = beaconRegistry else { return }
        
        // Convert readings to RSSI map
        let rssiMap = Dictionary(
            uniqueKeysWithValues: readings.map { ($0.id, Double($0.rssi)) }
        )
        currentReadings = rssiMap
        
        // Calculate position using trilateration
        if let rawPosition = TrilaterationPositioner.estimate(
            current: rssiMap,
            registry: registry,
            pathLossExponent: pathLossExponent
        ) {
            // Apply exponential moving average smoothing
            let smoothedPosition = smoothPosition(rawPosition)
            currentPosition = smoothedPosition
        }
    }
    
    private func smoothPosition(_ newPosition: PositionFix) -> PositionFix {
        guard smoothingFactor > 0, smoothingFactor < 1.0 else {
            // No smoothing
            previousPosition = (newPosition.x, newPosition.y)
            return newPosition
        }
        
        guard let prev = previousPosition else {
            // First position - no smoothing possible
            previousPosition = (newPosition.x, newPosition.y)
            return newPosition
        }
        
        // Exponential moving average: smoothed = alpha * new + (1 - alpha) * previous
        let alpha = smoothingFactor
        let smoothedX = alpha * newPosition.x + (1 - alpha) * prev.x
        let smoothedY = alpha * newPosition.y + (1 - alpha) * prev.y
        
        // Store for next iteration
        previousPosition = (smoothedX, smoothedY)
        
        // Return smoothed position
        return PositionFix(
            x: smoothedX,
            y: smoothedY,
            z: newPosition.z,
            floor: newPosition.floor,
            confidence: newPosition.confidence,
            overlap: newPosition.overlap,
            ts: newPosition.ts
        )
    }
    
    private func toggleScanning() {
        if isScanning {
            stopScanning()
        } else {
            startScanning()
        }
    }
    
    private func startScanning() {
        activeBeaconManager.start()
        isScanning = true
    }
    
    private func stopScanning() {
        activeBeaconManager.stop()
        isScanning = false
        currentPosition = nil
        currentReadings = [:]
    }
}

// MARK: - Position Map Visualization

struct PositionMapView: View {
    let beaconRegistry: BeaconRegistry?
    let currentPosition: PositionFix?
    let currentReadings: [String: Double]
    let frameSize: CGSize
    
    private var bounds: (minX: Double, maxX: Double, minY: Double, maxY: Double)? {
        guard let registry = beaconRegistry, !registry.beacons.isEmpty else {
            return nil
        }
        
        let xs = registry.beacons.map { $0.x }
        let ys = registry.beacons.map { $0.y }
        
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 10
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 10
        
        // Add 10% padding
        let paddingX = (maxX - minX) * 0.1
        let paddingY = (maxY - minY) * 0.1
        
        return (
            minX: minX - paddingX,
            maxX: maxX + paddingX,
            minY: minY - paddingY,
            maxY: maxY + paddingY
        )
    }
    
    var body: some View {
        ZStack {
            // Background grid
            GridPattern()
                .stroke(Color(.systemGray4), lineWidth: 1)
            
            if let registry = beaconRegistry, let bounds = bounds {
                // Beacons
                ForEach(registry.beacons, id: \.compositeId) { beacon in
                    BeaconMarker(
                        beacon: beacon,
                        bounds: bounds,
                        frameSize: frameSize,
                        rssi: currentReadings[beacon.compositeId]
                    )
                }
                
                // Current position
                if let position = currentPosition {
                    PositionMarker(
                        position: position,
                        bounds: bounds,
                        frameSize: frameSize
                    )
                }
            } else {
                Text("No beacon data loaded")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func toScreenCoordinates(x: Double, y: Double) -> CGPoint {
        guard let bounds = bounds else {
            return CGPoint(x: frameSize.width / 2, y: frameSize.height / 2)
        }
        
        let rangeX = bounds.maxX - bounds.minX
        let rangeY = bounds.maxY - bounds.minY
        
        // Convert to 0-1 range, then to screen coordinates
        // Flip Y because SwiftUI Y increases downward
        let normalizedX = (x - bounds.minX) / rangeX
        let normalizedY = 1.0 - (y - bounds.minY) / rangeY
        
        return CGPoint(
            x: normalizedX * frameSize.width,
            y: normalizedY * frameSize.height
        )
    }
}

// MARK: - Grid Pattern

struct GridPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let gridSize: CGFloat = 20
        
        // Vertical lines
        var x: CGFloat = 0
        while x <= rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            x += gridSize
        }
        
        // Horizontal lines
        var y: CGFloat = 0
        while y <= rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
            y += gridSize
        }
        
        return path
    }
}

// MARK: - Beacon Marker

struct BeaconMarker: View {
    let beacon: Beacon
    let bounds: (minX: Double, maxX: Double, minY: Double, maxY: Double)
    let frameSize: CGSize
    let rssi: Double?
    
    private var position: CGPoint {
        let rangeX = bounds.maxX - bounds.minX
        let rangeY = bounds.maxY - bounds.minY
        
        let normalizedX = (beacon.x - bounds.minX) / rangeX
        let normalizedY = 1.0 - (beacon.y - bounds.minY) / rangeY
        
        return CGPoint(
            x: normalizedX * frameSize.width,
            y: normalizedY * frameSize.height
        )
    }
    
    private var isActive: Bool {
        rssi != nil
    }
    
    var body: some View {
        ZStack {
            // Signal rings for active beacons
            if isActive {
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                    .frame(width: 40, height: 40)
                
                Circle()
                    .stroke(Color.blue.opacity(0.2), lineWidth: 2)
                    .frame(width: 60, height: 60)
            }
            
            // Beacon icon
            Circle()
                .fill(isActive ? Color.blue : Color.gray)
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                )
            
            // Label
            VStack(spacing: 2) {
                Text(beacon.id)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isActive ? .primary : .secondary)
                
                if let rssi = rssi {
                    Text("\(Int(rssi)) dBm")
                        .font(.system(size: 8))
                        .foregroundStyle(.blue)
                }
            }
            .padding(4)
            .background(Color(.systemBackground).opacity(0.9))
            .cornerRadius(4)
            .offset(y: -30)
        }
        .position(position)
    }
}

// MARK: - Position Marker

struct PositionMarker: View {
    let position: PositionFix
    let bounds: (minX: Double, maxX: Double, minY: Double, maxY: Double)
    let frameSize: CGSize
    
    @State private var pulseScale: CGFloat = 1.0
    
    private var screenPosition: CGPoint {
        let rangeX = bounds.maxX - bounds.minX
        let rangeY = bounds.maxY - bounds.minY
        
        let normalizedX = (position.x - bounds.minX) / rangeX
        let normalizedY = 1.0 - (position.y - bounds.minY) / rangeY
        
        return CGPoint(
            x: normalizedX * frameSize.width,
            y: normalizedY * frameSize.height
        )
    }
    
    var body: some View {
        ZStack {
            // Pulsing outer circle
            Circle()
                .fill(Color.green.opacity(0.3))
                .frame(width: 30, height: 30)
                .scaleEffect(pulseScale)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: pulseScale
                )
            
            // Inner position dot
            Circle()
                .fill(Color.green)
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
            
            // Crosshair
            Path { path in
                path.move(to: CGPoint(x: -15, y: 0))
                path.addLine(to: CGPoint(x: -5, y: 0))
                path.move(to: CGPoint(x: 5, y: 0))
                path.addLine(to: CGPoint(x: 15, y: 0))
                path.move(to: CGPoint(x: 0, y: -15))
                path.addLine(to: CGPoint(x: 0, y: -5))
                path.move(to: CGPoint(x: 0, y: 5))
                path.addLine(to: CGPoint(x: 0, y: 15))
            }
            .stroke(Color.green, lineWidth: 1.5)
            
            // Label
            Text("YOU")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(Color.green)
                .cornerRadius(4)
                .offset(y: 25)
        }
        .position(screenPosition)
        .onAppear {
            pulseScale = 1.5
        }
    }
}

// MARK: - Preview

#Preview {
    VisualPositionView()
}
