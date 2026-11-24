import SwiftUI

private typealias GastricPlate = GalaxySSIHealthAtlasGastricAcidGeometry

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gastricAcidStomachPlate() {
    gradient(GastricPlate.stomach,82,244,0xF5C8B7,0xD9888A); stroke(GastricPlate.stomach,GastricPlate.tissueEdge,2)
    stroke(GastricPlate.folds,0xF9D6C5,4.3); stroke(GastricPlate.folds,GastricPlate.rose,1.15)
  }
  func gastricAcidCellPlate(_ acidity: Double = 0) {
    stroke(GastricPlate.vessel,0xA76379,22); stroke(GastricPlate.vessel,0xECC2C6,17)
    oval(29,110,41,117,fill: GastricPlate.rose,border: GastricPlate.tissueEdge)
    oval(33,161,45,169,fill: GastricPlate.rose,border: GastricPlate.tissueEdge)
    oval(42,212,54,220,fill: GastricPlate.rose,border: GastricPlate.tissueEdge)
    oval(40,239,52,246,fill: GastricPlate.rose,border: GastricPlate.tissueEdge)
    gradient(GastricPlate.cell,74,275,0xFFEAD0,0xE3A298); stroke(GastricPlate.cell,GastricPlate.tissueEdge,2)
    oval(133,204,183,249,top: 204,bottom: 248,from: 0xDFB1CC,to: 0xB886AA,border: Self.violet)
    disc(156,227,5,0xA46F98,border: Self.violet)
    let mitochondria: [(Double, Double, Double)] = [(130,142,-58),(157,99,-24),(235,116,27),(224,241,-37),(113,203,64)]
    for (x, y, angle) in mitochondria { gastricAcidMitochondrion(x,y,angle: angle) }
    fill(GastricPlate.canaliculus,GastricPlate.lumenFill)
    if acidity > 0 {
      var acid = context; acid.opacity *= Double(Int(156 * acidity)) / 255
      copy(acid).fill(GastricPlate.canaliculus,0xE5A07B)
    }
    stroke(GastricPlate.canaliculus,GastricPlate.lumenEdge,1.65)
    for i in 0...3 {
      let x = 136 + Double(i) * 7
      line(x,189 + Double(i) * 1.6,x + 2,184 + Double(i) * 1.6,GastricPlate.lumenEdge,1.1)
    }
    for i in 0...5 {
      let x = 231 + Double(i) * 7
      line(x,183 + Double(i) * 1.35,x + 1,178 + Double(i) * 1.35,GastricPlate.lumenEdge,1.1)
    }
  }
  private func gastricAcidMitochondrion(_ x: Double, _ y: Double, angle: Double) {
    var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(angle))
    let art = copy(local); art.oval(-12,-4,12,4,fill: 0xEFC2A1,border: GastricPlate.tissueEdge)
    for i in -1...1 { art.line(Double(i) * 5 - 1,-2,Double(i) * 5 + 1,2,GastricPlate.tissueEdge,1) }
  }
  func gastricAcidCellLabels() {
    gastricAcidCallout("gastric_acid_story_apical_canaliculus",120,46,168,127,54,160,124)
    gastricAcidCallout("gastric_acid_story_blood_side",78,303,134,91,286,109,225)
    gastricAcidCallout("gastric_acid_story_gland_lumen",285,303,124,294,286,303,252)
  }
}
