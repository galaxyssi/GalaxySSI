import Foundation

struct GalaxySSIHealthAtlasBarrierMotion {
  let chapter: Int
  let fraction: Double
  init(chapter: Int, fraction: Double) {
    self.chapter = min(4, max(0, chapter)); self.fraction = Self.safePhase(fraction)
  }
  private static func safePhase(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func ascent(_ t: Double) -> Double { 277 - 129 * safePhase(t) }
  static func escape(_ t: Double, disrupted: Bool, index: Int) -> Double {
    guard (0...5).contains(index) else { return 0 }
    let time = max(0, safePhase(t) - 0.05 * Double(index))
    let rate = disrupted ? 1.55 : index == 0 ? 0.98 : 0.36
    return min(1, time * rate)
  }
}
