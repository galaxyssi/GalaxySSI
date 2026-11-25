import Foundation

enum GalaxySSIHealthAtlasCerebellumMotion {
  typealias Point = GalaxySSIHealthAtlasSectionLesson.Point
  struct Arm { let elbow: Point; let upperAngle: Double; let lowerAngle: Double }
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  private static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
  static func reachProgress(chapter: Int, phase: Double) -> Double {
    let t = safe(phase)
    switch chapter {
    case 0: return 0
    case 1: return 0.36 * smooth(t)
    case 2: return 0.36 + 0.18 * smooth(t)
    case 3: return 0.54 + 0.46 * smooth(t)
    default:
      if t < 0.18 { return 1 - smooth(t / 0.18) }
      if t < 0.48 { return smooth((t - 0.18) / 0.30) }
      if t < 0.66 { return 1 - smooth((t - 0.48) / 0.18) }
      return smooth((t - 0.66) / 0.34)
    }
  }
  static func laterDeviation(_ time: Double) -> Double {
    let t = safe(time); return t < 0.18 ? 1 : t < 0.66 ? 0.67 : 0.32
  }
  static func point(_ progress: Double, deviation: Double) -> Point {
    let p = safe(progress), d = deviation.isFinite ? deviation : 0, arc = sin(.pi * p)
    return Point(x: 212 + (318 - 212) * p, y: 187 + (162 - 187) * p - 24 * arc + 22 * d * arc * arc)
  }
  static func arm(_ finger: Point) -> Arm? {
    let dx = finger.x - 164, dy = finger.y - 243, distance = hypot(dx, dy)
    guard distance.isFinite, distance > 0 else { return nil }
    let along = (distance * distance + 81 * 81 - 98 * 98) / (2 * distance), bend = sqrt(max(0, 81 * 81 - along * along))
    let elbow = Point(x: 164 + (along * dx - bend * dy) / distance, y: 243 + (along * dy + bend * dx) / distance)
    return Arm(elbow: elbow, upperAngle: atan2(elbow.y - 243, elbow.x - 164) * (180 / .pi), lowerAngle: atan2(finger.y - elbow.y, finger.x - elbow.x) * (180 / .pi))
  }
  static func cueTravel(_ time: Double, delay: Double) -> Double? {
    let t = safe(time)
    guard delay.isFinite, delay >= 0, delay < 1, t >= delay else { return nil }
    return min(1, max(0, (t - delay) / (1 - delay)))
  }
}
