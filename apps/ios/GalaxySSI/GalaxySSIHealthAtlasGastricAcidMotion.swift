import Foundation

enum GalaxySSIHealthAtlasGastricAcidMotion {
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1,max(0,t)) : 0 }
  private static func ease(_ t: Double, start: Double, end: Double) -> Double {
    let f = min(1,max(0,(safe(t) - start) / (end - start)))
    return f * f * (3 - 2 * f)
  }
  static func locate(_ t: Double) -> Double { ease(t,start: 0.04,end: 0.82) }
  static func histamine(_ t: Double) -> Double { ease(t,start: 0.02,end: 0.43) }
  static func recruit(_ t: Double) -> Double { ease(t,start: 0.26,end: 0.92) }
  static func exchange(_ t: Double) -> Double { ease(t,start: 0.10,end: 0.86) }
  static func chloride(_ t: Double) -> Double { ease(t,start: 0.04,end: 0.64) }
  static func lumen(_ t: Double) -> Double { ease(t,start: 0.18,end: 0.98) }
  static func feedback(_ t: Double) -> Double { ease(t,start: 0.06,end: 0.70) }
  static func output(_ t: Double) -> Double { 1 - 0.74 * ease(t,start: 0.32,end: 0.93) }
  static func flow(_ t: Double, index: Int) -> Double? {
    let f = safe(lumen(t) * 1.16 - 0.15 * Double(index))
    return f > 0.01 && f < 0.98 ? f : nil
  }
}
