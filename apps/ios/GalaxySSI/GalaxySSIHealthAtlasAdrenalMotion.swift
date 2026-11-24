import Foundation

enum GalaxySSIHealthAtlasAdrenalMotion {
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1,max(0,t)) : 0 }
  static func ease(_ t: Double) -> Double { let f = safe(t); return f * f * (3 - 2 * f) }
  static func alpha(_ value: Double) -> Int { Int(255 * safe(value)) }
  struct Locator { let outer: Bool; let end: Double; let alpha: Double }
  static func locator(_ t: Double) -> Locator {
    let t = safe(t), outer = t < 0.47, fraction = outer ? t / 0.47 : (t - 0.47) / 0.53
    return .init(outer: outer,end: ease(fraction),alpha: outer ? ease((1 - fraction) * 4) : 1)
  }
  static func pulse(_ t: Double, index: Int) -> Double? {
    let f = (safe(t) - 0.14 * Double(index)) / 0.68
    return (0...1).contains(f) ? f : nil
  }
  static func crossing(_ t: Double, index: Int) -> Double? {
    let f = (safe(t) - 0.54 - 0.14 * Double(index)) / 0.25
    return (0...1).contains(f) ? f : nil
  }
  static func pore(_ t: Double) -> Double { ease((safe(t) - 0.46) / 0.12) }
  static func approach(_ t: Double) -> Double { ease(safe(t) / 0.46) }
  struct Released { let x: Double; let y: Double; let alpha: Double }
  static func released(_ t: Double, index: Int) -> Released {
    let f = ease((safe(t) - 0.47 - Double(index) * 0.043) / 0.31)
    return .init(x: 184 + (Double(index) - 2.5) * (1.3 + 5 * f),y: 206 + (55 + 5 * Double(index % 3)) * f,alpha: 1 - 0.42 * f)
  }
  struct Circulation { let phase: Double; let alpha: Double }
  static func circulation(_ t: Double, index: Int) -> Circulation? {
    let phase = safe(t) * 1.08 - Double(index) * 0.11 + 0.15
    guard (0...1).contains(phase) else { return nil }
    return .init(phase: phase,alpha: min(1,min(14 * phase,12 * (1 - phase))))
  }
  static func resting(_ t: Double, index: Int) -> Circulation {
    let t = safe(t), remaining = 1 - ease(t), strength = safe(2 + 8 * remaining - Double(index))
    let f = (0.64 * t + Double(index) * 0.113).truncatingRemainder(dividingBy: 1)
    return .init(phase: f,alpha: min(1,min(10 * f,10 * (1 - f))) * strength)
  }
  static func blood(phase: Double, index: Int) -> Circulation {
    let f = (phase + Double(index) * 0.21).truncatingRemainder(dividingBy: 1)
    return .init(phase: f,alpha: min(1,min(f * 16,(1 - f) * 16)))
  }
}
