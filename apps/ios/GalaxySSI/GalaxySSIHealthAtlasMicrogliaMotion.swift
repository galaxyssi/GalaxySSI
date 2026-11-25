import Foundation

enum GalaxySSIHealthAtlasMicrogliaMotion {
  static func phase(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func ease(_ t: Double, _ start: Double, _ end: Double) -> Double {
    let f = min(1, max(0, (t-start)/(end-start)))
    return f*f*(3-2*f)
  }
}
