import Foundation

struct GalaxySSIHealthAtlasVenousMotion {
  let squeeze: Double
  let proximalOpen: Double
  let distalOpen: Double
  init(step: Int, fraction: Double) {
    let t = Self.safe(fraction)
    switch step {
    case 1: squeeze = 0.82 * Self.ease(t)
    case 2: squeeze = 0.82 + 0.18 * Self.ease(t)
    case 3: squeeze = 1
    case 4: squeeze = 1 - Self.ease(t)
    default: squeeze = 0
    }
    switch step {
    case 1: proximalOpen = Self.ease(t, from: 0.32, to: 0.86)
    case 2, 3: proximalOpen = 1
    case 4: proximalOpen = 1 - Self.ease(t, from: 0, to: 0.29)
    default: proximalOpen = 0
    }
    switch step {
    case 1: distalOpen = 1 - Self.ease(t, from: 0, to: 0.32)
    case 2, 3: distalOpen = 0
    case 4: distalOpen = Self.ease(t, from: 0.29, to: 0.62)
    default: distalOpen = 1
    }
  }
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func ease(_ t: Double, from: Double = 0, to: Double = 1) -> Double {
    guard from.isFinite, to.isFinite, to > from else { return 0 }
    let u = min(1, max(0, (safe(t) - from) / (to - from)))
    return u * u * (3 - 2 * u)
  }
  static func ringAlpha(_ time: Double) -> Int {
    let t = safe(time)
    return Int(213 * 4 * t * (1 - t))
  }
  static func flow(_ t: Double, index: Int, from: Double, to: Double, strength: Double = 1) -> (y: Double, alpha: Int) {
    let p = (2 * safe(t) + Double(index) / 3).truncatingRemainder(dividingBy: 1)
    return (from + (to - from) * p, Int(255 * safe(strength) * min(1, min(6 * p, 6 * (1 - p)))))
  }
}
