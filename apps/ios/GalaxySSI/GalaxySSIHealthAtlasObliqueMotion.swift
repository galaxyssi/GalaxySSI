import Foundation
import CoreGraphics

struct GalaxySSIHealthAtlasObliqueMotion {
  static let turns: [Double] = [0,0.12,1,0,-1,0]
  let turn: Double
  let degrees: Double
  let right: Bool
  let bands: [GalaxySSIHealthAtlasObliqueBand]
  init(_ step: Int, _ t: Double) {
    let step = min(4,max(0,step)), t = t.isFinite ? min(1,max(0,t)) : 0
    let ease = t*t*(3-2*t), turn = Self.turns[step]+(Self.turns[step+1]-Self.turns[step])*ease
    self.turn = turn; degrees = 27*turn; right = Self.turns[step+1]>Self.turns[step]
    let angle = 27*turn * .pi/180
    func rotate(_ x: Double, _ y: Double) -> CGPoint {
      CGPoint(x:180+x*cos(angle)-y*sin(angle),y:177+x*sin(angle)+y*cos(angle))
    }
    // Superior view, anterior up: clockwise turns toward the person's right.
    bands = [
      .init(CGPoint(x:152,y:108),rotate(-59,-11),max(0,turn),true),
      .init(CGPoint(x:95,y:207),rotate(-45,-28),max(0,-turn),false),
      .init(CGPoint(x:208,y:108),rotate(59,-11),max(0,-turn),true),
      .init(CGPoint(x:265,y:207),rotate(45,-28),max(0,turn),false)
    ]
  }
}
