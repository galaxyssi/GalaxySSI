import Foundation

enum GalaxySSIHealthAtlasDuctBufferMotion {
  static func ease(_ t: Double, _ start: Double, _ end: Double) -> Double {
    let phase = t.isFinite ? min(1, max(0, t)) : 0
    let p = min(1, max(0, (phase - start) / (end - start)))
    return p * p * (3 - 2 * p)
  }
  static func orient(_ t: Double) -> Double { ease(t, 0.04, 0.95) }
  static func acidArrival(_ t: Double) -> Double { ease(t, 0.01, 0.39) }
  static func secretin(_ t: Double) -> Double { ease(t, 0.39, 0.94) }
  static func secretion(_ t: Double, _ outlet: Int) -> Double { ease(t, 0.06 + Double(outlet) * 0.13, 0.62 + Double(outlet) * 0.11) }
  static func delivery(_ t: Double) -> Double { ease(t, 0.02, 0.97) }
  static func bufferInflow(_ t: Double) -> Double { ease(t, 0.01, 0.41) }
  static func buffering(_ t: Double) -> Double { ease(t, 0.39, 0.99) }
}
