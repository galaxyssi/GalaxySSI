import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func toothGrindingStroke(_ t: Double) {
    let frame = GalaxySSIHealthAtlasToothMotion.grinding(t)
    toothFrontSection(frame.jawX, frame.jawY, 0)
    var local = context
    local.translateBy(x: 274 + frame.jawX * 0.52, y: 176 + frame.jawY * 0.48)
    let art = copy(local)
    if t < 0.30 {
      art.toothFoodCrumb(0, 0, 23, 9 - 5 * frame.close, 0)
    } else {
      for (i, offset) in GalaxySSIHealthAtlasToothAnatomyData.crumbs.enumerated() {
        let x = offset.x * (0.57 + 0.48 * frame.breakUp) + (i % 2 == 0 ? frame.shear * 4 : 0)
        let y = offset.y * (1 - 0.74 * frame.close)
        art.toothFoodCrumb(x, y, 5.8 - 2.1 * frame.breakUp, 5 - 3 * frame.close, 15 * Double(i - 2))
      }
    }
    toothFrontCrowns(frame.jawX, frame.jawY)
    toothCallout("tooth_mastication_story_molars", 276, 82, 98, 276, 91, 276, 162)
    toothCallout("tooth_mastication_story_jaw", 180, 332, 103, 180, 315, 180, 274 + frame.jawY)
  }
  func toothGatherBolus(_ t: Double) {
    let frame = GalaxySSIHealthAtlasToothMotion.bolus(t)
    toothFrontSection(frame.jawX, frame.jawY, frame.place)
    for (i, offset) in GalaxySSIHealthAtlasToothAnatomyData.crumbs.enumerated() {
      let dx = offset.x * (1 - 0.55 * frame.wet), dy = offset.y * (1 - 0.15 * frame.wet)
      toothFoodCrumb(frame.x + dx, frame.y + dy, 5.8, 4.3, 15 * Double(i - 2))
    }
    if frame.wet > 0 {
      let edge = 24 - 8 * frame.wet
      var arc = Path()
      arc.addArc(center: .zero, radius: 1, startAngle: .degrees(197), endAngle: .degrees(197 + 146 * frame.wet), clockwise: false)
      // Transform the ellipse path, keeping its stroke width in scene coordinates.
      let ellipse = arc.applying(CGAffineTransform(a: edge, b: 0, c: 0, d: 10.5, tx: frame.x, ty: frame.y - 0.5))
      var local = context; local.opacity *= Double(Int(frame.wet * 255)) / 255
      copy(local).stroke(ellipse, 0x527E8F, 1.8)
    }
    disc(frame.x + 2, frame.y - 19 + 9 * frame.wet, 2.8, 0xACD3DB, border: 0x527E8F)
    toothFrontCrowns(frame.jawX, frame.jawY)
    toothCallout("tooth_mastication_story_saliva", 238, 78, 88, 233, 88, frame.x + 2, frame.y - 19 + 9 * frame.wet)
    toothCallout("tooth_mastication_story_tongue", 141, 181, 80, 142, 188, 154 + frame.jawX, 216 + frame.jawY * 0.58)
  }
}
