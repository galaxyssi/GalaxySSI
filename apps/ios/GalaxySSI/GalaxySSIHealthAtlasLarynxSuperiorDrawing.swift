import SwiftUI

private typealias LarynxSuperior = GalaxySSIHealthAtlasLarynxShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func larynxSuperior(_ gap: Double) {
    label("larynx_story_superior", 180, 28, 154)
    gradient(LarynxSuperior.outline, 48, 199, 0xF7D9C7, 0xDCA0A5); stroke(LarynxSuperior.outline, LarynxSuperior.wallEdge, 1.35)
    gradient(LarynxSuperior.vestibule, 65, 192, 0x74898E, 0x4B666F); stroke(LarynxSuperior.vestibule, 0xA1747C, 1.35)
    fill(LarynxSuperior.anteriorRim, 0xF9D8C4); stroke(LarynxSuperior.anteriorRim, 0xBD8790, 1.2)
    let fold = LarynxSuperior.superiorFold(gap)
    var detail = Path(); detail.move(to: CGPoint(x: 128, y: 133))
    detail.addQuadCurve(to: CGPoint(x: 156 - 0.10 * gap, y: 101), control: CGPoint(x: 131, y: 115))
    for side in 0...1 {
      var local = context
      if side == 1 { local.translateBy(x: 360, y: 0); local.scaleBy(x: -1, y: 1) }
      let art = copy(local)
      art.gradient(fold, 84, 176, 0xFFF8E8, 0xECD2BF); art.stroke(fold, 0x997580, 1.35); art.stroke(detail, 0xFFF9EE, 2)
    }
    larynxLeader(67, 75, 92, 75, 115, 78); label("larynx_story_larynx", 42, 79, 48)
    larynxLeader(72, 133, 95, 133, 134, 124); label("larynx_story_folds", 43, 137, 57)
    line(180, 199, 180, 158, LarynxSuperior.guide, 1.05); disc(180, 158, 2, 0xEDF5ED, border: LarynxSuperior.guide)
    label("larynx_story_glottis", 180, 214, 112)
  }
}
