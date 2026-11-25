import Foundation

enum GalaxySSIHealthAtlasSinusMotion {
  private static func phase(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func interval(_ t: Double, _ start: Double, _ end: Double) -> Double {
    min(1, max(0, (phase(t) - start) / (end - start)))
  }
  static func ease(_ p: Double) -> Double { p * p * (3 - 2 * p) }
  static func highlight(_ t: Double, _ group: Int) -> Double {
    let p = interval(t, Double(group) * 0.21, Double(group) * 0.21 + 0.37)
    return max(0, sin(.pi * p))
  }
  static func heightReveal(_ t: Double) -> Double { ease(interval(t, 0.10, 0.88)) }
  static func secretion(_ t: Double, _ index: Int) -> Double {
    ease(interval(t, 0.07 + 0.21 * Double(index), 0.42 + 0.21 * Double(index)))
  }
  static func ciliumBend(_ t: Double, _ index: Int) -> Double {
    let angle = 2 * Double.pi * (2.65 * phase(t) - Double(index) * 0.09)
    return 0.35 + 0.65 * cos(angle)
  }
  static func ascent(_ t: Double, _ index: Int) -> Double { interval(t, 0.03 + 0.17 * Double(index), 0.62 + 0.17 * Double(index)) }
  static func exit(_ t: Double, _ index: Int) -> Double { ease(interval(t, 0.03 + 0.14 * Double(index), 0.77 + 0.10 * Double(index))) }
}
