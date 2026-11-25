import SwiftUI

extension GalaxySSIHealthAtlasImmuneDrawing {
  func mastScene(_ step: Int, _ t: Double) {
    switch step {
    case 0: mastSites(t)
    case 1:
      mastCell(180, 172, 1.46, 0)
      art.endocrineArc(180, 172, 71, 71, -161 + 165 * Self.ease(t), 54, GalaxySSIHealthAtlasIllustratedDrawing.cream, 2.4)
      art.line(141, 187, 100, 274, 0x6E476B, 1.5); art.line(211, 241, 265, 274, 0x6E476B, 1.5)
      art.disc(141, 187, 2.5, GalaxySSIHealthAtlasIllustratedDrawing.cream, border: 0x6E476B)
      art.disc(211, 241, 2.5, GalaxySSIHealthAtlasIllustratedDrawing.cream, border: 0x6E476B)
      art.label("mast_story_label_cell", 180, 52, 230); art.label("mast_story_label_nucleus", 88, 297, 130); art.label("mast_story_label_granules", 270, 297, 132)
    case 2:
      mastCell(111, 171, 1.16, t); mastReleased(t)
      art.label("mast_story_label_cell", 111, 282, 128); art.label("mast_story_label_contents", 254, 282, 153)
    default:
      art.oval(33, 262, 327, 308, fill: 0xEFC6C7, border: 0xAB6875); art.oval(45, 269, 315, 301, fill: 0xFBE5DE, border: 0xAB6875)
      for i in 0...5 {
        let x = 77 + Double(i) * 40, y = 267 - 4.5 * art.wave((Double(i) + 0.5) / 12)
        art.oval(x - 7, y, x + 7, y + 5, fill: 0xBE8E9C, border: 0xAB6875)
      }
      mastCell(111, 171, 1.16, 1); mastReleased(1, spread: t)
      art.label("mast_story_label_tissue", 249, 49, 174); art.label("mast_story_label_vessel", 180, 332, 220)
    }
  }
  private func mastSites(_ t: Double) {
    art.label("mast_story_label_resident", 180, 37, 280)
    for (i, item) in [("skin", UInt32(0xAB6875)), ("airway", 0x598C91), ("gut", 0xBB8560)].enumerated() {
      let (name, edge) = item, y = 91 + Double(i) * 97, focus = min(1, max(0, 1 - abs(t * 2 - Double(i))))
      var context = art.context; context.translateBy(x: 28, y: y)
      let local = art.copy(context), immune = Self(art: local)
      local.rounded(0, -22, 178, 35, 4, 0xF2DFD5)
      if i == 0 {
        local.fill(GalaxySSIHealthAtlasImmuneGeometry.skinTop, 0xE4A7A5); local.stroke(GalaxySSIHealthAtlasImmuneGeometry.skinTop, edge, 1.2)
      } else if i == 1 {
        local.oval(4, -22, 112, 19, fill: 0x94BCBD, border: edge); local.oval(11, -17, 105, 14, fill: 0xE2F2EE, border: edge)
        for j in 0...6 { local.line(25 + Double(j) * 11, -12, 27 + Double(j) * 11, -7, edge, 1) }
      } else {
        local.fill(GalaxySSIHealthAtlasMastGeometry.gutTop, 0xEDC3A5); local.stroke(GalaxySSIHealthAtlasMastGeometry.gutTop, edge, 1.2)
      }
      local.oval(34, 22, 113, 31, fill: 0xD9A1A5, border: 0xAB6875)
      let x = i == 0 ? 122.0 : 139.0, mastY = i == 0 ? 12.0 : 22.0, r = 12 + 6 * focus
      local.stroke(Path(ellipseIn: CGRect(x: x - r, y: mastY - r, width: 2 * r, height: 2 * r)), 0x6E476B, 1 + 1.6 * focus)
      immune.mastCell(x, mastY, 0.19, 0)
      art.line(215, y + 4, 230 + 12 * focus, y + 4, edge, 1.6 + focus); art.label("mast_story_label_" + name, 286, y + 8, 96)
    }
  }
  private func mastCell(_ x: Double, _ y: Double, _ size: Double, _ release: Double) {
    typealias G = GalaxySSIHealthAtlasMastGeometry
    var context = art.context; context.translateBy(x: x, y: y); context.scaleBy(x: size, y: size)
    let local = art.copy(context), shell = GalaxySSIHealthAtlasImmuneGeometry.shell
    local.gradient(shell, -60, 60, 0xEDC9E0, 0xBD84AD); local.stroke(shell, 0x6E476B, 1.6)
    local.oval(-38, -24, 8, 25, fill: 0x88658F, border: 0x6E476B); local.oval(-33, -20, 2, 21, fill: 0xA387AD, border: 0xA387AD)
    for (i, granule) in G.granules.enumerated() {
      let releasing = (4...9).contains(i)
      let f = releasing ? Self.ease(release, 0.04 + 0.071 * Double(i - 4), G.fusionPhase(i - 4)) : 0
      if f < 1 {
        let x = releasing ? granule.x + (G.releaseRim[i - 4] - granule.x) * f : granule.x
        local.disc(x, granule.y, (4.9 + Double(i % 3)) * (1 - 0.75 * f), 0x8C4171, border: GalaxySSIHealthAtlasIllustratedDrawing.cream)
      }
    }
  }
  private func mastReleased(_ release: Double, spread: Double = 0) {
    typealias G = GalaxySSIHealthAtlasMastGeometry
    for i in 0..<6 {
      let out = Self.ease(release, G.fusionPhase(i), 0.62 + 0.073 * Double(i))
      if out <= 0 { continue }
      let f = Self.ease(spread, 0.02 + 0.034 * Double(i), 0.74 + 0.042 * Double(i))
      let x = 111 + 1.16 * G.releaseRim[i] + (50 * out + 72 * f) * G.spokesX[i]
      let y = 171 + 1.16 * G.granules[i + 4].y + (20 * out + 22 * f) * G.spokesY[i], r = 2 + 1.8 * out - 1.65 * f
      art.disc(x, y, r, 0xB05A48)
      if out > 0.18 { art.disc(x + 8 * out + 6 * f, y - 4 * out + 7 * f, r * 0.63, 0xB05A48) }
    }
  }
}
