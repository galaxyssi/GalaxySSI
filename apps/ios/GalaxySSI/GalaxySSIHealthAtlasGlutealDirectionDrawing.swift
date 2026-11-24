import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func glutealSweep(_ radius: Double, _ start: Double, _ span: Double, _ position: Double) {
    let arc = Path { p in
      p.addArc(center:CGPoint(x:190,y:173),radius:radius,startAngle:.degrees(start),endAngle:.degrees(start+span),clockwise:span < 0)
    }
    stroke(arc,0x97B4BE,1.6)
    let theta = (start+span*position) * .pi/180
    disc(190+radius*cos(theta),173+radius*sin(theta),4,Self.blue,border:Self.cream)
    let end = (start+span) * .pi/180, near = (start+span-(span > 0 ? 4 : -4)) * .pi/180
    arrow(190+radius*cos(near),173+radius*sin(near),190+radius*cos(end),173+radius*sin(end),Self.blue)
  }
  func glutealGhost(_ p: Path, _ angle: Double) {
    var c = context; c.concatenate(GalaxySSIHealthAtlasGlutealPose.rotation(angle))
    copy(c).stroke(p,0x98ADB0,1.35)
  }
}
