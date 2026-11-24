import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private static let crhSignal: UInt32 = 0x52768C, acthSignal: UInt32 = 0x75508B, cortisolSignal: UInt32 = 0xA5612C
  private static let cortisolTargets: [CGPoint] = (0..<5).compactMap { i in
    GalaxySSIHealthAtlasFunctionPath.sample(GalaxySSIHealthAtlasCorticotrophGeometry.cortisolBloodRoute,
      position: 0.19 + 0.077 * Double(i), width: 360, height: 360)?.point
  }
  func corticotrophSignal(_ step: Int, _ t: Double) {
    typealias G = GalaxySSIHealthAtlasCorticotrophGeometry
    switch step {
    case 0:
      pituitaryVessel(G.portal, 16); fill(G.hypothalamus, 0xC8C6D4); stroke(G.hypothalamus, 0x857B95, 2)
      anteriorPituitary(151, 177, 1.37, Self.acthSignal)
      for i in 0...4 { pituitaryMarker(G.portalRoute, (t - Double(i) * 0.095) / 0.56, Self.crhSignal, radius: 3.2) }
      let response = Self.pituitarySmooth((t - 0.53) / 0.41)
      if response > 0 { pituitaryRing(211, 219, 9 + 15 * response, Self.acthSignal, opacity: 1 - response, width: 2.8) }
      label("antcort_art_hypothalamus", 114, 53, 191); label("antcort_art_crh_portal", 236, 130, 194); label("antcort_art_cell", 194, 296, 219)
    case 1:
      pituitaryVessel(G.systemic, 13); anteriorPituitary(18, 98, 0.96, Self.acthSignal)
      fill(G.kidney, 0xD99B9B); stroke(G.kidney, 0x965C6C, 2); fill(G.adrenal, 0xEED19C); stroke(G.adrenal, 0xA16148, 2.2)
      for i in 0...4 { pituitaryMarker(G.systemicRoute, (t - Double(i) * 0.082) / 0.65, Self.acthSignal, radius: 4.1, angular: true) }
      let arrived = (t - 0.64) / 0.31
      if (0...1).contains(arrived) {
        var local = context; local.opacity = Double(Int(255 * (1 - arrived))) / 255
        copy(local).stroke(G.adrenal, Self.acthSignal, 2.3 + arrived * 3)
      }
      label("antpit_art_anterior", 67, 185, 119); label("antcort_art_adrenal", 277, 68, 140)
      label("antcort_art_acth_blood", 157, 285, 190); label("antcort_art_kidney", 283, 279, 73)
    case 2:
      fill(G.cortexSection, 0xE5B477); stroke(G.cortexSection, 0xA16148, 2.2)
      fill(G.fasciculata, 0xF5D9A5); stroke(G.fasciculata, 0xC18A55, 1.6)
      fill(G.reticularis, 0xDCA38D); stroke(G.reticularis, 0xA66B62, 1.6)
      fill(G.medulla, 0xBC8E9F); stroke(G.medulla, 0x875875, 1.6)
      let f = Self.pituitarySmooth((t - 0.07) / 0.84)
      var clipped = context; clipped.clip(to: G.fasciculata); clipped.opacity = Double(Int(255 * 0.34)) / 255
      copy(clipped).pituitaryTrace(G.cortexArcRoute, f - 0.32, f, Self.cortisolSignal, 15)
      line(227, 69, 201, 127, 0xA16148, 1.4); line(183, 265, 183, 207, 0x875875, 1.4)
      label("antcort_art_cortex", 92, 56, 137); label("antcort_art_fasciculata", 258, 56, 175); label("antcort_art_medulla", 183, 287, 125)
    default:
      pituitaryVessel(G.cortisolBlood, 21)
      for row in 0...3 { for col in 0...6 {
        let x = 64 + Double(col) * 21, y = 116 + Double(row) * 28 + Double(col % 2) * 8
        oval(x - 10, y - 13, x + 10, y + 14, fill: 0xF4D5A5, border: 0xC99669); disc(x, y, 3.6, 0xBB8874)
      } }
      guard Self.cortisolTargets.count == 5 else { return }
      for i in 0...4 {
        let p = (t - 0.07 - 0.115 * Double(i)) / 0.36
        if (0...1).contains(p) {
          let target = Self.cortisolTargets[i], y = target.y - 5, f = Self.pituitarySmooth(p), origin = i % 2 == 0 ? 187.0 : 191.0
          disc(origin + (target.x - origin) * f, y + 5 * f, 3.5, Self.cortisolSignal)
          if p < 0.55 { pituitaryRing(origin, y, 5 + p * 11, Self.cortisolSignal, opacity: 1 - p / 0.55, width: 1.5) }
        }
        let exit = t - 0.43 - 0.115 * Double(i)
        if exit >= 0 { pituitaryMarker(G.cortisolBloodRoute, 0.19 + 0.077 * Double(i) + exit * 1.25, Self.cortisolSignal, radius: 3.7) }
      }
      label("antcort_art_fasciculata", 122, 71, 196); label("antcort_art_cortisol_blood", 231, 303, 232)
    }
  }
}
