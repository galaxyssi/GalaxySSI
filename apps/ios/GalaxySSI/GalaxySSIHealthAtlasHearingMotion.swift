import Foundation
import CoreGraphics

struct GalaxySSIHealthAtlasHearingMotion {
  enum Stage: Int, CaseIterable { case sound, middleEar, cochlea, hairCell, nerve }
  let stage: Stage
  let fraction: Double
  init(chapter: Int, fraction: Double) {
    stage = Stage(rawValue: chapter) ?? .sound
    self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
  }
  static func oscillation(_ progress: Double, delay: Double = 0) -> Double {
    guard progress.isFinite, delay.isFinite else { return 0 }
    return sin((progress * 3 - delay) * 2 * .pi)
  }
  static func packet(_ position: Double, progress: Double) -> Double {
    guard position.isFinite, progress.isFinite else { return 0 }
    let center = progress * 0.92
    let envelope = min(1, max(0, 1 - abs(position - center) / 0.42))
    return envelope * oscillation(progress, delay: position * 2.8)
  }
  static func relativeChannelOpening(_ towardTallest: Double) -> Double {
    let t = towardTallest.isFinite ? towardTallest : 0
    return 0.19 + 0.76 * min(1, max(0, t)) + 0.16 * min(0, max(-1, t))
  }
  static func influence(_ value: Double, center: Double, radius: Double) -> Double {
    guard value.isFinite, center.isFinite, radius.isFinite, radius > 0 else { return 0 }
    return min(1, max(0, 1 - abs(value - center) / radius))
  }
  var motion: Double { Self.oscillation(fraction) }
  var meshAsset: String? {
    stage == .middleEar ? "HealthAtlasEarSection" : stage == .hairCell ? "HealthAtlasSensoryCochlearHair" : nil
  }
  var mesh: [CGPoint] {
    guard meshAsset != nil else { return [] }
    return (0...28).flatMap { row in (0...28).map { column in
      let x = Double(column) / 28, y = Double(row) / 28
      if stage == .middleEar {
        let drum = Self.influence(x, center: 0.444, radius: 0.058) * Self.influence(y, center: 0.51, radius: 0.17)
        let chain = Self.influence(x, center: 0.56, radius: 0.15) * Self.influence(y, center: 0.45, radius: 0.14)
        return CGPoint(x: 16 + 312 * x + motion * (5.5 * drum + 4 * chain), y: 58 + 208 * y)
      }
      let taper = min(1, max(0, (0.29 - y) / 0.14))
      let shift = 8 * motion * taper * Self.influence(x, center: 0.46, radius: 0.34)
      return CGPoint(x: 12 + 145 * x + shift, y: 27 + 240 * y)
    }}
  }
  var soundDistances: [Double] { (0..<6).map { loop(fraction * 1.7 + Double($0) / 6) } }
  var nervePositions: [Double] { (0..<4).map { loop(fraction * 1.8 + Double($0) / 4) } }
  var cochleaPosition: Double { loop(fraction * 1.14) }
  private func loop(_ value: Double) -> Double { value - value.rounded(.towardZero) }
}
