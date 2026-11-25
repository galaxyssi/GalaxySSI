import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func pectoralScene(_ step: Int, _ t: Double) {
    let g = GalaxySSIHealthAtlasPectoralGeometry.self, m = GalaxySSIHealthAtlasPectoralActionMotion.self
    let angle = m.angle(step, t), attachment = m.attachment(angle)
    pectoralChest()
    if step >= 2 { pectoralSweep(angle, returning: step == 4) }
    var local = context; local.translateBy(x: 223, y: 147); local.rotate(by: .degrees(angle))
    let art = copy(local)
    art.fill(g.arm, 0xCADBD9); art.stroke(g.arm, 0x637D81, 1.4)
    art.fill(g.humerus, 0xF7EDDB); art.stroke(g.humerus, 0x9D8A74, 1.35)
    art.line(89, 5, 108, 24, 0xB0A188, 4); art.line(29, 7, 38, 7, 0xAD9273, 1.7)
    pectoralFan(attachment.x, attachment.y, step, t)
    disc(223, 147, 3.4, Self.cream, border: 0x637D81)
    label("pectoral_action_overhead", 180, 36, 224)
    arrow(103, 273, 103, 289, 0x637D81); label("pectoral_action_front", 103, 311, 146)
    switch step {
    case 0:
      pectoralLeader(82, 69, 104, 164, 165, 0x945964); label("pectoral_action_clavicular", 82, 61, 140)
      pectoralLeader(70, 229, 104, 157, 190, 0xA65F55); label("pectoral_action_sternocostal", 77, 246, 142)
    case 1:
      let radius = 6 + 5 * sin(t * .pi)
      stroke(Path(ellipseIn: CGRect(x: attachment.x - radius, y: attachment.y - radius, width: 2 * radius, height: 2 * radius)), 0xA65F55, 1.4)
      pectoralLeader(271, 76, 247, attachment.x, attachment.y, 0xA65F55); label("pectoral_action_tendon", 271, 68, 150)
    default:
      pectoralLeader(245, 77, 224, 223, 147, 0x637D81); label("pectoral_action_joint", 245, 69, 148)
    }
  }
  private func pectoralChest() {
    let g = GalaxySSIHealthAtlasPectoralGeometry.self
    gradient(g.chest, 83, 216, 0xD3E4E3, 0xEEF2E9); stroke(g.chest, 0x637D81, 1.6)
    fill(g.thorax, 0xE8EDDF); stroke(g.thorax, 0xADAC98, 1.5)
    oval(102, 118, 143, 178, fill: 0xCADBD6, border: 0x9EB5B0)
    oval(157, 118, 200, 178, fill: 0xCADBD6, border: 0x9EB5B0)
    oval(136, 93, 158, 113, fill: 0xEFE5D1, border: 0x9D8A74)
    oval(142, 182, 157, 205, fill: 0xEFE5D1, border: 0x9D8A74)
    fill(g.farFan, 0xD2A29C); stroke(g.farFan, 0xB47E79, 1.3)
  }
  private func pectoralSweep(_ angle: Double, returning: Bool) {
    let start = GalaxySSIHealthAtlasPectoralActionMotion.startAngle, sweep = GalaxySSIHealthAtlasPectoralActionMotion.sweepAngle
    func arc(_ start: Double, _ length: Double) -> Path {
      var path = Path()
      if length > 0 { path.addArc(center: CGPoint(x: 223, y: 147), radius: 125, startAngle: .degrees(start), endAngle: .degrees(start + length), clockwise: false) }
      return path
    }
    stroke(arc(start, sweep), 0x9AAFB1, 1.45)
    stroke(arc(returning ? angle : start, returning ? start + sweep - angle : angle - start), Self.teal, 2.75)
    let a = angle * .pi / 180, tail = (angle + (returning ? 4 : -4)) * .pi / 180
    arrow(223 + 125 * cos(tail), 147 + 125 * sin(tail), 223 + 125 * cos(a), 147 + 125 * sin(a), Self.teal)
  }
  private func pectoralLeader(_ x: Double, _ y: Double, _ elbow: Double, _ tx: Double, _ ty: Double, _ color: UInt32) {
    line(x, y, elbow, y, color, 1.15); line(elbow, y, tx, ty, color, 1.15)
  }
}
