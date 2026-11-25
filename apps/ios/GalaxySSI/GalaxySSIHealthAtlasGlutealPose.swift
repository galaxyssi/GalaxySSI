import SwiftUI

struct GalaxySSIHealthAtlasGlutealPose {
  static let origin: [CGPoint] = [.init(x:128,y:118),.init(x:116,y:138),.init(x:112,y:161),.init(x:117,y:177)]
  static let insertion: [CGPoint] = [.init(x:159,y:207),.init(x:164,y:219),.init(x:158,y:233)]
  let pelvis: CGAffineTransform
  let femur: CGAffineTransform
  let origins: [CGPoint]
  let insertions: [CGPoint]
  init(_ pelvisAngle: Double, _ femurAngle: Double) {
    let pelvis = Self.rotation(pelvisAngle), femur = Self.rotation(femurAngle)
    self.pelvis=pelvis; self.femur=femur
    origins = Self.origin.map { $0.applying(pelvis) }
    insertions = Self.insertion.map { $0.applying(femur) }
  }
  static func rotation(_ degrees: Double) -> CGAffineTransform {
    let a=degrees * .pi/180, c=cos(a), s=sin(a)
    return CGAffineTransform(a:c,b:s,c:-s,d:c,tx:190-190*c+173*s,ty:173-190*s-173*c)
  }
  static func ease(_ t: Double) -> Double {
    let t = t.isFinite ? min(1,max(0,t)) : 0
    return t*t*(3-2*t)
  }
}
