import SwiftUI

private typealias VenousMotion = GalaxySSIHealthAtlasVenousMotion
private typealias VenousInk = GalaxySSIHealthAtlasVenousShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func venousScene(_ frame: GalaxySSIHealthAtlasVenousMotion, step: Int, t: Double) {
    line(141, 20, 141, 340, 0xCADBD4, 1)
    label("venous_return_story_calf", 75, 31, 121); label("venous_return_story_cutaway", 244, 31, 172)
    venousCalf(frame.squeeze, focus: step == 0 ? t : 0)
    label("venous_return_story_heartward", 230, 57, 120); arrow(270, 84, 270, 66, VenousInk.flow)
    venousMuscle(frame.squeeze)
    let lumen = VenousInk.lumen(frame.squeeze)
    gradient(lumen, 78, 315, 0xE3F4F6, 0xACD8E2); stroke(lumen, VenousInk.wall, 2.2)
    line(215, 82, 245, 82, 0xF4FCFD, 1.4); line(215, 311, 245, 311, 0xE1F3F6, 1.4)
    var local = context; local.clip(to: lumen)
    copy(local).venousValve(116, open: frame.proximalOpen); copy(local).venousValve(246, open: frame.distalOpen)
    venousValveLabel(116, "venous_return_story_proximal_valve"); venousValveLabel(246, "venous_return_story_distal_valve")
    switch step {
    case 0:
      venousStationRing(230, 116, min(1, t * 2)); venousStationRing(230, 246, max(0, t * 2 - 1))
    case 1:
      if frame.squeeze > 0.06 {
        arrow(164, 181, 191 + 10 * frame.squeeze, 181, Self.coral); arrow(296, 181, 269 - 10 * frame.squeeze, 181, Self.coral)
      }
    case 2, 3:
      venousFlow(t, from: 210, to: 82)
      if step == 3 { venousStationRing(230, 238, t) }
    case 4:
      if frame.distalOpen > 0.86 { venousFlow(t, from: 310, to: 165, strength: VenousMotion.ease(t, from: 0.56, to: 0.68)) }
    default: break
    }
  }
  private func venousValve(_ y: Double, open: Double) {
    for side in [-1.0, 1.0] {
      let tip = 230 + side * (16 * open), root = 230 + side * 27
      let detail = Path { p in
        p.move(to: CGPoint(x: root, y: y + 10))
        p.addQuadCurve(to: CGPoint(x: tip, y: y - 8), control: CGPoint(x: 230 + side * (11 + 12 * open), y: y + 6))
        p.addQuadCurve(to: CGPoint(x: root, y: y + 10), control: CGPoint(x: 230 + side * (9 + 10 * open), y: y + 14)); p.closeSubpath()
      }
      fill(detail, 0xE8F6F6); stroke(detail, VenousInk.flow, 1.5)
    }
  }
  private func venousValveLabel(_ y: Double, _ key: String) {
    label(key, 305, y - 13, 87); line(258, y, 297, y, VenousInk.leader, 1); line(297, y, 305, y - 8, VenousInk.leader, 1)
  }
  private func venousFlow(_ t: Double, from: Double, to: Double, strength: Double = 1) {
    for i in 0...2 {
      let packet = VenousMotion.flow(t, index: i, from: from, to: to, strength: strength)
      var local = context; local.opacity *= Double(packet.alpha) / 255
      let art = copy(local)
      art.line(226, packet.y + 4, 230, packet.y, VenousInk.flow, 2); art.line(234, packet.y + 4, 230, packet.y, VenousInk.flow, 2)
    }
  }
  func venousStationRing(_ x: Double, _ y: Double, _ t: Double, radius: Double = 7) {
    guard t > 0, t < 1 else { return }
    var local = context; local.opacity *= Double(VenousMotion.ringAlpha(t)) / 255
    let r = radius + 17 * t
    copy(local).stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), 0xAC6A40, 1.7)
  }
}
