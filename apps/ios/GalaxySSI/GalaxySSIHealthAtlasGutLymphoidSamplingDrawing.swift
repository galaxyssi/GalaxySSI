import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gutLymphoidSamplingAnatomy() {
    let g = GalaxySSIHealthAtlasGutLymphoidGeometry.self, r = GalaxySSIHealthAtlasGutLymphoidRoutes.self
    gutLymphoidFill(g.mucosa,124,305,0xF5DBC8,0xD8A9B8,0x976C78); stroke(g.deepEdge,0xC58FA4,2)
    gutLymphoidFollicle(91,247,37,39); gutLymphoidFollicle(288,249,31,39)
    gutLymphoidFill(g.domeEpithelium,118,166,0xF7D5BB,0xE3A7A0,0x976C78); stroke(g.dome,0xEAB7AD,3.5)
    for point in r.domeMarkers {
      let x = Double(point.x), y = Double(point.y)
      if x < 152 || x > 187 { disc(x,y+4,1.35,0x895D84) }
    }
    fill(g.mCell,0xB9D6CF); stroke(g.mCell,Self.teal,1.35)
    oval(158,150,165,160,fill:0x84ABA5,border:Self.teal)
    line(162,129,165,128,Self.teal,1.15); line(170,128,173,128,Self.teal,1.15); line(178,129,181,130,Self.teal,1.15)
    gutLymphoidMCellLabels()
  }
  func gutLymphoidSampling(_ t: Double) {
    gutLymphoidSamplingAnatomy(); gutLymphoidDendritic(182)
    let progress = GalaxySSIHealthAtlasGutLymphoidMotion.uptake(t)
    at(GalaxySSIHealthAtlasGutLymphoidRoutes.sampleTrack.route,progress) { x,y in
      if (135...167).contains(y) { disc(x,y,8,0xFAE2B1,border:0xA77336) }
      gutLymphoidProtein(x,y,4.5)
    }
    gutLymphoidProtein(44,60,4.5)
    gutLymphoidSamplingLabels()
  }
}
