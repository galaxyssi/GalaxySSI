import SwiftUI

private typealias SurfactantMotion = GalaxySSIHealthAtlasSurfactantMotion
private typealias SurfactantShapes = GalaxySSIHealthAtlasSurfactantShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func surfactantOverview(step: Int, width: Double) {
    let sampleX = SurfactantMotion.stretch(116, center: 96, width: width)
    line(sampleX - 5, 139, 31, 169, SurfactantShapes.guide, 1); line(sampleX + 6, 139, 329, 169, SurfactantShapes.guide, 1)
    var local = context; local.translateBy(x: 96, y: 0); local.scaleBy(x: width, y: 1); local.translateBy(x: -96, y: 0)
    let sac = copy(local)
    sac.fill(SurfactantShapes.sac, SurfactantShapes.air); sac.stroke(SurfactantShapes.sac, SurfactantShapes.rose, 14)
    sac.stroke(SurfactantShapes.sac, Self.peach, 11.5); sac.stroke(SurfactantShapes.sac, SurfactantShapes.lining, 4.5); sac.stroke(SurfactantShapes.sac, Self.teal, 1.6)
    stroke(Path(ellipseIn: CGRect(x: sampleX - 8.5, y: 123.5, width: 17, height: 17)), SurfactantShapes.guide, 1.5)
    line(100, 82, 190, 60, SurfactantShapes.guide, 1); disc(100, 82, 2, SurfactantShapes.guide); label("surfactant_air", 264, 64, 138)
    if (3...4).contains(step) {
      let inhale = step == 3
      for side in [-1.0, 1.0] {
        let inner = 96 + side * 53, outer = 96 + side * 74
        arrow(inhale ? inner : outer, 110, inhale ? outer : inner, 110, Self.teal)
      }
      label(inhale ? "surfactant_inhale" : "surfactant_exhale", 264, 108, 154)
    }
  }
  func surfactantCutaway(step: Int, t: Double, width: Double) {
    rounded(15, 169, 345, 309, 8, SurfactantShapes.air)
    var local = context; local.translateBy(x: 180, y: 0); local.scaleBy(x: width, y: 1); local.translateBy(x: -180, y: 0)
    let art = copy(local)
    art.fill(SurfactantShapes.section(230), SurfactantShapes.lining); art.fill(SurfactantShapes.section(246), Self.peach); art.fill(SurfactantShapes.section(254), SurfactantShapes.tissue)
    art.stroke(SurfactantShapes.surface(246), SurfactantShapes.rose, 1.15)
    art.fill(SurfactantShapes.typeTwo, 0xEBADAB); art.stroke(SurfactantShapes.typeTwo, SurfactantShapes.rose, 1.4)
    art.oval(111, 258, 137, 277, fill: 0xC9ABD1, border: Self.violet); art.oval(231, 247, 252, 254, fill: 0xC9ABD1, border: Self.violet)
    art.oval(163, 268, 278, 297, fill: 0xF8CBD1, border: SurfactantShapes.rose)
    for i in 0...2 { let x = 176 + Double(i) * 36; art.oval(x, 277, x + 17, 288, fill: 0xCE838C, border: SurfactantShapes.rose) }
    art.surfactantLamellar(110, 244, 6); art.surfactantLamellar(147, 252, 5)
    switch step {
    case 0:
      art.surfactantLamellar(125, 233, 7)
      var arc = Path(); arc.addArc(center: CGPoint(x: 125, y: 233), radius: 11, startAngle: .degrees(-90), endAngle: .degrees(-90 + 45 + 290 * t), clockwise: false)
      art.stroke(arc, SurfactantShapes.guide, 1.25)
    case 1: art.surfactantRelease(t)
    case 2: if t < 0.2 { art.surfactantReleasedMaterial(1 + t) }
    default: break
    }
    art.stroke(SurfactantShapes.surface(230), Self.teal, 2.1)
    for i in 1...19 { art.at(SurfactantMotion.filmTrack, Double(i) / 20) { x, y in art.disc(x, y, 1.55, 0x91C8AE) } }
    if step == 2 && t >= 0.2 {
      for side in [-1, 1] { art.at(SurfactantMotion.filmTrack, SurfactantMotion.spread(t, side: side)) { x, y in art.disc(x, y, 2.8, Self.teal, border: Self.cream) } }
    }
    at(SurfactantMotion.filmTrack, 0.77) { x, y in
      surfactantCallout("surfactant_film", 258, 190, 145, SurfactantMotion.stretch(x, center: 180, width: width), y, above: true)
    }
    if step == 0 {
      let targetX = SurfactantMotion.stretch(107, center: 180, width: width)
      line(66, 196, 66, 229, SurfactantShapes.guide, 1); line(66, 229, targetX, 240, SurfactantShapes.guide, 1)
      disc(targetX, 240, 2, SurfactantShapes.guide); label("surfactant_lamellar_bodies", 66, 190, 106)
    } else {
      surfactantCallout("surfactant_liquid", 66, 190, 106, SurfactantMotion.stretch(57, center: 180, width: width), 244, above: true)
    }
    surfactantCallout("surfactant_type_ii", 78, 330, 102, SurfactantMotion.stretch(119, center: 180, width: width), 283)
    surfactantCallout("surfactant_capillary", 192, 330, 97, SurfactantMotion.stretch(212, center: 180, width: width), 287)
    surfactantCallout("surfactant_type_i", 293, 330, 99, SurfactantMotion.stretch(302, center: 180, width: width), 252)
  }
  private func surfactantLamellar(_ x: Double, _ y: Double, _ radius: Double) {
    disc(x, y, radius, 0xE1EEE0, border: Self.teal); disc(x, y, radius * 0.58, 0x9EC8B4, border: Self.teal)
  }
  private func surfactantRelease(_ t: Double) {
    let approach = SurfactantMotion.approach(t)
    if approach < 1 { surfactantLamellar(125, 233 - 14 * approach, 7); return }
    var pore = Path(); pore.move(to: CGPoint(x: 120, y: 212))
    pore.addCurve(to: CGPoint(x: 130, y: 212), control1: CGPoint(x: 117, y: 225), control2: CGPoint(x: 133, y: 225))
    fill(pore, SurfactantShapes.lining); line(121, 212, 129, 212, SurfactantShapes.lining, 2); stroke(pore, Self.teal, 1.3)
    surfactantReleasedMaterial(SurfactantMotion.release(t))
  }
  private func surfactantReleasedMaterial(_ travel: Double) {
    for i in -1...1 { disc(125 + Double(i) * (1.8 + travel * 2), 216 - 16 * travel + Double(i) * 1.4, 1.55, Self.teal) }
  }
  private func surfactantCallout(_ key: String, _ x: Double, _ baseline: Double, _ width: Double, _ targetX: Double, _ targetY: Double, above: Bool = false) {
    line(x, baseline + (above ? 6 : -16), targetX, targetY, SurfactantShapes.guide, 1); disc(targetX, targetY, 2, SurfactantShapes.guide); label(key, x, baseline, width)
  }
}
