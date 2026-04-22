import Foundation

/// Turn-by-turn navigation instruction generator for POC testing environment
struct POCNavigationInstructions {
    
    /// Represents a single navigation instruction
    struct Instruction {
        let action: Action
        let distance: Double?
        let targetNode: String
        let spokenText: String
        let displayText: String
        
        enum Action {
            case start
            case walkStraight
            case turnLeft
            case turnRight
            case arrive
        }
    }
    
    /// Generate turn-by-turn instructions for the POC route from A to B
    /// Route: Walk 4.5m east → Turn left → Walk 4.5m north
    static func generateInstructions(
        for path: [Graph.Node],
        startName: String = "Point A",
        destinationName: String = "Point B"
    ) -> [Instruction] {
        guard !path.isEmpty else { return [] }
        
        var instructions: [Instruction] = []
        
        // Starting instruction
        if let firstNode = path.first {
            instructions.append(
                Instruction(
                    action: .start,
                    distance: nil,
                    targetNode: firstNode.id,
                    spokenText: "Starting navigation from \(startName) to \(destinationName). Begin walking straight ahead.",
                    displayText: "Start at \(startName)"
                )
            )
        }
        
        // Generate instructions for each segment
        for i in 0..<(path.count - 1) {
            let current = path[i]
            let next = path[i + 1]
            
            let distance = calculateDistance(from: current, to: next)
            
            // Check if there's a turn at this node
            if i > 0 {
                let previous = path[i - 1]
                if let turnInstruction = generateTurnInstruction(
                    from: previous,
                    through: current,
                    to: next,
                    distance: distance
                ) {
                    instructions.append(turnInstruction)
                    continue
                }
            }
            
            // Straight walking instruction
            let walkInstruction = Instruction(
                action: .walkStraight,
                distance: distance,
                targetNode: next.id,
                spokenText: String(format: "Walk straight for %.1f meters", distance),
                displayText: String(format: "Walk %.1fm straight", distance)
            )
            instructions.append(walkInstruction)
        }
        
        // Arrival instruction
        if let lastNode = path.last {
            instructions.append(
                Instruction(
                    action: .arrive,
                    distance: nil,
                    targetNode: lastNode.id,
                    spokenText: "You have arrived at \(destinationName).",
                    displayText: "Arrived at \(destinationName)"
                )
            )
        }
        
        return instructions
    }
    
    /// Generate proximity-based instruction for navigation progress
    static func generateProximityInstruction(
        currentPosition: (x: Double, y: Double),
        targetNode: Graph.Node,
        instruction: Instruction
    ) -> String {
        let distance = sqrt(
            pow(targetNode.x - currentPosition.x, 2) +
            pow(targetNode.y - currentPosition.y, 2)
        )
        
        switch instruction.action {
        case .walkStraight:
            if distance > 3.0 {
                return String(format: "Continue straight. %.1f meters remaining.", distance)
            } else if distance > 1.5 {
                return String(format: "%.1f meters to next turn.", distance)
            } else {
                return "Approaching turn point."
            }
            
        case .turnLeft, .turnRight:
            if distance < 0.5 {
                return instruction.spokenText
            } else {
                return String(format: "%.1f meters to turn.", distance)
            }
            
        case .arrive:
            if distance < 1.5 {
                return "You are arriving at your destination."
            } else {
                return String(format: "%.1f meters to destination.", distance)
            }
            
        case .start:
            return instruction.spokenText
        }
    }
    
    /// Calculate distance between two nodes
    private static func calculateDistance(from: Graph.Node, to: Graph.Node) -> Double {
        let dx = to.x - from.x
        let dy = to.y - from.y
        return sqrt(dx * dx + dy * dy)
    }
    
    /// Determine if there's a turn and generate appropriate instruction
    private static func generateTurnInstruction(
        from previous: Graph.Node,
        through current: Graph.Node,
        to next: Graph.Node,
        distance: Double
    ) -> Instruction? {
        // Calculate vectors
        let v1x = current.x - previous.x
        let v1y = current.y - previous.y
        let v2x = next.x - current.x
        let v2y = next.y - current.y
        
        // Normalize vectors
        let mag1 = sqrt(v1x * v1x + v1y * v1y)
        let mag2 = sqrt(v2x * v2x + v2y * v2y)
        
        guard mag1 > 0.01 && mag2 > 0.01 else { return nil }
        
        let n1x = v1x / mag1
        let n1y = v1y / mag1
        let n2x = v2x / mag2
        let n2y = v2y / mag2
        
        // Calculate angle using dot product
        let dot = n1x * n2x + n1y * n2y
        let angle = acos(min(max(dot, -1.0), 1.0)) * 180.0 / .pi
        
        // If angle is small (< 30 degrees), it's straight
        guard angle > 30 else { return nil }
        
        // Calculate cross product to determine left or right
        let cross = n1x * n2y - n1y * n2x
        
        let action: Instruction.Action
        let direction: String
        
        if cross > 0 {
            action = .turnLeft
            direction = "left"
        } else {
            action = .turnRight
            direction = "right"
        }
        
        let angleDesc = angle > 80 && angle < 100 ? "90 degrees" : String(format: "%.0f degrees", angle)
        
        return Instruction(
            action: action,
            distance: distance,
            targetNode: next.id,
            spokenText: "Turn \(direction) \(angleDesc), then walk \(String(format: "%.1f", distance)) meters.",
            displayText: "Turn \(direction) ↑ \(String(format: "%.1fm", distance))"
        )
    }
    
    /// Get detailed POC-specific instructions
    static func getPOCRouteDescription() -> String {
        """
        POC Test Route: Point A to Point B
        
        1. Start at Point A (0.0, 0.5)
        2. Walk straight for 4.5 meters along the 1-meter wide hallway
        3. At the Junction (4.0, 0.5), turn left 90 degrees
        4. Walk straight for 4.5 meters along the 1-meter wide hallway
        5. Arrive at Point B (5.0, 5.0)
        
        Total distance: Approximately 9 meters
        Total turns: 1 left turn
        Hallway width: 1 meter
        """
    }
}

// MARK: - Enhanced POC Journey Planner

extension StationJourneyPlanner {
    
    /// Generate detailed POC-specific journey steps
    static func buildPOCPlan(
        path: [Graph.Node]
    ) -> StationJourneyPlan? {
        guard path.count >= 2 else { return nil }
        
        let instructions = POCNavigationInstructions.generateInstructions(for: path)
        
        // For POC, create a simplified plan
        return StationJourneyPlan(
            startStation: "Point A - Start",
            destinationStation: "Point B - Destination",
            platformSide: "straight ahead",
            boardingHint: "along the hallway",
            stopCount: instructions.count - 2, // Exclude start and arrive
            destinationExitGate: "Point B"
        )
    }
    
    /// Generate spoken instructions for POC navigation
    static func pocDetailedSteps() -> [String] {
        [
            "Starting navigation from Point A to Point B.",
            "Walk straight ahead along the hallway for 2 meters.",
            "Continue straight. You are halfway to the junction.",
            "Continue straight for 2 more meters.",
            "You are approaching the junction. Prepare to turn left.",
            "Turn left 90 degrees at the junction.",
            "Now walk straight ahead for 2.5 meters.",
            "Continue straight. You are halfway to your destination.",
            "Continue straight for 2 more meters.",
            "You are approaching Point B.",
            "You have arrived at Point B. Navigation complete."
        ]
    }
}
