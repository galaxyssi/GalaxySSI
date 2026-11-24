import Foundation

enum GalaxySSIHealthAtlasMesangialMotion {
  static let loopHinge = 137.0
  static func smooth(_ f: Double) -> Double { f * f * (3 - 2 * f) }
  static func loopScale(_ tension: Double) -> Double { 1 - 0.13 * tension }
  enum Stage: Int {
    case locate, boundary, support, uptake, tension
    func progress(_ value: Double) -> Double {
      let f = value.isFinite ? min(1, max(0, value)) : 0
      switch self {
      case .locate: return GalaxySSIHealthAtlasMesangialMotion.smooth(f)
      case .boundary: return 1 - (1 - f) * (1 - f)
      case .support: return f * f
      case .uptake: return f
      case .tension: return f < 0.7 ? GalaxySSIHealthAtlasMesangialMotion.smooth(f / 0.7) : GalaxySSIHealthAtlasMesangialMotion.smooth((1 - f) / 0.3)
      }
    }
  }
  static func fiberReach(_ f: Double, _ index: Int) -> Double {
    0.4 + 0.6 * min(1, max(0, (f - Double(index) * 0.055) / 0.835))
  }
  static func boundaryLight(_ f: Double) -> Double { min(1, max(0, (f - 0.35) / 0.65)) }
  struct Uptake { let travel: Double; let radius: Double; let size: Double }
  static func uptake(_ f: Double) -> Uptake {
    .init(travel: min(1, max(0, f / 0.72)),
      radius: 4 + 1.5 * min(1, max(0, (f - 0.48) / 0.24)),
      size: 1 - 0.52 * min(1, max(0, (f - 0.72) / 0.28)))
  }
}
