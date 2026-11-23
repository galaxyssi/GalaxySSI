import SwiftUI

private typealias PleuraInk = GalaxySSIHealthAtlasPleuraInk
private typealias PleuraMotion = GalaxySSIHealthAtlasPleuraMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func pleuraScene(_ frame: GalaxySSIHealthAtlasPleuraMotion, step: Int) {
    let breath = frame.breath, widen = frame.widen
    stroke(PleuraInk.airway, 0xAB8072, 14); stroke(PleuraInk.airway, 0xEED2BA, 11)
    for y in stride(from: 47, through: 91, by: 7) { line(175, Double(y), 185, Double(y + 1), 0xC59883, 1) }
    for side in [-1.0, 1.0] {
      var local = context; local.translateBy(x: 180, y: 0); local.scaleBy(x: side * widen, y: 1)
      copy(local).pleuraHemiThorax(breath, heartSide: side > 0, highlight: step == 2)
    }
    let sampleX = 180 - 102 * widen
    line(sampleX - 7, 135, 30, 164, PleuraInk.guide, 1); line(30, 164, 30, 226, PleuraInk.guide, 1)
    stroke(Path(ellipseIn: CGRect(x: sampleX - 8, y: 122, width: 16, height: 16)), PleuraInk.guide, 1.3)
    pleuraCallout("pleura_story_lung", 91, 25, 100, 129, 66)
    pleuraCallout("pleura_story_wall", 280, 25, 126, 180 + 91 * widen, 78 - 2 * breath)
    pleuraCallout("pleura_story_diaphragm", 180, 211, 124, 180, 171 + 17 * breath, below: true)
    if step == 1 || step == 4 {
      let outer = 302 + 10 * breath, lower = 171 + 20 * breath, direction = step == 1 ? 1.0 : -1
      arrow(outer, 129, outer + direction * 21, 129 - direction * 7, Self.teal)
      arrow(239, lower + 9, 239, lower + 9 + direction * 16, Self.teal)
    }
    if step == 2 { arrow(231, 132, 250 + 13 * breath, 145 + 12 * breath, PleuraInk.visceral) }
    pleuraCutaway(frame, sliding: step == 3)
  }
  private func pleuraHemiThorax(_ breath: Double, heartSide: Bool, highlight: Bool) {
    var edge = Path(); edge.move(to: CGPoint(x: 26, y: 49))
    edge.addCurve(to: CGPoint(x: 96, y: 96), control1: CGPoint(x: 47, y: 32), control2: CGPoint(x: 81, y: 59))
    edge.addCurve(to: CGPoint(x: 102, y: 176 + 9 * breath), control1: CGPoint(x: 106, y: 122), control2: CGPoint(x: 109, y: 150))
    stroke(edge, 0xE4BAAC, 22); stroke(edge, 0xF4DCD0, 18)
    for i in 0...4 {
      let x = 86 + 6 * Double(i) - 1.15 * Double(i * i), y = 81 + 19 * Double(i) - 3 * breath
      var accent = Path(); accent.move(to: CGPoint(x: x + 14, y: y - 4))
      accent.addQuadCurve(to: CGPoint(x: x - 13, y: y + 9), control: CGPoint(x: x + 8, y: y + 4))
      stroke(accent, 0xB88C72, 9); stroke(accent, 0xFFEBCC, 6)
    }
    var dome = Path(); dome.move(to: CGPoint(x: 102, y: 176 + 9 * breath)); pleuraLungBase(&dome, breath)
    dome.addCurve(to: CGPoint(x: 0, y: 166 + 17 * breath), control1: CGPoint(x: 26, y: 154 + 22 * breath), control2: CGPoint(x: 14, y: 165 + 17 * breath))
    var diaphragm = context; diaphragm.translateBy(x: 0, y: 5)
    copy(diaphragm).stroke(dome, 0xA86567, 11); copy(diaphragm).stroke(dome, 0xDFA495, 8)
    var lung = edge; pleuraLungBase(&lung, breath)
    stroke(lung, PleuraInk.parietal, 7); stroke(lung, PleuraInk.fluid, 4.5)
    let notch = heartSide ? 12.0 : 0
    lung.addCurve(to: CGPoint(x: 19 + notch, y: 133), control1: CGPoint(x: 16 + notch, y: 164 + 16 * breath), control2: CGPoint(x: 12 + notch, y: 147))
    lung.addCurve(to: CGPoint(x: 14, y: 78), control1: CGPoint(x: 29, y: 116), control2: CGPoint(x: 8, y: 105))
    lung.addQuadCurve(to: CGPoint(x: 26, y: 49), control: CGPoint(x: 15, y: 57)); lung.closeSubpath()
    gradient(lung, 44, 195, 0xFAE0D9, 0xDBA0A9); stroke(lung, PleuraInk.visceral, highlight ? 2.3 : 1.5)
    var local = context; local.clip(to: lung)
    var accent = Path(); accent.move(to: CGPoint(x: 33, y: 91))
    accent.addQuadCurve(to: CGPoint(x: 106, y: 151 + 5 * breath), control: CGPoint(x: 64, y: 126))
    if !heartSide { accent.move(to: CGPoint(x: 57, y: 116)); accent.addQuadCurve(to: CGPoint(x: 105, y: 109), control: CGPoint(x: 77, y: 108)) }
    copy(local).stroke(accent, 0xC48E98, 1.3)
  }
  private func pleuraLungBase(_ path: inout Path, _ breath: Double) {
    path.addCurve(to: CGPoint(x: 42, y: 154 + 22 * breath), control1: CGPoint(x: 81, y: 174 + 9 * breath), control2: CGPoint(x: 66, y: 147 + 22 * breath))
  }
  private func pleuraCutaway(_ frame: PleuraMotion, sliding: Bool) {
    rounded(20, 226, 340, 318, 7, 0xF5DED2); rounded(24, 269, 336, 314, 5, 0xF5C7C7)
    fill(Path(CGRect(x: 24, y: 266, width: 312, height: 6)), PleuraInk.fluid)
    line(24, 266, 336, 266, PleuraInk.parietal, 1.8); line(24, 272, 336, 272, PleuraInk.visceral, 1.8)
    for i in 0...4 {
      let wallX = frame.wallTick(i), lungX = frame.lungTick(i)
      line(wallX, 266, wallX - 5, 253, sliding ? PleuraInk.parietal : 0xAEACA0, 2)
      line(lungX, 272, lungX + 5, 286, sliding ? PleuraInk.visceral : 0xC79A9F, 2)
    }
    label("pleura_story_detail", 180, 245, 220)
    pleuraKey("pleura_story_parietal", 64, PleuraInk.parietal); pleuraKey("pleura_story_fluid", 180, PleuraInk.fluid); pleuraKey("pleura_story_visceral", 296, PleuraInk.visceral)
  }
  private func pleuraKey(_ key: String, _ x: Double, _ color: UInt32) {
    line(x - 9, 324, x + 9, 324, color, 4); label(key, x, 342, 112)
  }
  private func pleuraCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ targetX: Double, _ targetY: Double, below: Bool = false) {
    line(x, y + (below ? -16 : 6), targetX, targetY, PleuraInk.guide, 1); disc(targetX, targetY, 1.6, PleuraInk.guide); label(key, x, y, width)
  }
}
