import Foundation

enum GalaxySSIHealthAtlasSensorimotorMotion {
  typealias Point = GalaxySSIHealthAtlasSectionLesson.Point
  static let midReach = 0.52
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func window(_ t: Double, _ from: Double, _ to: Double) -> Double {
    min(1, max(0, (safe(t) - from) / (to - from)))
  }
  static func cycle(_ t: Double, _ delay: Double, _ period: Double) -> Double {
    max(0, safe(t) - delay).truncatingRemainder(dividingBy: period) / period
  }
  static func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }
  static func tissueTrace(_ t: Double) -> Double { window(t, 0.06, 0.86) }
  static func touch(_ t: Double) -> Double { window(t, 0.08, 0.59) }
  static func position(_ t: Double) -> Double { window(t, 0.22, 0.92) }
  static func planning(_ t: Double) -> Double { window(t, 0.04, 0.76) }
  static func reply(_ t: Double) -> Double { window(t, 0.28, 0.95) }
  static func preview(_ t: Double) -> Double { ease(window(t, 0.18, 0.93)) }
  static func command(_ t: Double) -> Double { window(t, 0.03, 0.72) }
  static func ongoingInput(_ t: Double) -> Double { cycle(t, 0, 0.46) }
  static func ongoingOutput(_ t: Double) -> Double { cycle(t, 0.15, 0.34) }
  static func reach(_ chapter: Int, _ t: Double) -> Double {
    switch chapter {
    case 3: return midReach * ease(window(t, 0.19, 1))
    case 4: return midReach + (1 - midReach) * ease(window(t, 0, 0.94))
    default: return 0
    }
  }
  static func finger(_ reach: Double) -> Point {
    .init(x: 218 + 56 * reach, y: 277 - 2 * reach - 22 * sin(.pi * reach))
  }
  struct Frame {
    let step: Int
    let t: Double
    let reach: Double
    let finger: Point
    let elbow: Point
    let position: Point
    let upperAngle: Double
    let lowerAngle: Double
    init(step: Int, fraction: Double) {
      self.step = step; t = safe(fraction)
      reach = GalaxySSIHealthAtlasSensorimotorMotion.reach(step, t)
      finger = GalaxySSIHealthAtlasSensorimotorMotion.finger(reach)
      let sx = 41.0, sy = 266.0, upper = 88.0, lower = 151.0
      let dx = finger.x - sx, dy = finger.y - sy, distance = hypot(dx, dy)
      // The bounded fingertip arc remains inside the reach of these two fixed segments.
      let along = (distance * distance + upper * upper - lower * lower) / (2 * distance)
      let bend = sqrt(max(0, upper * upper - along * along))
      let ex = sx + (dx * along - dy * bend) / distance
      let ey = sy + (dy * along + dx * bend) / distance
      elbow = .init(x: ex, y: ey)
      position = .init(x: sx + (ex - sx) * 0.69, y: sy + (ey - sy) * 0.69)
      upperAngle = atan2(ey - sy, ex - sx)
      lowerAngle = atan2(finger.y - ey, finger.x - ex)
    }
  }
}
