import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func spermScene(step: Int, t: Double) {
    switch step {
    case 0: spermFormation(t)
    case 1, 2, 3: spermDuctMap(step: step, t: t)
    default: spermPropel(t)
    }
  }
  private func spermFormation(_ t: Double) {
    oval(43, 44, 318, 319, top: 80, bottom: 306, from: 0xF8D8C8, to: 0xD9969B, border: Self.coral)
    oval(105, 106, 257, 258, fill: 0xFFF4E6, border: Self.coral)
    for i in 0..<10 {
      var local = context; local.translateBy(x: 180, y: 181); local.rotate(by: .degrees(Double(i) * 36)); local.translateBy(x: -180, y: -181)
      let drawing = copy(local)
      drawing.oval(163, 53, 197, 90, fill: Self.sand, border: Self.sienna); drawing.disc(179, 72, 6, Self.violet)
      drawing.oval(167, 88, 193, 108, fill: Self.peach, border: Self.coral); drawing.disc(180, 98, 4, Self.violet)
      if i % 2 == 0 { drawing.gameteSperm(180, 124 + 35 * t, rotation: 90, size: 0.82, t: t + Double(i) * 0.22) }
    }
    var cell = Path(); cell.move(to: CGPoint(x: 265, y: 238))
    cell.addCurve(to: CGPoint(x: 264, y: 165), control1: CGPoint(x: 247, y: 207), control2: CGPoint(x: 251, y: 188))
    cell.addCurve(to: CGPoint(x: 275, y: 192), control1: CGPoint(x: 273, y: 149), control2: CGPoint(x: 276, y: 153))
    cell.addQuadCurve(to: CGPoint(x: 284, y: 232), control: CGPoint(x: 278, y: 218))
    cell.addQuadCurve(to: CGPoint(x: 265, y: 238), control: CGPoint(x: 279, y: 249))
    fill(cell, 0x7EAE9F); disc(275, 229, 5, Self.teal)
    label("sperm_flow_lumen", 181, 187, 108); line(272, 285, 274, 243, Self.teal, 1.3); label("sperm_flow_sertoli", 273, 303, 120)
  }
  private func spermDuctMap(step: Int, t: Double) {
    typealias Motion = GalaxySSIHealthAtlasGameteMotion
    oval(43, 81, 212, 300, top: 80, bottom: 306, from: 0xF8D8C8, to: 0xD9969B, border: Self.coral)
    for i in 0...4 {
      var tubule = Path(); tubule.move(to: CGPoint(x: Double(67 + i * 9), y: 226))
      tubule.addCurve(to: CGPoint(x: Double(91 + i * 12), y: 129), control1: CGPoint(x: Double(37 + i * 24), y: 179), control2: CGPoint(x: Double(155 + i * 8), y: 189))
      tubule.addCurve(to: CGPoint(x: 176, y: Double(135 + i * 10)), control1: CGPoint(x: Double(73 + i * 17), y: 104), control2: CGPoint(x: Double(110 + i * 13), y: 98)); stroke(tubule, 0xBB8185, 3)
    }
    let vas = GalaxySSIHealthAtlasSectionLessonView.path(Motion.vas, width: 360, height: 360)
    let rete = GalaxySSIHealthAtlasSectionLessonView.path(Motion.rete, width: 360, height: 360)
    let epi = GalaxySSIHealthAtlasSectionLessonView.path(Motion.epididymis, width: 360, height: 360)
    stroke(vas, Self.coral, 12); stroke(vas, Self.peach, 8); stroke(rete, Self.coral, 11); stroke(rete, Self.cream, 5)
    stroke(epi, Self.sienna, 13); stroke(epi, Self.sand, 8)
    for i in 0...3 {
      var efferent = Path(); efferent.move(to: CGPoint(x: Double(194 + i * 3), y: Double(114 + i * 3)))
      efferent.addQuadCurve(to: CGPoint(x: 243, y: 104), control: CGPoint(x: Double(214 + i * 2), y: Double(90 + 10 * i))); stroke(efferent, Self.sienna, 1.4)
    }
    switch step {
    case 1: gameteFlow(Motion.rete, t, Self.teal, 4)
    case 2: gameteFlow(Motion.epididymis, t, Self.teal, 4)
    default:
      for i in 0...3 { at(Motion.epididymis, 0.86 + Double(i) * 0.036 + 0.009 * wave(t + Double(i) * 0.2)) { disc($0, $1, 3.4, Self.teal, border: Self.cream) } }
      stroke(Path(ellipseIn: CGRect(x: 240, y: 242, width: 80, height: 58)), Self.teal, 1.75)
    }
    if step == 1 {
      line(82, 115, 172, 163, Self.coral, 1.3); label("sperm_flow_rete", 72, 109, 117)
      line(170, 59, 216, 103, Self.sienna, 1.3); label("sperm_flow_efferent", 145, 51, 122)
    }
    if step >= 2 { line(290, 47, 275, 103, Self.sienna, 1.3); label("sperm_flow_head", 287, 36, 130) }
    if step == 3 { line(275, 318, 275, 299, Self.teal, 1.3); label("sperm_flow_tail", 272, 335, 140) }
    if step == 2 {
      rounded(40, 293, 320, 343, 14, 0xE2EEEA); gameteSperm(82 + 212 * t, 318 + 4 * wave(3 * t), rotation: 0, size: 1.2, t: 3 * t)
    }
  }
  private func spermPropel(_ t: Double) {
    var duct = Path(); duct.move(to: CGPoint(x: 24, y: 155))
    for x in stride(from: 24, through: 336, by: 4) { duct.addLine(to: CGPoint(x: Double(x), y: 184 - GalaxySSIHealthAtlasGameteMotion.ductRadius(Double(x), t))) }
    for x in stride(from: 336, through: 24, by: -4) { duct.addLine(to: CGPoint(x: Double(x), y: 184 + GalaxySSIHealthAtlasGameteMotion.ductRadius(Double(x), t))) }
    duct.closeSubpath(); stroke(duct, Self.coral, 18); stroke(duct, Self.peach, 12); fill(duct, 0xFCE4C4)
    for i in 0...3 { gameteSperm(Double(77 + i * 30) + 135 * t, 181 + (i % 2 == 0 ? -6 : 6), rotation: 0, size: 0.63, t: t + Double(i) * 0.2) }
    let squeeze = min(328, max(31, 16 + 328 * t))
    arrow(squeeze, 112, squeeze, 147, Self.coral); arrow(squeeze, 255, squeeze, 220, Self.coral); arrow(115, 284, 170 + 98 * t, 284, Self.teal)
    label("sperm_flow_vas", 180, 69, 206); label("sperm_flow_wall", 180, 318, 216)
  }
}
