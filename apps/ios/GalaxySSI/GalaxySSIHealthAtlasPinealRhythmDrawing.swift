import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func pinealRhythm(_ t: Double) {
    let g = GalaxySSIHealthAtlasPinealGeometry.self
    rounded(34, 123, 326, 270, 6, 0xFBF6E8); rounded(119, 123, 250, 270, 0, 0xE6E7F1)
    gradient(g.curveArea, 130, 278, 0xCABCE0, 0xF0EDF5)
    for y in stride(from: 151.0, through: 241, by: 30) { line(34, y, 326, y, 0xCBD5DC, 0.9) }
    line(34, 126, 34, 270, 0x55727D, 1.3); line(34, 270, 326, 270, 0x55727D, 1.3)
    stroke(g.curve, 0x73518E, 3.2)
    let f = GalaxySSIHealthAtlasPinealMotion.phase(t), x = g.cycleX(f), y = g.cycleY(f)
    line(x, 122, x, 270, 0x8393A7, 1.05); disc(x, y, 6.2, 0x73518E, border: 0xFAFFFF)
    pinealSun(76, 75, 9); pinealCrescent(184, 75, 10, 0xF4F8FA); pinealSun(288, 75, 9)
  }
}
