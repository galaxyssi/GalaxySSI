import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func latissimusScene(_ step: Int, _ t: Double) {
    let g = GalaxySSIHealthAtlasLatissimusGeometry.self, m = GalaxySSIHealthAtlasLatissimusActionMotion.self
    let pose = m.pose(step, t), direction = m.project(pose), dx = direction.x, dy = direction.y, scale = hypot(dx, dy)
    guard scale > 0 else { return }
    let tx = 220 + dx * 25 + dy / scale * 7, ty = 121 + dy * 25 - dx / scale * 7
    latissimusBack()
    if step >= 2 { latissimusTrails(step) }
    var local = context; local.translateBy(x: 220, y: 121); local.rotate(by: .radians(atan2(dy, dx))); local.scaleBy(x: scale, y: 1)
    let art = copy(local)
    art.fill(g.arm, 0xCADBD7); art.stroke(g.arm, 0x637F82, 1.4)
    art.fill(g.armBone, 0xF3E8D4); art.stroke(g.armBone, 0x9E8B73, 1.2)
    art.line(94, 0, 124, -2, 0xAC9E84, 3.5); art.line(24, -6, 40, -5, 0xB59A7B, 1.5)
    latissimusSheet(tx, ty, step, t)
    disc(220, 121, 3.4, Self.cream, border: 0x637F82); label("latissimus_action_oblique", 180, 37, 250)
    if step >= 2 { latissimusDirection(step, pose) }
    else if step == 1 {
      let radius = 6 + 5 * sin(t * .pi)
      stroke(Path(ellipseIn: CGRect(x: tx - radius, y: ty - radius, width: 2 * radius, height: 2 * radius)), 0x95574E, 1.5)
      line(272, 69, 254, 69, 0x95574E, 1.15); line(254, 69, tx, ty, 0x95574E, 1.15)
      label("latissimus_action_tendon", 272, 61, 152)
    } else {
      line(99, 300, 118, 300, 0x557E80, 1.15); line(118, 300, 118, 257, 0x557E80, 1.15)
      label("latissimus_action_fascia", 99, 318, 178)
    }
  }
  private func latissimusTrails(_ step: Int) {
    let g = GalaxySSIHealthAtlasLatissimusGeometry.self, m = GalaxySSIHealthAtlasLatissimusActionMotion.self
    stroke(g.extensionTrace, step == 3 ? 0x94AAAA : Self.blue, 1.7)
    stroke(g.adductionTrace, step == 2 ? 0x94AAAA : Self.teal, 1.7)
    let forward = m.project(0), side = m.project(2)
    disc(220 + forward.x * 140, 121 + forward.y * 140, 2.8, Self.cream, border: Self.blue)
    label("latissimus_action_forward_pose", 298, 108, 111)
    disc(220 + side.x * 140, 121 + side.y * 140, 2.8, Self.cream, border: Self.teal)
    label("latissimus_action_side_pose", 251, 275, 118)
  }
  private func latissimusDirection(_ step: Int, _ pose: Double) {
    let m = GalaxySSIHealthAtlasLatissimusActionMotion.self, returning = step == 4
    let extensionPhase = step == 2 || (returning && pose < 1), start = extensionPhase ? 0.0 : 1
    let before = max(start, pose - 0.04), after = min(start + 1, pose + 0.04)
    let a = m.project(before), b = m.project(after), direction = m.project(pose)
    let dx = b.x - a.x, dy = b.y - a.y, sign = returning ? -1.0 : 1
    let scale = sign * 8 / max(0.001, hypot(dx, dy)), x = 220 + 140 * direction.x, y = 121 + 140 * direction.y
    arrow(x - dx * scale, y - dy * scale, x, y, extensionPhase ? Self.blue : Self.teal)
  }
}
