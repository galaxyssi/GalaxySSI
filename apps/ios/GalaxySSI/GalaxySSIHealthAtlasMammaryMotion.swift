import Foundation

struct GalaxySSIHealthAtlasMammaryMotion {
  typealias Point = GalaxySSIHealthAtlasSectionLesson.Point
  struct Dot { let point: Point; let radius: Double }
  let squeeze: Double
  let radius: Double
  let amount: Double
  init(step: Int, fraction: Double) {
    let t = Self.safe(fraction)
    squeeze = step == 3 ? Self.ease((t - 0.32) / 0.68) : step == 4 ? 1 - Self.ease((t - 0.68) / 0.32) : 0
    radius = 88 - 15 * squeeze
    switch step {
    case 0: amount = 0.14
    case 1: amount = 0.14 + 0.24 * t
    case 2: amount = 0.38 + 0.62 * Self.ease(t)
    case 3: amount = 1
    default: amount = 1 - 0.65 * Self.ease(t)
    }
  }
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func ease(_ t: Double) -> Double { let f = safe(t); return f * f * (3 - 2 * f) }
  static func point(_ radius: Double, _ angle: Double) -> Point {
    let radians = angle * 0.017453293
    return Point(x: 138 + radius * cos(radians), y: 177 + radius * sin(radians))
  }
  func milkDot(_ i: Int) -> Dot? {
    let size = Self.safe((amount - Double(i) / 21) * 12)
    guard size > 0 else { return nil }
    let angle = Double(i) * 137.5 + 16, distance = radius * (0.37 + 0.09 * Double(i % 4)), p = Self.point(distance, angle)
    guard abs(p.y - 177) >= 11 else { return nil }
    return Dot(point: p, radius: (2.3 + 0.5 * Double(i % 3)) * size)
  }
  func signal(_ t: Double, index: Int) -> Dot {
    let t = Self.safe(t), travel = Self.safe((t - 0.065 * Double(index)) / 0.38)
    let reach = radius + 22 + (1 - travel) * (44 - Double(index) * 11)
    return Dot(point: Self.point(reach, 58 + 4 * Double(index)), radius: 3.5 * (1 - Self.ease((t - 0.4) / 0.36)))
  }
  static func flow(_ t: Double, index: Int) -> Point? {
    let travel = safe(t) * 1.52 - Double(index) * 0.115
    guard (0...1).contains(travel) else { return nil }
    return Point(x: 193 + (333 - 197) * travel, y: 177 + Double(index % 3 - 1) * 6.5 * (1 - 0.45 * travel))
  }
}
