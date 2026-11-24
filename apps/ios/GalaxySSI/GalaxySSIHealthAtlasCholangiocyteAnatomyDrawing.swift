import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func cholangiocyteEnter(_ t: Double) {
    let g = GalaxySSIHealthAtlasCholangiocyteGeometry.self, r = GalaxySSIHealthAtlasCholangiocyteRoutes.self
    gradient(g.hepaticTissue, 78, 258, 0xF3E7ED, 0xBEADC8); stroke(g.hepaticTissue, 0x937F9D, 1.15)
    stroke(g.hepaticVeils, 0xEBDAE6, 3.2); stroke(g.hepaticVeils, 0xF9ECED, 1.15)
    cholangiocyteTube(g.ductTwigs, 5.5); cholangiocyteTube(g.smallDucts, 12)
    cholangiocyteTube(g.trunk, 23); stroke(g.smallDucts, 0xF0F2D3, 5.1)
    for (i, track) in [r.orientLeft, r.orientRight].enumerated() {
      for j in 0...2 {
        let f = GalaxySSIHealthAtlasCholangiocyteMotion.stream(t, 0.05+Double(i)*0.08+Double(j)*0.28)
        at(track.route, f) { x, y in cholangiocyteBile(x, y, 3.5) }
      }
    }
  }
  func cholangiocyteLining(_ t: Double) {
    let g = GalaxySSIHealthAtlasCholangiocyteGeometry.self, r = GalaxySSIHealthAtlasCholangiocyteRoutes.self
    gradient(g.wallFloor, 239, 297, 0xCECBDC, 0xF2E8E6); stroke(g.wallFloor, 0xB7A6BC, 1.15)
    gradient(g.openLumen, 132, 208, 0xE2EBCC, 0xB4CFB0); stroke(g.openLumen, 0x527B79, 1.15)
    for i in 0...5 {
      let x = 48+Double(i)*44
      cholangiocyteCell(x, 138+Double(i)*0.7, 44, -45, false)
      cholangiocyteCell(x, 208+Double(i)*0.7, 44, 50, i == 4)
    }
    for (i, track) in [r.ribbon0, r.ribbon1, r.ribbon2].enumerated() {
      let motion = GalaxySSIHealthAtlasCholangiocyteMotion.self
      cholangiocyteRibbon(track, motion.stream(t, 0.18*Double(i)), 0.23, 0xECF3D8, 2.4)
      for j in 0...2 {
        let p = motion.stream(t, 0.08+0.12*Double(i)+0.29*Double(j))
        at(track.route, 0.03+0.92*p) { x, y in cholangiocyteBile(x, y, 4.2) }
      }
    }
  }
}
