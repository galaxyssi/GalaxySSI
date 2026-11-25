import SwiftUI

private typealias EndothelialShapes = GalaxySSIHealthAtlasEndothelialShapes
private typealias EndothelialMotion = GalaxySSIHealthAtlasEndothelialMotion

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func endothelialScene(step: Int, t: Double) {
    var clipped = context; clipped.clip(to: EndothelialShapes.field)
    let tissue = copy(clipped)
    tissue.endothelialAnatomy()
    switch step {
    case 0:
      let x = 33 + 237 * t; tissue.line(x, 153, x + 55, 153, Self.cream, 3)
    case 1: tissue.arrow(176, 118, 176, 187, Self.blue)
    case 2:
      tissue.arrow(86, 117, 86, 191, Self.sienna); tissue.arrow(201, 191, 201, 117, Self.sienna)
    case 4: tissue.arrow(103, 226, 103, 281, Self.teal)
    default: break
    }
    tissue.endothelialParticles(step: step, t: t)
    stroke(EndothelialShapes.field, 0xA6C1B6, 1.1)
    label("endothelium_lumen", 270, 87, 134)
    line(268, 151, 268, 166, Self.coral, 1.1); disc(268, 151, 1.8, Self.coral)
    label("endothelium_lining", 268, 181, 138); label("endothelium_interstitium", 268, 214, 138)
    label("endothelium_lymph_capillary", 263, 283, 133)
    endothelialWater(29, 336); label("endothelium_water", 60, 340, 48)
    endothelialSolute(106, 336); label("endothelium_solutes", 157, 340, 89)
    endothelialProtein(218, 336); label("endothelium_proteins", 285, 340, 108)
  }
  private func endothelialAnatomy() {
    gradient(EndothelialShapes.field, 24, 314, 0xEFF5E8, 0xDEEADE)
    gradient(Path(CGRect(x: 18, y: 63, width: 324, height: 71)), 64, 133, 0xFFEAE2, 0xF7C8C0)
    endothelialLining(40); endothelialLining(133)
    endothelialRedCell(53, 87, -19); endothelialRedCell(226, 99, 13)
    endothelialTissueCell(55, 230, -21); endothelialTissueCell(241, 241, -17); endothelialTissueCell(314, 233, 24)
    gradient(EndothelialShapes.lymph, 264, 305, 0xE0F3EA, 0xAED5C9); stroke(EndothelialShapes.lymph, Self.teal, 1.6)
  }
  private func endothelialLining(_ y: Double) {
    var local = context; local.translateBy(x: 0, y: y)
    let art = copy(local)
    art.gradient(Path(CGRect(x: 18, y: 0, width: 324, height: 24)), 0, 24, 0xF6CEBB, 0xDF9DA8)
    for i in 0...5 {
      let x = 18 + 54 * Double(i)
      if i > 0 { var seam = local; seam.translateBy(x: x, y: 0); copy(seam).stroke(EndothelialShapes.tileSeam, Self.coral, 1.05) }
      art.oval(x + 16, 8, x + 36, 16, fill: 0xC5899C, border: Self.coral)
    }
    art.line(18, 0, 342, 0, Self.coral, 1.25); art.line(18, 24, 342, 24, Self.coral, 1.25)
  }
  private func endothelialRedCell(_ x: Double, _ y: Double, _ angle: Double) {
    var local = context
    local.translateBy(x: x, y: y); local.rotate(by: .degrees(angle)); local.translateBy(x: -x, y: -y)
    let art = copy(local)
    art.oval(x - 16, y - 8, x + 16, y + 8, fill: 0xEAA4A3, border: Self.coral)
    art.oval(x - 7, y - 3, x + 7, y + 3, fill: 0xF7C8C0, border: 0xD48E91)
  }
  private func endothelialTissueCell(_ x: Double, _ y: Double, _ angle: Double) {
    var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(angle))
    let art = copy(local)
    art.fill(EndothelialShapes.tissueCell, 0xC0D6C1); art.stroke(EndothelialShapes.tissueCell, 0x91B3A1, 1)
    art.oval(-6, -3, 6, 3, fill: 0x8AB1A7, border: 0x749A8D)
  }
  private func endothelialParticles(step: Int, t: Double) {
    endothelialWater(266, 119); endothelialWater(307, 99)
    for i in EndothelialMotion.lymphRoutes.indices {
      if step == 4 {
        at(EndothelialMotion.lymphRoutes[i], EndothelialMotion.travel(t, delay: i)) { x, y in endothelialWater(x, y) }
      } else {
        let f = step == 0 ? 0 : step == 1 ? EndothelialMotion.travel(t, delay: i) : 1
        let startY = 96 + 6 * Double(i)
        endothelialWater(EndothelialMotion.waterTissueX(i) - 2 * (1 - f), startY + (EndothelialMotion.waterTissueY(i) - startY) * f)
      }
    }
    // Opposing solute transport is diffusion, separate from bulk water filtration.
    let down = step < 2 ? 0 : step == 2 ? EndothelialMotion.travel(t) : 1
    let up = step == 2 ? EndothelialMotion.travel(t, delay: 1) : down
    endothelialSolute(99, 82 + 121 * down); endothelialSolute(189, 197 - 113 * up)
    let drift = step < 3 ? 0 : step == 3 ? EndothelialMotion.travel(t) : 1
    endothelialProtein(72 + 19 * drift, 118, active: step == 3)
    endothelialProtein(214 + 20 * drift, 117, active: step == 3)
    endothelialProtein(285 + 23 * drift, 116, active: step == 3)
  }
  private func endothelialWater(_ x: Double, _ y: Double) {
    disc(x, y, 4.5, 0x86BED7, border: Self.blue); disc(x - 1, y - 1.3, 1.2, 0xE2F5FB)
  }
  private func endothelialSolute(_ x: Double, _ y: Double) {
    var local = context; local.translateBy(x: x, y: y)
    let art = copy(local)
    art.fill(EndothelialShapes.soluteShape, 0xF1C17D); art.stroke(EndothelialShapes.soluteShape, Self.sienna, 1.1)
  }
  private func endothelialProtein(_ x: Double, _ y: Double, active: Bool = false) {
    var local = context; local.translateBy(x: x, y: y)
    let art = copy(local)
    art.fill(EndothelialShapes.proteinShape, active ? 0xBC92CD : 0xD8B6DD)
    art.stroke(EndothelialShapes.proteinShape, Self.violet, active ? 1.6 : 1.1); art.disc(-3, -2.5, 1.5, Self.cream)
  }
}
