import SwiftUI

private typealias LarynxFrontal = GalaxySSIHealthAtlasLarynxShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func larynxFrontal(_ gap: Double) {
    line(24, 225, 336, 225, 0xC1CECA, 1); label("larynx_story_cutaway", 180, 241, 153)
    fill(LarynxFrontal.frontalLumen, 0xDBEEEA)
    let fold = LarynxFrontal.foldSection(gap)
    for side in 0...1 {
      var local = context
      if side == 1 { local.translateBy(x: 360, y: 0); local.scaleBy(x: -1, y: 1) }
      let art = copy(local)
      art.gradient(LarynxFrontal.airwayWall, 245, 340, 0xF1C7C4, 0xE8D0B7); art.stroke(LarynxFrontal.airwayWall, LarynxFrontal.wallEdge, 1.35)
      art.gradient(fold, 263, 289, 0xFFF8E8, 0xE9CBB7); art.stroke(fold, LarynxFrontal.wallEdge, 1.35)
      for y in stride(from: 305, through: 333, by: 7) { art.line(146.5, Double(y), 157, Double(y + 1), 0xB78979, 1.15) }
    }
    line(47, 270, 65, 270, LarynxFrontal.flow, 2); label("larynx_story_airflow", 56, 287, 96)
    line(283, 270, 301, 270, LarynxFrontal.pulse, 2); label("larynx_story_sound", 292, 287, 118)
    larynxLeader(86, 326, 112, 326, 150, 319); label("larynx_story_trachea", 55, 330, 61)
  }
}
