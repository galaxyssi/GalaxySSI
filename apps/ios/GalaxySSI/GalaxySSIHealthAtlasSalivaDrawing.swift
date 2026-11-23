import SwiftUI

private typealias SalivaMotion = GalaxySSIHealthAtlasSalivaMotion
private typealias SalivaShapes = GalaxySSIHealthAtlasSalivaShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func salivaMap(step: Int, t: Double) {
    gradient(SalivaShapes.head, 16, 177, 0xFFE8D8, 0xEDC0B2); stroke(SalivaShapes.head, SalivaShapes.rose, 1.4)
    stroke(SalivaShapes.jaw, 0xEED3B6, 9); stroke(SalivaShapes.jaw, 0xBF9277, 1.2)
    oval(111, 57, 139, 90, fill: 0xEAB5A8, border: SalivaShapes.rose); oval(117, 62, 131, 81, fill: 0xD8978E, border: SalivaShapes.rose)
    fill(SalivaShapes.mouth, 0xAF707B); stroke(SalivaShapes.mouth, SalivaShapes.rose, 1.2)
    fill(SalivaShapes.tongue, 0xE6A0AA); stroke(SalivaShapes.tongue, SalivaShapes.rose, 1.2)
    rounded(191, 110, 218, 114, 2, Self.cream)
    salivaGland(151, 100, 12, 0xE9BD81); salivaGland(165, 153, 9, 0xD9ABD0); salivaGland(207, 144, 5, 0xB7D4B0)
    let duct = GalaxySSIHealthAtlasSectionLessonView.path(SalivaMotion.cheekTrack, width: 360, height: 360)
    stroke(duct, Self.sienna, 4.5); stroke(duct, Self.cream, 2.4)
    if step == 0 { salivaStream(SalivaMotion.cheekTrack, t, count: 3, end: 0.88, radius: 2.3) }
    if step == 4 {
      label("saliva_story_cheek_opening", 296, 101, 112); salivaLeader(265, 106, 246, 106, 198, 114)
      disc(198, 114, 4, SalivaShapes.water, border: SalivaShapes.fluid); salivaStream(SalivaMotion.mouthTrack, t, count: 4, end: 1, radius: 2.4)
    }
    label("saliva_story_parotid", 53, 96, 94); salivaLeader(72, 102, 108, 102, 137, 104)
    label("saliva_story_sublingual", 296, 141, 106); salivaLeader(251, 146, 235, 146, 213, 144)
    label("saliva_story_submandibular", 270, 170, 161); salivaLeader(209, 162, 190, 162, 173, 157)
  }
  func salivaCutaway(step: Int, t: Double) {
    rounded(17, 209, 343, 324, 8, 0xF7E8DF); label("saliva_story_example", 180, 198, 233)
    rounded(126, 251, 179, 281, 11, 0xE5BACB)
    for angle in stride(from: 60, through: 300, by: 60) {
      var local = context; local.translateBy(x: 111, y: 267); local.rotate(by: .degrees(Double(angle)))
      let art = copy(local)
      art.gradient(SalivaShapes.acinarCell, -26, 26, 0xFFEADB, 0xE9ACAC); art.stroke(SalivaShapes.acinarCell, SalivaShapes.rose, 1.25)
      art.oval(39, -9, 54, 9, fill: 0xCAA6CE, border: Self.violet)
      art.disc(24, -6, 2.4, SalivaShapes.protein, border: Self.sienna); art.disc(27, 5, 2, SalivaShapes.protein, border: Self.sienna)
      if step == 1 && angle == 240 { art.salivaMolecule(29 - 16 * t, 0) }
    }
    salivaDuctWall(237, 255); salivaDuctWall(277, 295)
    fill(SalivaShapes.lumen, SalivaShapes.water); stroke(SalivaShapes.lumen, SalivaShapes.fluid, 1.2)
    switch step {
    case 0, 1:
      salivaLeader(73, 328, 73, 325, 90, 311); label("saliva_story_acinar_cells", 73, 344, 120)
      label("saliva_story_duct", 261, 342, 150); salivaLeader(261, 327, 261, 316, 261, 293)
      if step == 1 { label("saliva_story_lumen", 174, 225, 81); salivaLeader(174, 230, 165, 244, 151, 263) }
    case 2:
      salivaStream(SalivaMotion.fluidTrack, t, count: 4, end: 1, radius: 2.25)
      at(SalivaMotion.proteinTrack, t) { x, y in salivaMolecule(x, y) }
      at(SalivaMotion.proteinTrack, (t + 0.5).truncatingRemainder(dividingBy: 1)) { x, y in salivaMolecule(x, y) }
      disc(49, 338, 2.5, SalivaShapes.fluid); label("saliva_story_fluid", 110, 342, 110)
      salivaMolecule(184, 338); label("saliva_story_proteins", 263, 342, 144)
    case 3:
      salivaDuctFlow(t)
      label("saliva_story_sodium_out", 221, 226, 97); arrow(209, 262, 220, 232, Self.violet)
      let sodium = SalivaMotion.sodium(t); disc(sodium.x, sodium.y, 3, Self.violet, border: Self.cream)
      label("saliva_story_potassium_in", 283, 317, 110); arrow(284, 300, 273, 270, Self.teal)
      let potassium = SalivaMotion.potassium(t); disc(potassium.x, potassium.y, 3, Self.teal, border: Self.cream)
    case 4:
      salivaDuctFlow(t); label("saliva_story_to_mouth", 252, 342, 176)
    default: break
    }
  }
  private func salivaDuctWall(_ top: Double, _ bottom: Double) {
    for i in 0...6 {
      let x = 169 + 23 * Double(i)
      rounded(x, top, x + 22, bottom, 4, 0xE5BACB); oval(x + 7, top + 4, x + 15, bottom - 4, fill: 0xC6A2CB, border: Self.violet)
    }
  }
  private func salivaDuctFlow(_ t: Double) {
    for i in 0...6 {
      let x = SalivaMotion.ductX(t, index: i)
      disc(x, 265, 2.4, SalivaShapes.fluid); if i % 3 == 0 { salivaMolecule(x, 271) }
    }
  }
  private func salivaStream(_ path: SalivaMotion.Route, _ t: Double, count: Int, end: Double, radius: Double) {
    for i in 0..<count { at(path, SalivaMotion.streamFraction(t, index: i, count: count, end: end)) { x, y in disc(x, y, radius, SalivaShapes.fluid, border: Self.cream) } }
  }
  private func salivaMolecule(_ x: Double, _ y: Double) { disc(x, y, 3.3, SalivaShapes.protein, border: Self.sienna) }
  private func salivaGland(_ x: Double, _ y: Double, _ r: Double, _ color: UInt32) {
    oval(x - 1.6 * r, y - r, x + r, y + r, fill: color, border: SalivaShapes.rose)
    for i in -1...1 {
      let lobeX = x + 0.68 * Double(i) * r, lobeY = y - (i == 0 ? 0.55 : 0.27) * r
      disc(lobeX, lobeY, r * 0.62, color, border: SalivaShapes.rose); disc(lobeX - r * 0.12, lobeY - r * 0.2, r * 0.13, Self.cream)
    }
  }
  private func salivaLeader(_ x: Double, _ y: Double, _ bx: Double, _ by: Double, _ tx: Double, _ ty: Double) {
    line(x, y, bx, by, SalivaShapes.guide, 1); line(bx, by, tx, ty, SalivaShapes.guide, 1); disc(tx, ty, 1.65, SalivaShapes.guide)
  }
}
