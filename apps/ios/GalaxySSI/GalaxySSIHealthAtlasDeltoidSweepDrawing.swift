import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func deltoidSweep(_ frame: GalaxySSIHealthAtlasDeltoidPose, lowering: Bool) {
    let angle = (90-119*frame.amount) * .pi/180, cx = frame.head.x, cy = frame.head.y, radius = 141.0
    let start = angle+(lowering ? -0.2 : 0.2), tip = angle+(lowering ? 0.16 : -0.16)
    let p = Path { p in
      p.move(to: CGPoint(x: cx+radius*cos(start), y: cy+radius*sin(start)))
      p.addQuadCurve(to: CGPoint(x: cx+radius*cos(tip), y: cy+radius*sin(tip)),
        control: CGPoint(x: cx+(radius+2)*cos(angle), y: cy+(radius+2)*sin(angle)))
    }
    stroke(p, Self.blue, 1.8)
    let nearTip = tip+(lowering ? -0.08 : 0.08)
    arrow(cx+radius*cos(nearTip), cy+radius*sin(nearTip), cx+radius*cos(tip), cy+radius*sin(tip), Self.blue)
  }
}
