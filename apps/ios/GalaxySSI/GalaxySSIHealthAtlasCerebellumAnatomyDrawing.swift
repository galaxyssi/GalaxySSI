import SwiftUI

private typealias CerebellumAnatomy = GalaxySSIHealthAtlasCerebellumShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func cerebellumAnatomy() {
    rounded(10, 22, 124, 338, 7, 0xF7EEEB); line(131, 23, 131, 337, 0xCDDCD8, 1)
    gradient(CerebellumAnatomy.brainstem, 171, 238, 0xE5E1C8, 0xC7AA93); stroke(CerebellumAnatomy.brainstem, 0x947760, 1.25)
    gradient(CerebellumAnatomy.cerebrum, 112, 195, 0xFCE7D9, 0xE6B5B9); stroke(CerebellumAnatomy.cerebrum, Self.coral, 1.25)
    stroke(CerebellumAnatomy.gyri, 0xBC818B, 1.2)
    gradient(CerebellumAnatomy.cerebellum, 169, 223, 0xEFD0DC, 0xCE92AB); stroke(CerebellumAnatomy.cerebellum, CerebellumAnatomy.earlier, 1.25)
    var local = context; local.clip(to: CerebellumAnatomy.cerebellum)
    let art = copy(local)
    for i in 0...5 {
      let y = 179 + Double(i) * 7
      var trail = Path(); trail.move(to: CGPoint(x: 73, y: y + 6))
      trail.addCurve(to: CGPoint(x: 117, y: y + 1), control1: CGPoint(x: 85, y: y - 3), control2: CGPoint(x: 105, y: y - 5))
      art.stroke(trail, CerebellumAnatomy.folia, 1.15)
    }
    art.stroke(CerebellumAnatomy.whiteMatter, 0xFAE6D8, 2.6)
    line(66, 83, 66, 112, CerebellumAnatomy.guide, 1); disc(66, 112, 1.7, CerebellumAnatomy.guide)
    label("cerebellum_story_cerebrum", 66, 76, 102)
    line(100, 215, 100, 246, CerebellumAnatomy.earlier, 1); line(100, 246, 68, 246, CerebellumAnatomy.earlier, 1); disc(100, 215, 1.8, CerebellumAnatomy.earlier)
    label("cerebellum_story_cerebellum", 67, 264, 102)
    line(59, 221, 37, 246, CerebellumAnatomy.guide, 1); line(37, 246, 37, 288, CerebellumAnatomy.guide, 1); disc(59, 221, 1.7, CerebellumAnatomy.guide)
    label("cerebellum_story_brainstem", 66, 306, 102)
  }
}
