import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ependymalStream(_ track: GalaxySSIHealthAtlasEpendymalRoutes.Track, _ t: Double,
    _ speed: Double, _ beads: Int) {
    stroke(track.path, 0x4477B9D1, 13); stroke(track.path, 0xA0EEFBFF, 2)
    for i in 0..<beads {
      let f = (Double(i)/Double(beads)+speed*t).truncatingRemainder(dividingBy: 1)
      let size = min(f*8, (1-f)*8, 1)
      at(track.route, f) { x, y in disc(x, y, (2.1+Double(i % 2)*0.7)*size, 0x3C839E) }
    }
    at(track.route, 0.77) { x, y in at(track.route, 0.85) { tx, ty in arrow(x, y, tx, ty, 0x3C839E) } }
  }
  func ependymalLocator() {
    let g = GalaxySSIHealthAtlasEpendymalGeometry.self
    disc(74, 83, 56, 0xF7F9FD, border: 0xC2CDE0)
    fill(g.brainSection, 0xD9D8EC); stroke(g.brainSection, 0x8D88AE, 1.1)
    line(74, 54, 74, 72, 0x9992B3, 1.2)
    for mirror in 0...1 {
      var c = context
      if mirror == 1 { c.translateBy(x: 74, y: 83); c.scaleBy(x: -1, y: 1); c.translateBy(x: -74, y: -83) }
      let art = copy(c)
      art.fill(g.ventricularHorn, 0x70B1C6); art.stroke(g.ventricularHorn, 0x3C839E, 1.1)
    }
    oval(71, 85, 77, 99, fill: 0x70B1C6, border: 0x3C839E)
    label("ependymal_story_ventricles", 74, 156, 135)
    line(119, 116, 145, 172, 0x647C9A, 1.1); line(145, 172, 155, 172, 0x647C9A, 1.1)
  }
}
