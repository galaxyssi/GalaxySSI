import Foundation

enum GalaxySSIHealthAtlasGutLymphoidMotion {
  static func ease(_ t: Double, _ start: Double, _ end: Double) -> Double {
    let t = t.isFinite ? min(1,max(0,t)) : 0
    let p = min(1,max(0,(t-start)/(end-start)))
    return p*p*(3-2*p)
  }
  static func appendixFocus(_ t: Double) -> Double { ease(t,0,0.48) }
  static func ileumFocus(_ t: Double) -> Double { ease(t,0.38,0.94) }
  static func appendixScale(_ t: Double) -> Double { 1+0.14*ease(t,0.04,0.68) }
  static func ileumScale(_ t: Double) -> Double { 1+0.13*ease(t,0.28,0.94) }
  static func uptake(_ t: Double) -> Double { ease(t,0.05,0.94) }
  static func contact(_ t: Double) -> Double { ease(t,0.10,0.76) }
  static func display(_ t: Double) -> Double { ease(t,0.36,0.64) }
  static func iga(_ t: Double, _ index: Int) -> Double { ease(t,0.03+Double(index)*0.23,0.70+Double(index)*0.14) }
  static func igaDistance(_ progress: Double, _ index: Int) -> Double { progress*(1-0.095*Double(index)) }
}
