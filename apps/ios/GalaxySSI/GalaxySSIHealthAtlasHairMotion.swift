import Foundation

struct GalaxySSIHealthAtlasHairMotion {
  let renew: Double
  let bulb: Double
  let matrix: Double
  let club: Double
  let root: Double
  let tip: Double
  let lift: Double
  let drift: Double
  let opacity: Double
  init(step: Int, fraction: Double) {
    let t = fraction.isFinite ? min(1, max(0, fraction)) : 0, f = Self.ease(t)
    renew = step == 4 ? Self.ease((t - 0.45) / 0.55) : 0
    bulb = step == 2 ? 282 - 81 * f : step == 3 || step == 4 ? 201 + 81 * renew : 282
    matrix = step == 2 ? 1 - Self.ease(2 * t) : step == 3 || step == 4 ? renew : 1
    club = step == 2 ? f : step == 3 ? 1 : 0
    root = bulb - 8 - 10 * club
    tip = step == 0 ? 93 : step == 1 ? 93 - 19 * f : 74
    let release = Self.ease(t / 0.56)
    lift = 65 * release
    drift = 0.19 * lift + 10 * Self.ease((release - 0.78) / 0.22)
    opacity = 1 - Self.ease((t - 0.58) / 0.21)
  }
  static func ease(_ t: Double) -> Double { let f = t.isFinite ? min(1, max(0, t)) : 0; return f * f * (3 - 2 * f) }
  static func axis(_ y: Double) -> Double {
    let d = y - 132
    return 173 + 0.19 * d - (d < 0 ? 0.005 * d * d : 0)
  }
  var replacementRoot: Double { bulb - 8 }
  var replacementTip: Double { replacementRoot + (93 - replacementRoot) * renew }
}
