import SwiftUI

private typealias AstrocyteShapes = GalaxySSIHealthAtlasAstrocyteShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func astrocyteAnatomy(step: Int, t: Double, chapterCount: Int) {
    gradient(AstrocyteShapes.sender, 44, 134, 0xFFEADA, 0xEDBB9C); stroke(AstrocyteShapes.sender, Self.sienna, 1.35)
    gradient(AstrocyteShapes.receiver, 165, 221, 0xFFEAD9, 0xE8BA9F); stroke(AstrocyteShapes.receiver, Self.sienna, 1.35)
    astrocyteCapillary((Double(step) + t) / Double(max(1, chapterCount)))
    gradient(AstrocyteShapes.astrocyte, 65, 285, 0xDFEFDA, 0x8FCBBA); stroke(AstrocyteShapes.astrocyte, Self.teal, 1.35)
    oval(222, 181, 247, 204, fill: 0xA2C7B9, border: Self.teal)
    oval(230, 187, 241, 198, fill: 0x86B1A3, border: 0x79A697)
    let vesicles: [(Double, Double)] = [(87,92), (115,91), (134,113)]
    for (x, y) in vesicles {
      disc(x, y, 8, 0xFFE8D3, border: Self.sienna)
      if (step == 0 && (x != 134 || t < 0.25)) || x == 87 {
        disc(x - 2, y + 2, 1.65, Self.sienna); disc(x + 2, y - 1, 1.65, Self.sienna)
      }
    }
    for i in 0...2 {
      let x = 117 + Double(i) * 12
      line(x, 163, x - 2, 159, Self.sienna, 1.4); line(x, 163, x + 2, 159, Self.sienna, 1.4)
    }
  }
  private func astrocyteCapillary(_ t: Double) {
    let vessel = AstrocyteShapes.vessel
    gradient(vessel, 282, 321, 0xFFE2DD, 0xEAB6BB); stroke(vessel, Self.coral, 1.35)
    var local = context; local.clip(to: vessel)
    for i in 0...4 {
      let x = -62 + 96 * (Double(i) + t), drift = wave(x / 192), y = 301 + 2.5 * drift
      var cell = local
      cell.translateBy(x: x, y: y); cell.rotate(by: .degrees(14 * drift)); cell.translateBy(x: -x, y: -y)
      let art = copy(cell)
      art.oval(x - 12, y - 5.5, x + 12, y + 5.5, fill: 0xDE9CA7, border: Self.coral)
      art.oval(x - 5, y - 2, x + 5, y + 2, fill: 0xEFB8BD, border: 0xCD929E)
    }
  }
  func astrocyteLabels() {
    astrocyteLeader(83,39,86,66,Self.sienna); label("astrocyte_story_sending_neuron",83,34,151)
    astrocyteLeader(85,151,116,150,Self.sienna); label("astrocyte_story_synaptic_cleft",46,155,70)
    astrocyteLeader(87,231,93,212,Self.sienna); label("astrocyte_story_receiving_neuron",87,248,151)
    astrocyteLeader(302,111,252,128,Self.teal); label("astrocyte_story_astrocyte",302,105,100)
    astrocyteLeader(82,275,82,286,Self.coral); label("astrocyte_story_capillary",82,270,137)
    astrocyteLeader(284,271,241,280,Self.teal); label("astrocyte_story_endfoot",294,266,112)
    astrocyteGlutamate(33,339); label("astrocyte_story_glutamate",83,344,85)
    astrocyteGlutamine(148,339); label("astrocyte_story_glutamine",198,344,85)
    astrocytePotassium(266,339); label("astrocyte_story_potassium",308,344,69)
  }
  private func astrocyteLeader(_ x: Double, _ y: Double, _ tx: Double, _ ty: Double, _ color: UInt32) {
    line(x, y, tx, ty, color, 1.05); disc(tx, ty, 1.8, color)
  }
}
