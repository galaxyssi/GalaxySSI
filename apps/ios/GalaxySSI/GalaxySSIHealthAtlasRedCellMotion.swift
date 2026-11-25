import Foundation

enum GalaxySSIHealthAtlasRedCellMotion {
  typealias Point = GalaxySSIHealthAtlasSectionLesson.Point
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func ease(_ value: Double) -> Double { let f = safe(value); return f * f * (3 - 2 * f) }
  static func mix(_ from: Double, _ to: Double, _ f: Double) -> Double { from + (to - from) * f }
  static func peripheralFlow(_ t: Double, diffuse: Bool) -> Double { (safe(t) + (diffuse ? 1 : 0)) * 0.5 }
  static func cellX(_ t: Double, diffuse: Bool) -> Double { 166 + 58 * (peripheralFlow(t, diffuse: diffuse) - 0.5) }
  static func lungOxygen(_ t: Double, index: Int) -> Point {
    let t = safe(t), f = ease((t - 0.09 * Double(index)) / 0.77), x = 141 + 49 * t
    return Point(x: mix(116 + 42 * Double(index), x + 10 * Double(index - 1), f),
      y: mix(Double(113 - 12 * (index % 2)), Double(208 - 4 * (index % 2)), f))
  }
  static func peripheralOxygen(_ t: Double, index: Int, diffuse: Bool) -> Point {
    let t = safe(t), lane = Double(index - 1), plasmaY = Double(173 + 3 * (index % 2))
    if diffuse {
      let f = ease((t - 0.09 * Double(index)) / 0.78)
      return Point(x: mix(166 + 20 * lane, 86 + 94 * Double(index), f * f), y: mix(plasmaY, 268, f))
    }
    let f = ease((t - 0.09 * Double(index)) / 0.77)
    return Point(x: cellX(t, diffuse: false) + mix(10 * lane, 20 * lane, f), y: mix(Double(146 + 4 * (index % 2)), plasmaY, f))
  }
}
