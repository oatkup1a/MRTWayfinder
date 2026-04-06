import SwiftUI
import Combine

/// A specialized view for POC turn-by-turn navigation testing
/// Route: Point A (0,0.5) → Junction (4,0.5) → Point B (5,5)
/// Instructions: Walk 4.5m straight → Turn left 90° → Walk 4.5m straight
struct POCNavigationView: View {
    @StateObject private var navigationEngine = POCNavigationEngine()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            Text("POC Turn-by-Turn Navigation")
                .font(.title2.bold())
                .padding(.top)
            
            // Route Overview
            VStack(alignment: .leading, spacing: 8) {
                Text("Route Overview")
                    .font(.headline)
                
                Text("From: Point A (Start)")
                Text("To: Point B (Destination)")
                Text("Total Distance: ~9.0 meters")
                Text("Hallway Width: 1 meter")
                Text("Turns: 1 left turn at Junction")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Spacer()
            
            // Current Instruction
            VStack(spacing: 16) {
                Text("Current Instruction")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(navigationEngine.currentInstruction)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.1))
                    )
                
                if let distance = navigationEngine.distanceToNext {
                    Text(String(format: "%.1f meters remaining", distance))
                        .font(.headline)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)
            
            // Progress
            VStack(spacing: 8) {
                HStack {
                    Text("Step \(navigationEngine.currentStep) of \(navigationEngine.totalSteps)")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(navigationEngine.progress * 100))%")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                ProgressView(value: navigationEngine.progress)
                    .tint(.accentColor)
            }
            .padding(.horizontal)
            
            Spacer()
            
            // Controls
            VStack(spacing: 12) {
                if !navigationEngine.isNavigating {
                    Button {
                        navigationEngine.startNavigation()
                    } label: {
                        Text("Start Navigation")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                } else {
                    HStack(spacing: 12) {
                        Button {
                            navigationEngine.previousStep()
                        } label: {
                            Label("Previous", systemImage: "chevron.left")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                        }
                        .disabled(!navigationEngine.canGoPrevious)
                        
                        Button {
                            navigationEngine.nextStep()
                        } label: {
                            Label("Next", systemImage: "chevron.right")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .disabled(!navigationEngine.canGoNext)
                    }
                    
                    Button {
                        navigationEngine.stopNavigation()
                    } label: {
                        Text("Stop Navigation")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
                
                Button {
                    navigationEngine.speak(navigationEngine.currentInstruction)
                } label: {
                    Label("Repeat Instruction", systemImage: "speaker.wave.2")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle("POC Navigation")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Navigation Complete", isPresented: $navigationEngine.showCompletionAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("You have successfully arrived at Point B!")
        }
    }
}

// MARK: - Navigation Engine

@MainActor
class POCNavigationEngine: ObservableObject {
    @Published var currentInstruction: String = "Press Start to begin navigation"
    @Published var currentStep: Int = 0
    @Published var totalSteps: Int = 0
    @Published var distanceToNext: Double?
    @Published var isNavigating: Bool = false
    @Published var showCompletionAlert: Bool = false
    
    private let speech = Speech()
    private var instructions: [POCNavigationInstructions.Instruction] = []
    
    var progress: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(currentStep) / Double(totalSteps)
    }
    
    var canGoNext: Bool {
        currentStep < totalSteps
    }
    
    var canGoPrevious: Bool {
        currentStep > 1
    }
    
    init() {
        setupInstructions()
    }
    
    private func setupInstructions() {
        // Create POC path: A → Mid1 → Junction → Mid2 → B
        let path = [
            Graph.Node(id: "A", x: 0.0, y: 0.5, floor: "Ground", type: "start"),
            Graph.Node(id: "Mid1", x: 2.0, y: 0.5, floor: "Ground", type: "waypoint"),
            Graph.Node(id: "Junction", x: 4.0, y: 0.5, floor: "Ground", type: "junction"),
            Graph.Node(id: "Mid2", x: 4.5, y: 3.0, floor: "Ground", type: "waypoint"),
            Graph.Node(id: "B", x: 5.0, y: 5.0, floor: "Ground", type: "destination")
        ]
        
        instructions = POCNavigationInstructions.generateInstructions(
            for: path,
            startName: "Point A",
            destinationName: "Point B"
        )
        
        totalSteps = instructions.count
    }
    
    func startNavigation() {
        isNavigating = true
        currentStep = 1
        updateCurrentInstruction()
        speak(currentInstruction)
    }
    
    func stopNavigation() {
        isNavigating = false
        currentStep = 0
        currentInstruction = "Press Start to begin navigation"
        distanceToNext = nil
    }
    
    func nextStep() {
        guard canGoNext else { return }
        currentStep += 1
        updateCurrentInstruction()
        speak(currentInstruction)
        
        // Check if completed
        if currentStep == totalSteps {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showCompletionAlert = true
            }
        }
    }
    
    func previousStep() {
        guard canGoPrevious else { return }
        currentStep -= 1
        updateCurrentInstruction()
        speak(currentInstruction)
    }
    
    private func updateCurrentInstruction() {
        guard currentStep > 0 && currentStep <= instructions.count else {
            currentInstruction = "No instruction available"
            distanceToNext = nil
            return
        }
        
        let instruction = instructions[currentStep - 1]
        currentInstruction = instruction.spokenText
        distanceToNext = instruction.distance
    }
    
    func speak(_ text: String) {
        speech.say(text)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        POCNavigationView()
    }
}
