import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func scapularPulls(_ frame: GalaxySSIHealthAtlasScapularPose, _ step: Int) {
    let pts = frame.points, span = 0.38+0.26*frame.amount
    scapularPull(pts[0],118,70,span,0x9C5F79)
    scapularPull(pts[1],117,134,span*0.76,0x846280)
    if step >= 2 {
      scapularPull(pts[2],116,235,span,0x735D8C)
      scapularPull(pts[4],271,222,span,0x477E79)
    }
  }
  private func scapularPull(_ p: CGPoint, _ dx: Double, _ dy: Double, _ span: Double, _ color: UInt32) {
    let m = GalaxySSIHealthAtlasScapularMotion.self
    let x1 = m.blend(p.x,dx,0.10), y1 = m.blend(p.y,dy,0.10)
    let x2 = m.blend(p.x,dx,span), y2 = m.blend(p.y,dy,span)
    line(x1,y1,x2,y2,Self.cream,4.4); arrow(x1,y1,x2,y2,color)
  }
  func scapularSocket(_ frame: GalaxySSIHealthAtlasScapularPose, returning: Bool) {
    let pts = frame.points, x = pts[5].x, y = pts[5].y, dx = x-pts[2].x, dy = y-pts[2].y
    let length = hypot(dx,dy)
    guard length > 0 else { return }
    let inv = 1/length
    arrow(x+4*dx*inv,y+4*dy*inv,x+31*dx*inv,y+31*dy*inv,Self.blue)
    scapularKey("scapular_rotation_story_socket",299,61,x,y,Self.blue)
    let tx = pts[4].x, ty = pts[4].y, offset = returning ? 12.0 : -12.0
    arrow(tx+offset,ty+16,tx-offset,ty+16,Self.blue)
  }
}
