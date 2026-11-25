import Foundation

struct GalaxySSIHealthAtlasBreathingMotion {
  enum Stage: Int, CaseIterable {
    case inhale, reachAlveolus, diffuse, perfuse, exhale
    func closeUp(_ fraction: Double) -> Double {
      switch self {
      case .inhale: return 0
      case .reachAlveolus: return ease((fraction - 0.12) / 0.62)
      case .diffuse, .perfuse: return 1
      case .exhale: return 1 - ease(fraction / 0.35)
      }
    }
    func expansion(_ fraction: Double) -> Double {
      switch self {
      case .inhale: return ease(fraction)
      case .exhale: return 1 - ease(fraction)
      default: return 1
      }
    }
    private func ease(_ value: Double) -> Double {
      let x = value.isFinite ? min(1, max(0, value)) : 0
      return x * x * (3 - 2 * x)
    }
  }
  let stage: Stage
  let fraction: Double
  let phase: Double
  init(chapter: Int, fraction: Double, phase: Double) {
    stage = Stage(rawValue: chapter) ?? .inhale
    self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
    self.phase = GalaxySSIHealthAtlasGasExchange.phase(phase)
  }
  var zoom: Double { stage.closeUp(fraction) }
  var expansion: Double { stage.expansion(fraction) }
  var exhales: Bool { stage == .exhale }
  var detailSpan: Double { 54 + 232 * zoom }
  var detailX: Double { 214 - 183 * zoom }
  var detailY: Double { 175 - 157 * zoom }
  static func loop(_ value: Double) -> Double {
    guard value.isFinite else { return 0 }
    return value - value.rounded(.towardZero)
  }
  var airPositions: [Double] {
    (0..<4).map { let t = Self.loop(phase * 6 + Double($0) / 4); return exhales ? 1 - t : t }
  }
  var bloodPositions: [Double] { (0..<7).map { Self.loop(phase * 3 + Double($0) / 7) } }
  var diffusionPositions: [Double] { (0..<3).map { Self.loop(phase * 7 + Double($0) / 3) } }
}
