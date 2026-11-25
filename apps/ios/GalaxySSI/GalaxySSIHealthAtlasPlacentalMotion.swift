import Foundation

enum GalaxySSIHealthAtlasPlacentalMotion {
  static func phase(_ t: Double) -> Double { t.isFinite ? min(1,max(0,t)) : 0 }
  static func emphasis(_ t: Double) -> Double {
    let f = phase(t)
    return 4*f*(1-f)
  }
  static func stream(_ t: Double, _ index: Int) -> Double {
    let f = phase(t)+Double(index)/3
    return f-Double(Int(f))
  }
  static func transfer(_ t: Double, _ start: Double, _ end: Double) -> Double {
    let f = min(1,max(0,(phase(t)-start)/(end-start)))
    return f*f*(3-2*f)
  }
}
