import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ovumScene(step: Int, t: Double) {
    switch step {
    case 0, 1: ovary(releasing: step == 1, t: t)
    case 2: ovumPickup(t)
    case 3: ovumCilia(t)
    default: ovumDestination(t)
    }
  }
  private func ovary(releasing: Bool, t: Double) {
    let outside = releasing ? GalaxySSIHealthAtlasGameteMotion.release(t) : 0
    let open = releasing && t >= GalaxySSIHealthAtlasGameteMotion.follicleOpens
    var organ = Path(); organ.move(to: CGPoint(x: 34, y: 174))
    organ.addCurve(to: CGPoint(x: 226, y: 103), control1: CGPoint(x: 65, y: 97), control2: CGPoint(x: 144, y: 69))
    organ.addQuadCurve(to: CGPoint(x: 264, y: 146), control: CGPoint(x: 253, y: 115))
    if open { organ.addCurve(to: CGPoint(x: 260, y: 195), control1: CGPoint(x: 229, y: 138), control2: CGPoint(x: 219, y: 195)) }
    organ.addCurve(to: CGPoint(x: 119, y: 275), control1: CGPoint(x: 284, y: 248), control2: CGPoint(x: 201, y: 290))
    organ.addCurve(to: CGPoint(x: 34, y: 174), control1: CGPoint(x: 52, y: 263), control2: CGPoint(x: 16, y: 228)); organ.closeSubpath()
    gradient(organ, 80, 306, 0xF8D8C8, 0xD9969B); stroke(organ, Self.coral, 1.7)
    for i in 0...3 {
      let x = Double(66 + i * 23), y = 196 + 28 * wave(Double(i) * 0.093), r = Double(8 + 2 * i)
      oval(x - r, y - r, x + r, y + r, fill: Self.sand, border: Self.sienna)
      disc(x, y, 3 + Double(i) * 0.6, 0xFDF0D6, border: Self.violet)
    }
    let radius = releasing ? 48 : 29 + 19 * t, x = 209.0, y = 151.0
    if !open {
      oval(x - radius, y - radius, x + radius, y + radius, top: 88, bottom: 265, from: 0xFFEDCD, to: 0xE5B77D, border: Self.coral)
      stroke(Path(ellipseIn: CGRect(x: x - radius + 5, y: y - radius + 5, width: 2 * (radius - 5), height: 2 * (radius - 5))), Self.sienna, 1.1)
    } else {
      var arc = Path(); arc.addArc(center: CGPoint(x: x, y: y), radius: radius, startAngle: .degrees(52), endAngle: .degrees(321), clockwise: false)
      stroke(arc, Self.sienna, 2.2)
    }
    let cx = 220 + outside * 95, cy = 159 - outside * 17
    gameteOocyte(cx, cy, 13.5)
    if releasing {
      label("ovum_flow_oocyte", 285, 80, 134); line(284, 91, cx + 3, cy - 24, Self.violet, 1.2)
    } else {
      label("ovum_flow_cumulus", 241, 58, 139); line(240, 67, cx + 14, cy - 15, Self.violet, 1.2)
    }
    label("ovum_flow_follicle", 121, 82, 125); line(142, 86, x - radius * 0.61, y - radius * 0.78, Self.sienna, 1.2)
    label("ovum_flow_ovary", 130, 318, 135); line(130, 304, 130, 276, Self.coral, 1.2)
  }
  private func ovumPickup(_ t: Double) {
    oval(28, 189, 137, 283, top: 80, bottom: 306, from: 0xF8D8C8, to: 0xD9969B, border: Self.coral)
    oval(94, 202, 131, 244, fill: Self.sand, border: Self.sienna)
    var tube = Path(); tube.move(to: CGPoint(x: 196, y: 146))
    tube.addCurve(to: CGPoint(x: 330, y: 113), control1: CGPoint(x: 222, y: 112), control2: CGPoint(x: 278, y: 97))
    tube.addLine(to: CGPoint(x: 330, y: 155)); tube.addCurve(to: CGPoint(x: 202, y: 197), control1: CGPoint(x: 280, y: 161), control2: CGPoint(x: 229, y: 161)); tube.closeSubpath()
    gradient(tube, 76, 270, 0xF4D4C3, 0xC98393); stroke(tube, Self.coral, 1.5)
    for i in 0..<5 {
      let x0 = Double(200 + 6 * i), y0 = Double(146 + 8 * i)
      let tipX = Double(157 + 9 * i) + 4 * wave(2 * t + Double(i) * 0.14)
      let tipY = Double(152 + 12 * i) + 3 * wave(2 * t + Double(i) * 0.19)
      var strip = Path(); strip.move(to: CGPoint(x: x0, y: y0))
      strip.addQuadCurve(to: CGPoint(x: tipX, y: tipY), control: CGPoint(x: x0 - 17, y: y0 - 3))
      strip.addQuadCurve(to: CGPoint(x: x0 + 8, y: y0 + 1), control: CGPoint(x: tipX + 19, y: tipY + 5)); strip.closeSubpath()
      fill(strip, Self.peach); stroke(strip, Self.coral, 1.2)
    }
    at(GalaxySSIHealthAtlasGameteMotion.pickupPath, GalaxySSIHealthAtlasGameteMotion.pickup(t)) { gameteOocyte($0, $1, 10.5) }
    label("ovum_flow_fimbriae", 162, 95, 115); line(156, 104, 175, 146, Self.coral, 1.25)
    label("ovum_flow_tube", 280, 78, 138); line(275, 90, 275, 121, Self.coral, 1.25); label("ovum_flow_ovary", 82, 314, 136)
  }
  private func ovumCilia(_ t: Double) {
    rounded(28, 94, 333, 267, 23, 0xFFEDD2)
    for i in 0...21 {
      let x = 42 + Double(i) * 13.2, distance = (x - 14 - 330 * t) / 32
      let force = 4 * exp(-distance * distance), tilt = 6 + 10 * wave(t * 3.3 - Double(i) * 0.11)
      for sign in [-1.0, 1.0] {
        let root = 181 + sign * (56 - force)
        oval(x - 7, root + min(sign * 26, 0), x + 7, root + max(sign * 26, 0), fill: Self.peach, border: Self.coral)
        disc(x, root + sign * 15, 2.5, Self.violet)
        var cilium = Path(); cilium.move(to: CGPoint(x: x, y: root))
        cilium.addQuadCurve(to: CGPoint(x: x + tilt, y: root - sign * 20), control: CGPoint(x: x - 3.3, y: root - sign * 10.5)); stroke(cilium, Self.teal, 1.5)
      }
    }
    gameteOocyte(63 + 227 * t, 181 + 4 * wave(t), 14)
    label("ovum_flow_cilia_label", 103, 64, 110); line(103, 77, 120, 138, Self.teal, 1.2); arrow(127, 302, 244, 302, Self.teal)
  }
  private func ovumDestination(_ t: Double) {
    let route = GalaxySSIHealthAtlasGameteMotion.ampulla
    let path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
    stroke(path, Self.coral, 34); stroke(path, Self.peach, 30); stroke(path, 0xFFEED1, 17)
    var uterus = Path(); uterus.move(to: CGPoint(x: 306, y: 142))
    uterus.addQuadCurve(to: CGPoint(x: 347, y: 148), control: CGPoint(x: 331, y: 152))
    uterus.addLine(to: CGPoint(x: 350, y: 265)); uterus.addLine(to: CGPoint(x: 329, y: 265))
    uterus.addQuadCurve(to: CGPoint(x: 299, y: 181), control: CGPoint(x: 318, y: 213)); uterus.closeSubpath()
    fill(uterus, Self.peach); stroke(uterus, Self.coral, 1.4)
    at(route, 0.13 + 0.43 * GalaxySSIHealthAtlasGameteMotion.pickup(t)) { gameteOocyte($0, $1, 11) }
    label("ovum_flow_ampulla_label", 175, 72, 142); line(176, 82, 172, 120, Self.sienna, 1.3)
    label("ovum_flow_uterus", 263, 286, 163); arrow(270, 248, 315, 229, Self.teal)
  }
}
