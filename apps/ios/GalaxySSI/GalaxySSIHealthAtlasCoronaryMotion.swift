import Foundation

enum GalaxySSIHealthAtlasCoronaryMotion {
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1,max(0,t)) : 0 }
  static func squeeze(step: Int, t: Double) -> Double {
    let t = safe(t), ease = t * t * (3 - 2 * t)
    return step == 2 ? ease : step == 3 ? 1 - ease : 0
  }
  static func crowding(_ squeeze: Double) -> Double { 1 - 0.57 * squeeze }
  static func leftFlow(_ squeeze: Double) -> Double { 1 - 0.58 * squeeze }
  static func wallTime(step: Int, t: Double) -> Double {
    let t = safe(t), delta = 0.64 * t * t * t * (1 - 0.5 * t)
    return step == 2 ? 1 + t - delta : step == 3 ? 1.68 + 0.36 * t + delta : t
  }
  struct Stream { let position: Double; let size: Double; let alpha: Int }
  static func stream(time: Double, speed: Double, index: Int, count: Int, strength: Double, span: Double, length: Double) -> Stream? {
    guard time.isFinite, speed.isFinite, length.isFinite, length > 0, count > 0, index >= 0, index < count,
      (0...1).contains(strength), (0...1).contains(span) else { return nil }
    let travel = time * speed + Double(index) / Double(count)
    guard travel.isFinite else { return nil }
    let u = travel - floor(travel)
    return .init(position: u * span,size: min(5.8,length * 0.19),alpha: Int(255 * strength * min(1,min(8 * u,8 * (1 - u)))))
  }
  struct Oxygen { let x: Double; let y: Double; let alpha: Int }
  static func oxygen(time: Double, index: Int, crowding: Double) -> Oxygen {
    let u = (time * 1.35 + Double(index) * 0.26).truncatingRemainder(dividingBy: 1), side = index % 2 == 0 ? -1.0 : 1.0
    return .init(x: 149 + Double(index) * 20 + 5 * u,y: 290 + side * (8 * crowding + 19 * u),
      alpha: Int(255 * (1 - abs(2 * u - 1)) * crowding))
  }
}
