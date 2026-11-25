import Foundation

struct GalaxySSIHealthAtlasLarynxMotion {
  let cycle: Double
  let opening: Double
  let vibration: Double
  let gap: Double
  let outgoing: Double
  let breath: Double
  let sound: Double
  init(step: Int, fraction: Double) {
    let t = Self.safe(fraction)
    cycle = 3 * t; opening = 0.5 - 0.5 * cos(2 * .pi * cycle)
    vibration = step == 2 ? Self.ease(t) : step == 3 ? 1 : step == 4 ? 1 - Self.ease(t * 2.5) : 0
    let release = Self.ease((t - 0.15) / 0.75)
    let posture = step == 0 ? 36 + 7 * sin(2 * .pi * t) : step == 1 ? 36 - 32 * Self.ease(t) : step == 4 ? 4 + 32 * release : 4
    gap = posture + vibration * (11 * opening - 3)
    outgoing = step == 2 ? Self.ease(t * 3) : step == 3 ? 1 : step == 4 ? vibration : 0
    breath = step == 0 ? sin(2 * .pi * t) : step == 4 ? Self.ease((t - 0.4) / 0.32) * (1 - Self.ease((t - 0.75) / 0.25)) * 0.75 : 0
    sound = step == 3 ? Self.ease(t * 6) : step == 4 ? vibration : 0
  }
  var above: Double { outgoing * (0.15 + 0.85 * opening) * min(1, gap / 8) }
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func ease(_ t: Double) -> Double { let p = safe(t); return p * p * (3 - 2 * p) }
  static func unit(_ t: Double) -> Double { t.isFinite ? (t.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) : 0 }
  struct Flow { let x: Double; let y: Double; let direction: Double; let alpha: Int }
  static func airflow(travel: Double, index: Int, up: Bool, below: Double, above: Double) -> Flow? {
    let direction = up ? -1.0 : 1, p = unit(travel + Double(index) / 5)
    let y = up ? 337 - 88 * p : 249 + 88 * p, strength = y > 278 ? below : above
    let fade = min(1, min(p * 9, min((1 - p) * 9, abs(y - 278) / 9))), opacity = strength * fade
    guard opacity > 0 else { return nil }
    return Flow(x: 180 + Double(index % 3 - 1) * min(5, abs(y - 278) * 0.24), y: y, direction: direction, alpha: Int(255 * safe(opacity)))
  }
  struct Pulse { let y: Double; let halfWidth: Double; let alpha: Int }
  static func acoustic(cycle: Double, index: Int, strength: Double) -> Pulse {
    let age = (unit(cycle - 0.25) + Double(index)) / 2, y = 270 - 21 * age
    let fade = min(1, min(age * 8, (1 - age) * 5))
    return Pulse(y: y, halfWidth: 4 + 24 * age, alpha: Int(255 * safe(strength * fade)))
  }
}
