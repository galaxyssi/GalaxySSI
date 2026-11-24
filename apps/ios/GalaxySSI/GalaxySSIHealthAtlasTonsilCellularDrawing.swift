import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func tonsilCellular(_ t: Double, present: Bool) {
    typealias Geometry = GalaxySSIHealthAtlasTonsilGeometry
    typealias Routes = GalaxySSIHealthAtlasTonsilRoutes
    typealias Motion = GalaxySSIHealthAtlasTonsilMotion
    tonsilPane(Geometry.localTissue)
    tonsilFollicle(284, 236, 29, 34)
    for i in 0...4 {
      let x = 52 + Double(i) * 11
      disc(x, 239 + Double(i % 3) * 12, 2.3, 0xA9788C)
    }
    tonsilEpithelium(Geometry.epithelialSurface, points: Routes.epithelialPoints, width: 16)
    let reach = present ? Motion.contact(t) : 0, tip = 172 + 33 * reach
    tonsilPresenter(tip)
    if present {
      oval(204, 203, 250, 249, fill: 0xBBDCD7, border: Self.teal)
      oval(214, 210, 243, 239, fill: 0x669E98, border: Self.teal)
      tonsilAntigen(tip - 1.5, 225, 3.6)
      let glow = Motion.signal(t)
      if glow > 0 {
        var local = context; local.opacity *= Double(Int(200 * (1 - 0.65 * glow))) / 255
        let spread = 6 + 10 * glow
        for start in [221.0, 83] {
          var arc = Path()
          arc.addArc(center: CGPoint(x: 204, y: 225), radius: spread,
            startAngle: .degrees(start), endAngle: .degrees(start + 56), clockwise: false)
          copy(local).stroke(arc, Self.teal, 1.45)
        }
      }
    } else {
      let f = Motion.uptake(t)
      at(Routes.pickupTrack, f) { x, y in tonsilAntigen(x, y, 5 - 1.3 * f) }
      tonsilAntigenKey()
    }
  }
  private func tonsilPresenter(_ tip: Double) {
    let process = GalaxySSIHealthAtlasTonsilGeometry.presenter(tip)
    stroke(process, Self.violet, 5.6); stroke(process, 0xCFB0D4, 3.4)
    oval(103, 210, 149, 244, fill: 0xCFB0D4, border: Self.violet)
    oval(113, 216, 134, 231, fill: 0x9975A6, border: Self.violet)
  }
}
