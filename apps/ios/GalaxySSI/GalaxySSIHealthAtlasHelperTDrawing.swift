import SwiftUI

extension GalaxySSIHealthAtlasImmuneDrawing {
  func helperTScene(_ step: Int, _ t: Double) {
    typealias G = GalaxySSIHealthAtlasImmuneGeometry
    switch step {
    case 0:
      var local = art.context; local.translateBy(x: 98 + 26 * Self.ease(t), y: 172); local.scaleBy(x: 1.18, y: 1.18)
      let cue = art.copy(local)
      cue.gradient(G.cueRim, -43, 43, 0xF3DED4, 0xD6A697); cue.stroke(G.cueRim, 0x8E5E42, 1.6)
      cue.oval(-25, -19, 18, 21, fill: 0xB4829A, border: GalaxySSIHealthAtlasIllustratedDrawing.violet); cue.disc(-11, -7, 4, 0xDFBACB)
      helperCell(224, 172, 1.16)
      let response = Self.ease(t, 0.40, 0.90)
      for i in 0...2 { let y = 150 + Double(i) * 22; art.line(183 - Double(i % 2) * 2, y, 184 + 15 * response, y, 0x236D67, 1.4 + response) }
      art.label("helper_t_story_label_cue_cell", 110, 266, 132); art.label("helper_t_story_label_helper", 231, 266, 109)
    case 1:
      helperCell(124, 171, 1.45)
      for (i, angle) in [-64.0, -32, -1, 29, 60].enumerated() {
        let f = Self.ease(t, 0.065 + 0.086 * Double(i), 0.53 + 0.105 * Double(i))
        if f <= 0 { continue }
        var local = art.context; local.translateBy(x: 124, y: 171); local.rotate(by: .degrees(angle))
        let drawing = art.copy(local), r = 64 + 62 * f
        drawing.endocrineDiamond(r, Double(i % 2) * 4, 4.6 - 1.4 * f, 0x236D67)
        if f > 0.15 { drawing.endocrineDiamond(r - 12 * f, -7, 2.4, 0x236D67) }
      }
      art.label("helper_t_story_label_cytokines", 249, 269, 152); art.label("helper_t_story_label_helper", 115, 269, 112)
    default:
      let responding = step == 3
      helperCell(87, 172, 1.16)
      lymphocyte(267, 104, 0.78, 0xF5DAAA, 0xD4A476, 0x8E5E42)
      lymphocyte(267, 243, 0.78, 0xC9E4F0, 0x89AECF, GalaxySSIHealthAtlasIllustratedDrawing.blue)
      helperDelivery(G.upperPathRoute, responding ? 0.58 + 0.42 * t : Self.ease(t, 0.04, 0.80), responding ? 0.90 : 0.92)
      helperDelivery(G.lowerPathRoute, responding ? 0.52 + 0.48 * t : Self.ease(t, 0.18, 0.94), responding ? 1 : 0.88)
      if responding {
        helperFan(267, 104, t, 0x8E5E42, -1)
        helperFan(267, 243, Self.ease(t, 0.10, 0.96), GalaxySSIHealthAtlasIllustratedDrawing.blue, 1)
      }
      art.label("helper_t_story_label_helper", 87, 240, 117); art.label("helper_t_story_label_b", 266, 51, 113); art.label("helper_t_story_label_other_t", 263, 314, 153)
    }
  }
  private func helperCell(_ x: Double, _ y: Double, _ size: Double) { lymphocyte(x, y, size, 0xBFE9D7, 0x66AB9D, 0x23736B) }
  private func helperDelivery(_ route: GalaxySSIHealthAtlasSectionLesson.Route, _ f: Double, _ size: Double) {
    for i in 0...4 {
      let p = f - 0.125 * Double(i)
      if p > 0 && p <= 1 { art.at(route, p) { art.endocrineDiamond($0, $1, size * (4.3 - Double(i) * 0.38), 0x236D67) } }
    }
  }
  private func helperFan(_ x: Double, _ y: Double, _ t: Double, _ tint: UInt32, _ direction: Double) {
    for i in 0...2 {
      let r = 36 + 5 * Double(i) + 4 * t, sweep = 11 + 13 * Self.ease(t, 0.02 * Double(i), 0.65 + 0.06 * Double(i))
      art.endocrineArc(x, y, r, r, direction * (19 + 3 * Double(i)), sweep, tint, 2.2 - 0.41 * Double(i))
    }
  }
}
