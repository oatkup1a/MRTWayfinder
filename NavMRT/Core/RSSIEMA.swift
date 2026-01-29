final class RSSIEMA {
  private var state: [String: Double] = [:]
  private let alpha: Double
  init(alpha: Double = 0.3) { self.alpha = alpha }
    
  func update(id: String, rssi: Int) -> Double {
    let v = Double(rssi)
    let y = alpha * v + (1 - alpha) * (state[id] ?? v)
    state[id] = y
    return y
  }
    func reset() {
        state.removeAll()
    }
    
  var vector: [String: Double] { state }
}
