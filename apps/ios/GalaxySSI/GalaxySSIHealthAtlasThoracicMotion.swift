import Foundation

enum GalaxySSIHealthAtlasThoracicMotion {
  static let lateral = [53.0, 74, 91, 104, 112, 117, 118, 116, 111, 103, 94, 83]
  static let join = [29.0, 33, 37, 40, 43, 47, 52, 65, 77, 88, 69, 48]
  static func phase(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func expansion(_ step: Int, _ phase: Double) -> Double {
    let t = self.phase(phase), eased = t*t*(3-2*t)
    if step == 0 { let wave = sin(.pi*t); return 0.38*wave*wave }
    return step == 4 ? 1-eased : eased
  }
  static func frontX(_ x: Double, _ b: Double) -> Double { x+max(0, x-13)*0.14*b }
  static func frontY(_ x: Double, _ y: Double, _ b: Double) -> Double { y-(6+max(0, x-13)*0.045)*b }
  static func outerY(_ i: Int) -> Double { 84+15*Double(i) }
  static func joinY(_ i: Int) -> Double { i < 10 ? 99+16.2*Double(i) : 254+7*Double(i-10) }
  static func contactY(_ i: Int) -> Double { 85+17*Double(i) }
  static func rearX(_ i: Int) -> Double { 107+0.8*Double(i) }
  static func rearY(_ i: Int) -> Double { 73+16*Double(i) }
  static func sideSternumX(_ y: Double, _ b: Double) -> Double { 251+(y-90)*0.085+14*b }
}
