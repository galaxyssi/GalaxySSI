import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func intercalatedTubularFlow(_ f: Double) {
    arrow(126, 106, 321, 106, 0x4C7D86)
    var clipped = context; clipped.clip(to: Path(CGRect(x: 116, y: 79, width: 215, height: 48)))
    let art = copy(clipped)
    for i in 0...4 {
      let x = 116 + (Double(i) * 47 + f * 148).truncatingRemainder(dividingBy: 217), y = i % 2 == 0 ? 93.0 : 118.0
      art.line(x - 9, y, x, y, 0x8AB1B5, 1.65); art.disc(x + 4, y, 1.7, 0x4C7D86)
    }
  }
  func intercalatedProtons(_ f: Double) {
    arrow(153, 127, 164, 110, 0xA02E40)
    for i in 0...2 {
      at(GalaxySSIHealthAtlasIntercalatedRoutes.protonRoute, GalaxySSIHealthAtlasIntercalatedMotion.protonPhase(f, i)) { x, y in intercalatedProton(x, y) }
    }
  }
  func intercalatedBaseReturn(_ f: Double) {
    arrow(203, 238, 221, 265, 0x246E61)
    for i in 0...1 {
      at(GalaxySSIHealthAtlasIntercalatedRoutes.bicarbonateRoute, GalaxySSIHealthAtlasIntercalatedMotion.basePhase(f, i)) { x, y in intercalatedBicarbonate(x, y) }
    }
  }
  func intercalatedBuffer(_ f: Double, phosphate: Bool) {
    typealias Motion = GalaxySSIHealthAtlasIntercalatedMotion
    let y = phosphate ? 115.0 : 88.0, rise = phosphate ? 9.0 : 16.0
    let meeting = phosphate ? 230.0 : 211.0, startX = phosphate ? 186.0 : 169.0
    let approach = min(1, f / 0.54)
    if approach < 1 {
      intercalatedProton(Motion.mix(startX, meeting + 4, approach), Motion.mix(y + rise, y - 4, approach))
      intercalatedBufferGlyph(Motion.mix(startX + 22, meeting, approach), y, phosphate: phosphate, bound: false)
    } else {
      intercalatedBufferGlyph(Motion.mix(meeting, 313, (f - 0.54) / 0.46), y, phosphate: phosphate, bound: true)
    }
  }
  func intercalatedBufferedOutflow(_ f: Double) {
    arrow(180, 104, 326, 104, 0x4C7D86)
    label("intercalated_story_label_urine", 286, 88, 94)
    intercalatedLeader(286, 93, 286, 104)
    var clipped = context; clipped.clip(to: Path(CGRect(x: 164, y: 105, width: 173, height: 23)))
    let art = copy(clipped)
    for i in 0...3 {
      let x = 165 + (Double(i) * 43 + f * 153).truncatingRemainder(dividingBy: 174)
      art.intercalatedBufferGlyph(x, 119, phosphate: i % 2 != 0, bound: true)
    }
  }
}
