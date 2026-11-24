import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func cholangiocyteExchange(_ t: Double) {
    cholangiocyteCloseWall()
    let g = GalaxySSIHealthAtlasCholangiocyteGeometry.self, r = GalaxySSIHealthAtlasCholangiocyteRoutes.self
    stroke(g.bicarbonateCourse, 0x93B9A4, 1.6); stroke(g.chlorideCourse, 0xB798BD, 1.6)
    cholangiocyteChevron(129, 114, -1, -0.48, 0x2B7569)
    cholangiocyteChevron(208, 197, 0.26, 1, 0x77528B)
    for p in [g.exchangerLeft, g.exchangerMiddle, g.exchangerRight] {
      stroke(p, 0x2B7569, 6); stroke(p, 0xBDD0B4, 3)
    }
    for i in 0...2 {
      let p = GalaxySSIHealthAtlasCholangiocyteMotion.exchange(t, i)
      if p > 0 {
        let fan = max(0, (p-0.9)*10)
        at(r.bicarbonateTrack.route, p) { x, y in
          cholangiocyteBicarbonate(x-fan*(10+Double(i)*13), y+fan*13, 4.6)
        }
        at(r.chlorideTrack.route, p) { x, y in
          cholangiocyteChloride(x+fan*Double(i)*4, y+fan*(4+Double(i)*8), 4.3)
        }
      }
    }
    cholangiocyteBicarbonate(116, 108, 5.2); cholangiocyteChloride(245, 108, 4.7)
  }
  func cholangiocyteOsmosis(_ t: Double) {
    cholangiocyteCloseWall()
    let g = GalaxySSIHealthAtlasCholangiocyteGeometry.self, r = GalaxySSIHealthAtlasCholangiocyteRoutes.self
    stroke(g.waterCourse, 0xADD0D8, 8); stroke(g.waterCourse, 0xF0F8EF, 2.5)
    cholangiocyteChevron(216, 166, 0, -1, 0x326C95)
    cholangiocytePore(214, 153); cholangiocytePore(199, 246)
    for i in 0...3 {
      let p = GalaxySSIHealthAtlasCholangiocyteMotion.osmosis(t, i)
      if p > 0 {
        let fan = max(0, (p-0.9)*10)
        at(r.waterTrack.route, p) { x, y in
          cholangiocyteWater(x+fan*Double(i)*8, y+fan*(Double(i % 2)*11-4), 5.1)
        }
      }
    }
    for i in 0...2 {
      let x = 78+Double(i)*29+GalaxySSIHealthAtlasCholangiocyteMotion.stream(t, 0.2*Double(i))*18
      cholangiocyteBicarbonate(x, 130-Double(i)*4, 3.8)
    }
  }
}
