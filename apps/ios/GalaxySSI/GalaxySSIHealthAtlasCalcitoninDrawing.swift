import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private static let calcitonin: UInt32 = 0x396957, calcium: UInt32 = 0xA17127
  private static let mineralBone: UInt32 = 0xA07B54, cCellEdge: UInt32 = 0xA3616D
  func calcitoninSignal(_ step: Int, _ t: Double) {
    typealias G = GalaxySSIHealthAtlasCalcitoninGeometry
    switch step {
    case 0:
      thyroidFollicle(91, 160, 63); thyroidFollicle(269, 161, 59)
      oval(151, 152, 191, 180, fill: 0xB2CDB5, border: Self.calcitonin); disc(172, 166, 5.5, Self.calcitonin)
      endocrineArc(171.5, 166.5, 28.5, 25.5, -140, 36 + 315 * t, Self.calcitonin, 2)
      label("c_cell_art_c_cell", 180, 86, 160); line(175, 96, 172, 137, Self.calcitonin, 1.2)
      label("c_cell_art_lumen", 91, 164, 80); label("c_cell_art_lumen", 269, 165, 77); label("c_cell_art_follicles", 180, 274, 255)
    case 1:
      endocrineVessel(G.capillary, 26)
      oval(127, 109, 223, 177, fill: 0xB2CDB5, border: Self.calcitonin); disc(166, 143, 10, Self.calcitonin, border: Self.cream)
      label("c_cell_art_c_cell", 175, 91, 166)
      for i in 0...3 {
        let f = min(1, max(0, t * 1.37 - Double(i) * 0.17))
        endocrineDiamond(190 + Double(i) * 5 + 28 * f, 164 + 76 * f, 3.8, Self.calcitonin)
      }
      for i in 0...3 { at(G.capillaryRoute, (0.22 * t + Double(i) * 0.14).truncatingRemainder(dividingBy: 0.63)) { disc($0, $1, 3, Self.calcium) } }
      label("c_cell_art_blood_calcium", 89, 286, 146); label("c_cell_art_calcitonin", 267, 286, 146)
      disc(89, 303, 3.8, Self.calcium); endocrineDiamond(267, 303, 4.5, Self.calcitonin)
    case 2:
      fill(G.bone, 0xEED2A7); stroke(G.bone, Self.mineralBone, 1.6)
      for i in 0...10 { let x = 40 + Double(i) * 28; line(x, 279, x + 8, 275, 0xBD9563, 1.4) }
      fill(G.osteoclast, 0xE1AFBC); stroke(G.osteoclast, Self.cCellEdge, 1.6)
      for i in 0...3 { disc(133 + Double(i) * 25, 209 - 14 * wave(Double(i) / 6), 6, Self.cCellEdge, border: Self.cream) }
      var resorption = Path(); resorption.move(to: CGPoint(x: 145, y: 241))
      for i in 1...12 {
        let f = Double(i) / 12
        resorption.addLine(to: CGPoint(x: 145 + 73 * f, y: 242 + 13 * sin(f * 3.14159) + Double(i % 2) * (10 - 6.6 * t)))
      }
      stroke(resorption, Self.cCellEdge, 2.2)
      for i in 0...3 {
        let f = (0.8 * t + Double(i) * 0.24).truncatingRemainder(dividingBy: 1)
        disc(150 + Double(i) * 17, 266 - f * (27 - 14 * t), 2.1, Self.calcium)
      }
      endocrineDiamond(65 + 51 * t, 184 + 19 * t, 5.5, Self.calcitonin)
      label("c_cell_art_calcitonin", 78, 146, 135); label("c_cell_art_osteoclast", 180, 108, 230); label("c_cell_art_bone_surface", 180, 326, 252)
    default:
      label("c_cell_art_context_calcitonin", 180, 73, 296); line(72, 93, 72, 139, 0xA4B7B4, 1.4)
      endocrineDiamond(72, 93 + 44 * t, 4.5, Self.calcitonin)
      fill(G.boneIcon, 0xEED2A7); stroke(G.boneIcon, Self.mineralBone, 1.4)
      fill(G.kidneyIcon, 0xDEB6B8); stroke(G.kidneyIcon, Self.cCellEdge, 1.4)
      stroke(G.gutIcon, Self.mineralBone, 11); stroke(G.gutIcon, 0xEED2A7, 7)
      for (key, x) in [("c_cell_art_bone_label", 72.0), ("c_cell_art_kidney_label", 180.0), ("c_cell_art_gut_label", 288.0)] { label(key, x, 232, 95) }
      line(72, 268, 288, 268, 0xA4B7B4, 1.4)
      for x in [72.0, 180.0, 288.0] { line(x, 243, x, 268, 0xA4B7B4, 1.4); disc(x, 266 - 23 * t, 3.4, Self.blue) }
      label("c_cell_art_context_main", 180, 307, 296)
    }
  }
  private func thyroidFollicle(_ x: Double, _ y: Double, _ r: Double) {
    disc(x, y, r, 0xE4ADA5, border: Self.cCellEdge)
    for i in 0...17 { let a = Double(i) * 0.349066; disc(x + (r - 10) * cos(a), y + (r - 10) * sin(a), 2.7, Self.cCellEdge) }
    disc(x, y, r - 18, 0xFFDBB4, border: Self.mineralBone)
  }
}
