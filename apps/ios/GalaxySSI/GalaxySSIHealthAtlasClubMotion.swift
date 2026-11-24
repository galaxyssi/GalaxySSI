import Foundation

enum GalaxySSIHealthAtlasClubMotion {
  static func ease(_ t: Double, _ start: Double, _ end: Double) -> Double {
    let phase = t.isFinite ? min(1, max(0, t)) : 0
    let f = min(1, max(0, (phase - start) / (end - start)))
    return f * f * (3 - 2 * f)
  }
  static func locate(_ t: Double) -> Double { ease(t, 0.06, 0.88) }
  static func cilia(_ t: Double) -> Double { ease(t, 0.08, 0.87) }
  static func dock(_ t: Double) -> Double { ease(t, 0.04, 0.50) }
  static func release(_ t: Double, _ index: Int) -> Double { ease(t, 0.49 + 0.055 * Double(index), 0.80 + 0.060 * Double(index)) }
  static func spread(_ t: Double, _ index: Int) -> Double { ease(t, 0.08 + 0.021 * Double(index), 0.75 + 0.028 * Double(index)) }
  static func expand(_ t: Double) -> Double { ease(t, 0.04, 0.65) }
  static func divide(_ t: Double) -> Double { ease(t, 0.24, 0.68) }
  static func differentiate(_ t: Double) -> Double { ease(t, 0.52, 0.94) }
}
