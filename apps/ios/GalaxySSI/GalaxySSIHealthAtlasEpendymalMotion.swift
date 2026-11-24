import Foundation

enum GalaxySSIHealthAtlasEpendymalMotion {
  static func phase(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func rim(_ x: Double, _ top: Double) -> Double {
    let offset = x-180
    return top+0.00063*offset*offset-0.026*offset
  }
  static func beat(_ step: Int, _ t: Double, _ index: Int) -> Double {
    switch step {
    case 0: return 2*t-Double(index)*0.19
    case 1: return 1.55*t-Double(index)*0.18
    case 2: return 2*t-Double(index)*0.29
    default: return 3*t-Double(index)*0.23
    }
  }
  static func length(_ step: Int, _ index: Int) -> Double {
    if step == 1 { return index == 2 ? 52 : 39 }
    return step == 2 ? 41 : 31
  }
}
