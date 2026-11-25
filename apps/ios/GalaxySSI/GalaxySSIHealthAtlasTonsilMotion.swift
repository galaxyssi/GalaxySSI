import Foundation

enum GalaxySSIHealthAtlasTonsilMotion {
  static func ease(_ t: Double, _ start: Double, _ end: Double) -> Double {
    let phase = t.isFinite ? min(1, max(0, t)) : 0
    let p = min(1, max(0, (phase - start) / (end - start)))
    return p * p * (3 - 2 * p)
  }
  static func adenoidFocus(_ t: Double) -> Double { 1 - ease(t, 0.18, 0.55) }
  static func palatineFocus(_ t: Double) -> Double { ease(t, 0.32, 0.69) }
  static func cryptScale(_ t: Double) -> Double { 1 + 0.18 * ease(t, 0.08, 0.80) }
  static func cryptTrace(_ t: Double) -> Double { ease(t, 0.18, 0.88) }
  static func encounter(_ t: Double, lag: Double = 0) -> Double { ease(t - lag, 0.06, 0.87) }
  static func uptake(_ t: Double) -> Double { ease(t, 0.24, 0.83) }
  static func contact(_ t: Double) -> Double { ease(t, 0.10, 0.66) }
  static func signal(_ t: Double) -> Double { ease(t, 0.57, 0.86) }
}
