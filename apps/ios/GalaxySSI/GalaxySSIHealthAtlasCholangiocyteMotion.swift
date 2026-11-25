import Foundation

enum GalaxySSIHealthAtlasCholangiocyteMotion {
  static func stream(_ t: Double, _ offset: Double) -> Double {
    let p = safe(t) * 0.67 + offset
    return p - floor(p)
  }
  static func exchange(_ t: Double, _ index: Int) -> Double { advance(t, 0.035 + Double(index) * 0.18, 0.58) }
  static func osmosis(_ t: Double, _ index: Int) -> Double { advance(t, 0.02 + Double(index) * 0.12, 0.60) }
  private static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  private static func advance(_ t: Double, _ start: Double, _ span: Double) -> Double {
    let p = min(1, max(0, (safe(t) - start) / span))
    return p * p * (3 - 2 * p)
  }
}
