import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sinusRise(_ t: Double) {
    typealias Routes = GalaxySSIHealthAtlasSinusRoutes
    typealias Motion = GalaxySSIHealthAtlasSinusMotion
    sinusFilm(Routes.ascent, 0, 1, 0x9BC8B6, 4)
    for anchor in Routes.cilia {
      let point = anchor.sample.point, tangent = anchor.sample.direction
      let tangentX = Double(tangent.dx), tangentY = Double(tangent.dy)
      let bend = Motion.ciliumBend(t, anchor.index) * 4
      let x = Double(point.x) - 2 * tangentY, y = Double(point.y) + 2 * tangentX
      var cilium = Path()
      cilium.move(to: CGPoint(x: x, y: y))
      cilium.addQuadCurve(to: CGPoint(x: x + 6 * tangentY + bend * tangentX, y: y - 6 * tangentX + bend * tangentY),
        control: CGPoint(x: x + 3 * tangentY, y: y - 3 * tangentX))
      stroke(cilium, 0x457970, 1.15)
    }
    for i in 0...2 {
      let head = Motion.ascent(t, i)
      sinusFilm(Routes.ascent, head - 0.10, head, 0x12695F, 4.4)
    }
    arrow(178, 228, 187, 207, 0x12695F); arrow(185, 195, 187, 174, 0x12695F)
  }
  func sinusEnterNose(_ t: Double) {
    typealias Routes = GalaxySSIHealthAtlasSinusRoutes
    sinusFilm(Routes.ascent, 0.06, 1, 0x9BC8B6, 3.3)
    sinusFilm(Routes.exit, 0, 1, 0x9BC8B6, 4)
    for i in 0...2 {
      let head = GalaxySSIHealthAtlasSinusMotion.exit(t, i)
      sinusFilm(Routes.exit, head - 0.12, head, 0x12695F, 4.4)
    }
    arrow(241, 185, 267, 185, 0x12695F)
  }
}
