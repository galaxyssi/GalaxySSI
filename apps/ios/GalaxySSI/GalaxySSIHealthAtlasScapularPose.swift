import SwiftUI

struct GalaxySSIHealthAtlasScapularPose {
  let amount: Double
  let turn: CGAffineTransform
  let arm: CGAffineTransform
  let points: [CGPoint]
  init(_ pose: Double) {
    amount = pose
    let turn = Self.rotation(-36*pose, 212, 153, 2*pose, -6*pose)
    self.turn = turn
    let points = GalaxySSIHealthAtlasScapularMotion.sites.map { $0.applying(turn) }
    self.points = points
    arm = Self.rotation(-116*pose, 251, 142, points[5].x-251, points[5].y-142)
  }
  private static func rotation(_ angle: Double, _ px: Double, _ py: Double, _ dx: Double, _ dy: Double) -> CGAffineTransform {
    let radians = angle * .pi/180, c = cos(radians), s = sin(radians)
    return CGAffineTransform(a: c, b: s, c: -s, d: c, tx: px-px*c+py*s+dx, ty: py-px*s-py*c+dy)
  }
}
