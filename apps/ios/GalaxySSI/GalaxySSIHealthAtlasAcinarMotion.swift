import Foundation

enum GalaxySSIHealthAtlasAcinarMotion {
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func eased(_ t: Double, _ start: Double, _ end: Double) -> Double {
    let p = min(1, max(0, (safe(t) - start) / (end - start)))
    return p * p * (3 - 2 * p)
  }
  static func locate(_ t: Double) -> Double { eased(t, 0.07, 0.79) }
  static func synthesize(_ t: Double) -> Double { eased(t, 0.02, 0.51) }
  static func store(_ t: Double) -> Double { eased(t, 0.42, 0.92) }
  static func dock(_ t: Double) -> Double { eased(t, 0.12, 0.48) }
  static func release(_ t: Double) -> Double { eased(t, 0.48, 0.97) }
  static func enrich(_ t: Double) -> Double { eased(t, 0.08, 0.72) }
  static func transit(_ t: Double) -> Double { safe(t) }
  static func arrive(_ t: Double) -> Double { eased(t, 0.16, 0.95) }
  static func mix(_ a: Double, _ b: Double, _ p: Double) -> Double { a + (b - a) * p }
}
