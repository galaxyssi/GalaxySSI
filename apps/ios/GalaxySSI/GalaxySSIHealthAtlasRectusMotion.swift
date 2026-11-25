import Foundation
import CoreGraphics

struct GalaxySSIHealthAtlasRectusMotion {
  static let poses: [Double] = [0, 0.07, 0.33, 1, 0.25, 0]
  static let effort: [Double] = [0, 0.16, 0.67, 1, 0.33, 0]
  let bend: Double
  let tone: Double
  init(_ step: Int, _ t: Double) {
    let t = t.isFinite ? min(1,max(0,t)) : 0, ease = t*t*(3-2*t)
    let step = min(4,max(0,step))
    bend = 0.57*Self.lerp(Self.poses[step],Self.poses[step+1],ease)
    tone = Self.lerp(Self.effort[step],Self.effort[step+1],ease)
  }
  static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a+(b-a)*t }
  func point(_ x: Double, _ y: Double) -> CGPoint {
    if y >= 260 || bend < 0.0001 { return CGPoint(x:x,y:y) }
    let rise = 260-y, arc = min(104,rise), angle = bend*arc/104, radius = 104/bend
    let side = x-150, upper = rise-arc, halfSin = sin(angle*0.5)
    return CGPoint(x:150+2*radius*halfSin*halfSin+upper*sin(angle)+side*cos(angle),
      y:260-radius*sin(angle)-upper*cos(angle)+side*sin(angle))
  }
}
