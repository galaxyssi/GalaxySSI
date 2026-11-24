import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gutLymphoidDefense(_ t: Double) {
    let g = GalaxySSIHealthAtlasGutLymphoidGeometry.self, r = GalaxySSIHealthAtlasGutLymphoidRoutes.self, m = GalaxySSIHealthAtlasGutLymphoidMotion.self
    gutLymphoidFill(g.surfaceTissue,124,305,0xF5DBC8,0xD8A9B8,0x976C78)
    gutLymphoidFill(g.mucusBand,92,123,0xE5F1E8,0xAFD4CF,0xA4C6C0)
    gutLymphoidFill(g.surfaceEpithelium,118,166,0xF7D5BB,0xE3A7A0,0x976C78)
    for cell in r.epithelialCells {
      let x = Double(cell.apical.x), y = Double(cell.apical.y), bx = Double(cell.basal.x), by = Double(cell.basal.y)
      line(x,y,bx,by,0xC59A98,0.9); oval(bx-13,by-14,bx-7,by-5,fill:0xBD8499,border:0xBF8698)
    }
    oval(80,222,128,267,top:178,bottom:255,from:0xEBD4E8,to:0xC4A0CB,border:0x895D84)
    oval(86,239,104,259,fill:0xAC84B5,border:0x895D84)
    line(106,232,116,235,Self.cream,2.4); line(108,242,119,243,Self.cream,1.8)
    line(210,163,215,168,Self.teal,1.6); line(215,168,221,162,Self.teal,1.6)
    for i in 0...2 {
      let progress = m.iga(t,i)
      if i == 0 || progress > 0 {
        at(r.igaTrack.route,m.igaDistance(progress,i)) { x,y in gutLymphoidAntibody(x,y,y < 122) }
      }
    }
    gutLymphoidDefenseLabels()
  }
}
