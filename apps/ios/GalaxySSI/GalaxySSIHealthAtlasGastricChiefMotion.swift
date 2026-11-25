import Foundation

enum GalaxySSIHealthAtlasGastricChiefMotion {
  static func ease(_ t: Double, _ start: Double, _ end: Double) -> Double {
    let phase = t.isFinite ? min(1, max(0, t)) : 0
    let f = min(1, max(0, (phase - start) / (end - start)))
    return f * f * (3 - 2 * f)
  }
  static func locate(_ t: Double) -> Double { ease(t, 0.06, 0.86) }
  static func pack(_ t: Double, _ index: Int) -> Double { ease(t, 0.09 + 0.09 * Double(index), 0.64 + 0.10 * Double(index)) }
  static func dock(_ t: Double) -> Double { ease(t, 0.03, 0.53) }
  static func release(_ t: Double, _ index: Int) -> Double { ease(t, 0.46 + 0.055 * Double(index), 0.80 + 0.06 * Double(index)) }
  static func acidFlow(_ t: Double) -> Double { ease(t, 0.02, 0.60) }
  static func activate(_ t: Double, _ index: Int) -> Double { ease(t, 0.32 + 0.19 * Double(index), 0.72 + 0.22 * Double(index)) }
  static func approach(_ t: Double, _ index: Int) -> Double { ease(t, 0.02 + 0.23 * Double(index), 0.40 + 0.23 * Double(index)) }
  static func split(_ t: Double, _ index: Int) -> Double { ease(t, 0.40 + 0.23 * Double(index), 0.71 + 0.26 * Double(index)) }
}
