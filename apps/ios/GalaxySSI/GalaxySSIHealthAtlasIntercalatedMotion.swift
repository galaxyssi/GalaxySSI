import Foundation

enum GalaxySSIHealthAtlasIntercalatedMotion {
  enum Stage: Int {
    case orientation, protonSecretion, bicarbonateReturn, luminalBuffers, acidExcretion
    func progress(_ value: Double) -> Double {
      let f = value.isFinite ? min(1, max(0, value)) : 0
      switch self {
      case .orientation: return f * f * (3 - 2 * f)
      case .protonSecretion: return f * f
      case .bicarbonateReturn: return f * (2 - f)
      case .luminalBuffers: return min(1, max(0, (f - 0.07) / 0.86))
      case .acidExcretion: return f
      }
    }
  }
  static func mix(_ from: Double, _ to: Double, _ f: Double) -> Double { from + (to - from) * f }
  static func phosphateDelay(_ f: Double) -> Double { min(1, max(0, (f - 0.14) / 0.86)) }
  static func protonPhase(_ f: Double, _ index: Int) -> Double {
    (f * 1.22 + Double(index) * 0.31 + 0.08).truncatingRemainder(dividingBy: 1)
  }
  static func basePhase(_ f: Double, _ index: Int) -> Double {
    (f * 0.91 + Double(index) * 0.49 + 0.12).truncatingRemainder(dividingBy: 1)
  }
}
