import SwiftUI

private typealias RedCellMotion = GalaxySSIHealthAtlasRedCellMotion
private typealias RedCellShapes = GalaxySSIHealthAtlasRedCellShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func redCellCloseUp(_ t: Double) {
    redCellBody(112, 168, size: 3.35, angle: -11 + 24 * t)
    line(144, 166, 220, 166, RedCellShapes.wallEdge, 1.3); disc(144, 166, 4.5, Self.cream, border: RedCellShapes.cellEdge)
    disc(266, 166, 46, 0xFBE5E4, border: RedCellShapes.wallEdge)
    for i in 0...3 {
      let x = Double(254 + 24 * (i % 2)), y = Double(154 + 24 * (i / 2))
      oval(x - 14, y - 13, x + 14, y + 13, fill: i % 2 == 0 ? 0xD7979F : 0xC596AE, border: RedCellShapes.cellEdge)
      disc(x, y, 3, RedCellShapes.cellEdge, border: Self.cream)
    }
    label("red_cell_story_label_red_cell", 112, 252, 145); label("red_cell_story_label_hemoglobin", 266, 252, 145)
  }
  func redCellLung(_ t: Double) {
    gradient(RedCellShapes.alveolus, 66, 156, 0xFCF6EB, 0xFFDDD6); stroke(RedCellShapes.alveolus, RedCellShapes.wallEdge, 2.3)
    redCellVessel(160, 249)
    redCellBody(59 + 32 * t, 211, size: 0.8, angle: -8, bound: 1, rich: false)
    redCellBody(141 + 49 * t, 208, size: 1.05, angle: 0)
    redCellBody(255 + 35 * t, 211, size: 0.88, angle: 8, bound: 3)
    for i in 0...2 { let p = RedCellMotion.lungOxygen(t, index: i); redCellOxygen(p.x, p.y) }
    label("red_cell_story_label_alveolus", 180, 53, 200); label("red_cell_story_label_oxygen", 270, 112, 94)
    line(180, 251, 180, 274, RedCellShapes.wallEdge, 1.2); label("red_cell_story_label_lung_capillary", 180, 296, 200)
  }
  func redCellTransport(_ t: Double) {
    redCellVessel(105, 248, wall: 11)
    for i in 0...2 {
      redCellBody(65 + 85 * Double(i) + 55 * t, Double(159 + 33 * (i % 2)), size: 1.28, angle: 14 * wave(t * 0.6 + 0.3 * Double(i)), bound: 3)
    }
    label("red_cell_story_label_vessel", 180, 77, 210); arrow(136, 279, 224, 279, Self.teal); label("red_cell_story_label_flow", 180, 305, 190)
  }
  func redCellPeripheral(_ t: Double, diffuse: Bool) {
    let flow = RedCellMotion.peripheralFlow(t, diffuse: diffuse), x = RedCellMotion.cellX(t, diffuse: diffuse)
    redCellVessel(98, 189)
    redCellBody(57 + 25 * flow, 145, size: 0.88, angle: -9, bound: 3)
    redCellBody(x, 145, size: 1.12, angle: 0)
    redCellBody(252 + 31 * flow, 145, size: 0.84, angle: 10, bound: 1, rich: false)
    redCellOxygen(x, 137)
    for i in 0...2 { redCellTissue(86 + 94 * Double(i)) }
    for i in 0...2 { let p = RedCellMotion.peripheralOxygen(t, index: i, diffuse: diffuse); redCellOxygen(p.x, p.y) }
    label("red_cell_story_label_tissue_capillary", 180, 69, 220); label("red_cell_story_label_plasma", 69, 123, 76)
    if diffuse { label("red_cell_story_label_tissue_fluid", 267, 216, 124) }
    label("red_cell_story_label_tissue", 180, 330, 200)
  }
  private func redCellVessel(_ top: Double, _ bottom: Double, wall: Double = 5) {
    fill(Path(CGRect(x: 28, y: top, width: 304, height: bottom - top)), 0xFAEEF1)
    redCellLining(top, firstX: 54, wall: wall); redCellLining(bottom, firstX: 62, wall: wall)
  }
  private func redCellLining(_ y: Double, firstX: Double, wall: Double) {
    line(28, y, 332, y, RedCellShapes.wallEdge, wall + 2); line(28, y, 332, y, 0xE9B5BE, wall)
    for i in 0...5 { let x = firstX + 50 * Double(i); oval(x - 8, y - 2.8, x + 8, y + 2.8, fill: 0xC993A4, border: RedCellShapes.wallEdge) }
  }
  private func redCellTissue(_ x: Double) {
    oval(x - 41, 247, x + 41, 304, top: 246, bottom: 307, from: 0xE6EEE3, to: 0xB6D6C6, border: Self.teal)
    oval(x - 13, 275, x + 13, 291, fill: 0xB4A3BF, border: Self.violet); disc(x + 4, 283, 2.4, Self.violet)
    line(x - 30, 273, x - 23, 263, 0xF7FBF4, 2)
  }
  private func redCellBody(_ x: Double, _ y: Double, size: Double, angle: Double, bound: Int = 0, rich: Bool = true) {
    var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(angle)); local.scaleBy(x: size, y: size)
    let art = copy(local)
    art.oval(-24, -13, 24, 13, top: -14, bottom: 14, from: rich ? 0xF6A49E : 0xE6A3AC, to: rich ? 0xC65F6E : 0xA96177, border: RedCellShapes.cellEdge)
    art.oval(-13, -6, 13, 6, top: -7, bottom: 6, from: 0xC77884, to: 0xF6B8AD, border: 0xCB8290)
    var arc = Path(); arc.addArc(center: .zero, radius: 1, startAngle: .degrees(196), endAngle: .degrees(196 + 123), clockwise: false, transform: CGAffineTransform(scaleX: 20, y: 10))
    art.stroke(arc, 0xFBC5B9, 1.2)
    for i in 0..<bound { art.redCellOxygen(bound == 1 ? 0 : 10 * Double(i - 1), Double(-4 * (i % 2))) }
  }
  private func redCellOxygen(_ x: Double, _ y: Double) {
    disc(x - 2, y, 2.9, RedCellShapes.oxygen, border: Self.cream); disc(x + 2, y, 2.9, RedCellShapes.oxygen, border: Self.cream)
  }
}
