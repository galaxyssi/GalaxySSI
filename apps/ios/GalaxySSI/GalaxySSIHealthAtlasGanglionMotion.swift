import Foundation

enum GalaxySSIHealthAtlasGanglionMotion {
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1,max(0,t)) : 0 }
  static func window(_ t: Double, _ start: Double, _ end: Double) -> Double {
    let f = min(1,max(0,(safe(t)-start)/(end-start)))
    return f*f*(3-2*f)
  }
  static func sensory(_ t: Double) -> Double { window(t,0.05,0.94) }
  static func preganglionic(_ t: Double) -> Double { window(t,0.05,0.43) }
  static func contact(_ t: Double) -> Double { min(1,max(0,1-abs(safe(t)-0.51)/0.08)) }
  static func postganglionic(_ t: Double) -> Double { window(t,0.59,0.95) }
  static func satellite(_ t: Double) -> Double { 1-abs(2*safe(t)-1) }
}
