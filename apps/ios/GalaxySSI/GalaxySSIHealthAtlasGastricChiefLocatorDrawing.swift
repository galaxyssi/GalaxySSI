import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gastricChiefLocate(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasGastricChiefGeometry
    gastricChiefTint(Geometry.stomach, 84, 250, 0xF6C9B6, 0xD78C91)
    stroke(Geometry.stomach, 0x9A6470, 1.8)
    stroke(Geometry.stomachFolds, 0xF9D0C0, 5); stroke(Geometry.stomachFolds, Self.coral, 1.2)
    stroke(Path(ellipseIn: CGRect(x: 99, y: 133, width: 24, height: 24)), 0x9B622F, 1.7)
    line(123, 141, 169, 103, 0x56696E, 1); line(121, 151, 169, 231, 0x56696E, 1)
    gastricChiefTint(Geometry.glandWall, 82, 274, 0xFBE8DA, 0xE5B3AD)
    stroke(Geometry.glandWall, 0x9A6470, 1.45)
    for i in 0...5 {
      gastricChiefGlandCell(215 - 2 * Double(i), 115 + 28 * Double(i), isChief: i >= 4, isParietal: i == 2)
      gastricChiefGlandCell(283 - Double(i), 117 + 28 * Double(i), isChief: i >= 4, isParietal: i == 1 || i == 3)
    }
    gastricChiefGlandCell(221, 268, isChief: true, isParietal: false)
    gastricChiefGlandCell(250, 284, isChief: true, isParietal: false)
    gastricChiefGlandCell(280, 267, isChief: true, isParietal: false)
    fill(Geometry.glandLumen, 0xD6E9E5); stroke(Geometry.glandLumen, 0x568184, 1.4)
    let p = GalaxySSIHealthAtlasGastricChiefMotion.locate(t)
    at(GalaxySSIHealthAtlasGastricChiefRoutes.locateTrack, p) { x, y in disc(x, y, 4.8, 0x9B622F, border: Self.cream) }
    stroke(Path(ellipseIn: CGRect(x: 191, y: 228, width: 112, height: 69)), 0x9B622F, 1 + 1.2 * p)
  }
  private func gastricChiefGlandCell(_ x: Double, _ y: Double, isChief: Bool, isParietal: Bool) {
    var local = context
    local.translateBy(x: x, y: y)
    if x > 250 { local.scaleBy(x: -1, y: 1) }
    let art = copy(local), border: UInt32 = isChief ? 0x6D6088 : 0x9A6470
    if isParietal {
      art.oval(-24, -15, 24, 15, fill: 0xEDB7A5, border: border)
      art.disc(0, 1, 4.6, 0xB88097, border: border)
    } else {
      let cell = GalaxySSIHealthAtlasGastricChiefGeometry.glandEpithelialCell
      art.fill(cell, isChief ? 0xDCD3ED : 0xF4D8C9); art.stroke(cell, border, 1)
      art.oval(-19, -4, -8, 5, fill: 0xA18BB9, border: border)
      if isChief {
        art.disc(7, -4, 2.6, Self.violet)
        art.disc(13, 3, 2.1, Self.violet)
      }
    }
  }
}
