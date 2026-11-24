import Foundation

enum GalaxySSIHealthAtlasPinealMotion {
  static func phase(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func ease(_ t: Double, _ start: Double, _ end: Double) -> Double {
    let f = min(1, max(0, (phase(t)-start)/(end-start)))
    return f*f*(3-2*f)
  }
  static func zoom(_ t: Double) -> Double { ease(t, 0.04, 0.9) }
  static func retinalSignal(_ t: Double, _ i: Int) -> Double { ease(t, 0.22+0.11*Double(i), 0.55+0.12*Double(i)) }
  static func relay(_ t: Double, _ i: Int) -> Double { ease(t, 0.03+0.22*Double(i), 0.24+0.22*Double(i)) }
  static func transmitter(_ t: Double, _ i: Int) -> Double { ease(t, 0.025+0.04*Double(i), 0.23+0.04*Double(i)) }
  static func synthesis(_ t: Double, _ i: Int) -> Double { ease(t, 0.29+0.21*Double(i), 0.49+0.21*Double(i)) }
  static func secretion(_ t: Double, _ i: Int) -> Double { ease(t, 0.71+0.052*Double(i), 0.89+0.052*Double(i)) }
  static func melatonin(_ t: Double) -> Double { 0.08+0.82*ease(t, 0.29, 0.45)*(1-ease(t, 0.64, 0.81)) }
}
