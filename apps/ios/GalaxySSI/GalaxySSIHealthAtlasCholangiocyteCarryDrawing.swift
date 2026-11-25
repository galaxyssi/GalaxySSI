import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func cholangiocyteCarry(_ t: Double) {
    let g = GalaxySSIHealthAtlasCholangiocyteGeometry.self, r = GalaxySSIHealthAtlasCholangiocyteRoutes.self
    stroke(g.bowel, 0x947A8E, 48); stroke(g.bowel, 0xC8AAB9, 45)
    stroke(g.bowel, 0xE4C9CE, 37); stroke(g.bowel, 0xF9E8E1, 24)
    stroke(g.folds, 0xBD94A6, 1.4); cholangiocyteTube(g.outlet, 34)
    disc(267, 182, 6.3, 0xDCDFC5, border: 0x527B79)
    cholangiocyteRibbon(r.downstream, GalaxySSIHealthAtlasCholangiocyteMotion.stream(t, 0.29), 0.31, 0xA6CBBB, 4.2)
    for i in 0...11 {
      let f = GalaxySSIHealthAtlasCholangiocyteMotion.stream(t, 0.08*Double(i))
      at(r.downstream.route, 0.025+0.95*f) { x, y in
        let dy = Double(i % 3-1)*4.8
        switch i % 4 {
        case 0: cholangiocyteWater(x, y+dy, 3.9)
        case 2: cholangiocyteBicarbonate(x, y+dy, 3.6)
        default: cholangiocyteBile(x, y+dy, 3.4)
        }
      }
    }
  }
}
