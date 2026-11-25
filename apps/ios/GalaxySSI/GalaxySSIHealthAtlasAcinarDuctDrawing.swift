import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func acinarDuctTransit(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasAcinarGeometry
    typealias Motion = GalaxySSIHealthAtlasAcinarMotion
    acinarTube(Geometry.collectingBranches, 11, 7)
    for i in 0...7 {
      let x = 126 + Double(i) * 25.5
      acinarDuctCell(x, 145, i); acinarDuctCell(x, 193, i + 1)
    }
    acinarTube(Geometry.collectingDuct, 25, 19)
    acinarAcinus(77, 105, 0.35); acinarAcinus(71, 252, 0.34); acinarAcinus(62, 181, 0.59)
    let flow = Motion.transit(t)
    for i in 0...4 {
      at(GalaxySSIHealthAtlasAcinarRoutes.collectingTrack, (flow * 0.66 + Double(i) * 0.19).truncatingRemainder(dividingBy: 1)) { x, y in
        acinarCargo(x, y + (i % 2 == 0 ? -2 : 2), precursor: i % 2 != 0, radius: 2.7)
      }
    }
    let fluid = Motion.enrich(t)
    for i in 0...2 {
      let startX = 162 + Double(i) * 51
      let p = min(1, max(0, fluid * 1.32 - Double(i) * 0.16))
      let y = Motion.mix(i == 1 ? 201 : 161, i == 1 ? 187 : 176, p)
      acinarFluidMark(startX + 16 * p * p, y)
    }
    arrow(310, 182, 343, 182, 0x517C7A)
    acinarCargoKeys()
  }
  private func acinarDuctCell(_ x: Double, _ y: Double, _ index: Int) {
    rounded(x, y, x + 25.5, y + 28, 4.5, 0x8BA6A1)
    rounded(x + 0.9, y + 1, x + 24.6, y + 27, 3.5, index % 2 == 0 ? 0xE4E8D9 : 0xD3E4D9)
    oval(x + 7, y + 8, x + 18.5, y + 18, fill: 0x9AB5AD, border: 0x517C7A)
  }
}
