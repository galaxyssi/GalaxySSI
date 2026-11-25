import SwiftUI

struct GalaxySSIHealthAtlasDeltoidPose {
  typealias M = GalaxySSIHealthAtlasDeltoidMotion
  let amount: Double
  let scapula: CGAffineTransform
  let arm: CGAffineTransform
  let origins: [CGPoint]
  let controls: [CGPoint]
  let ends: [CGPoint]
  let tangents: [CGPoint]
  let head: CGPoint
  let bladeAnchor: CGPoint
  let clavicleEnd: CGPoint

  init(_ pose: Double) {
    amount = pose
    let bladeTurn = -33*pose*(0.45+0.55*pose)
    let blade = Self.rotation(bladeTurn, 157, 141, 5*pose, -4*pose)
    let head = CGPoint(x: 204, y: 142).applying(blade)
    let arm = Self.rotation(-119*pose, 204, 142, head.x-204, head.y-142)
    scapula = blade; self.arm = arm; self.head = head
    origins = M.roots.map { $0.applying(blade) }
    bladeAnchor = CGPoint(x: 138, y: 170).applying(blade)
    clavicleEnd = CGPoint(x: 226, y: 117).applying(blade)
    let ends = M.restingEnds.map { $0.applying(arm) }
    self.ends = ends
    controls = M.neutralControls.enumerated().map { i, p in
      let p = p.applying(blade)
      return CGPoint(x: p.x+pose*(17-2*Double(i)), y: p.y-pose*(18+5*Double(i)))
    }
    tangents = ends.enumerated().map { i, p in
      CGPoint(x: p.x+M.blend(-14+5.3*Double(i), -16, pose), y: p.y+M.blend(-13, 4, pose))
    }
  }
  private static func rotation(_ angle: Double, _ px: Double, _ py: Double, _ dx: Double, _ dy: Double) -> CGAffineTransform {
    let radians = angle * .pi/180, c = cos(radians), s = sin(radians)
    return CGAffineTransform(a: c, b: s, c: -s, d: c,
      tx: px-px*c+py*s+dx, ty: py-px*s-py*c+dy)
  }
}
