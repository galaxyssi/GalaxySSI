import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func acinarArrive(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasAcinarGeometry
    stroke(Geometry.duodenum, 0x9F6066, 46); stroke(Geometry.duodenum, 0xD99B94, 42)
    stroke(Geometry.duodenum, 0xF0BCB0, 34); stroke(Geometry.duodenum, 0xFAE4CF, 24)
    stroke(Geometry.duodenalFolds, 0xCB9687, 1.4)
    acinarFilled(Geometry.pancreas, top: 115, bottom: 238, from: 0xF7D4AB, to: 0xD9967C, edge: 0x9E6659)
    stroke(Geometry.lobularScallops, 0xBF8878, 1.25)
    acinarTube(Geometry.pancreaticDuct, 11, 7)
    disc(297, 184, 4.2, 0xD7EFEA, border: 0x517C7A)
    let p = GalaxySSIHealthAtlasAcinarMotion.arrive(t)
    for i in 0...4 {
      let f = 0.30 + 0.68 * p - 0.065 * Double(i)
      at(GalaxySSIHealthAtlasAcinarRoutes.deliveryTrack, f) { x, y in
        if i % 3 == 2 { acinarFluidMark(x, y) }
        else { acinarCargo(x, y, precursor: i % 3 == 1, radius: 2.65) }
      }
    }
    arrow(214, 260, 193, 261, 0x9A6259)
  }
}
