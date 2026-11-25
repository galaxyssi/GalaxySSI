import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private func gastricChiefCloseUp() {
    typealias Geometry = GalaxySSIHealthAtlasGastricChiefGeometry
    gastricChiefTint(Geometry.closeLumen, 67, 289, 0xE5F2EC, 0xC2E0DD)
    gastricChiefTint(Geometry.lumenWall, 82, 274, 0xFBE8DA, 0xE5B3AD)
    stroke(Geometry.lumenWall, 0x9A6470, 1.4)
    for i in 0...5 {
      let y = 105 + 27 * Double(i)
      oval(307, y - 5, 321, y + 5, fill: 0xC790A6, border: 0x9A6470)
      if i < 5 { line(295, y + 13, 331, y + 15, 0x9A6470, 0.9) }
    }
    gastricChiefTint(Geometry.chief, 94, 263, 0xF0E4EF, 0xB5A5D0)
    stroke(Geometry.chief, 0x6D6088, 1.9)
    stroke(Geometry.rER, 0x9984AE, 2.4)
    for i in 0...5 {
      let f = Double(i)
      disc(91 + 7 * f, 134 + 0.45 * (f - 2) * (f - 2), 1.2, 0x6D6088)
      disc(92 + 7 * f, 243 - 0.45 * f * f, 1.2, 0x6D6088)
    }
    oval(65, 162, 127, 222, fill: 0xA18BB9, border: 0x6D6088)
    oval(75, 171, 114, 210, fill: 0xBCAAD0, border: 0xA18BB9)
    disc(96, 192, 6, 0x6D6088, border: 0xA18BB9)
    gastricChiefGranule(186, 130, 8.5); gastricChiefGranule(187, 157, 7.8)
    gastricChiefGranule(174, 205, 7); gastricChiefGranule(186, 245, 8.4)
  }
  func gastricChiefPack(_ t: Double) {
    gastricChiefCloseUp()
    for (i, route) in GalaxySSIHealthAtlasGastricChiefRoutes.packTracks.enumerated() {
      let p = GalaxySSIHealthAtlasGastricChiefMotion.pack(t, i)
      at(route, p) { x, y in gastricChiefGranule(x, y, 4.4 + 4.6 * p) }
    }
  }
  func gastricChiefRelease(_ t: Double) {
    gastricChiefCloseUp()
    let p = GalaxySSIHealthAtlasGastricChiefMotion.dock(t)
    if p < 0.90 {
      gastricChiefGranule(181 + 36 * p, 183 + 12 * p, 9)
    } else {
      // The open membrane pocket stays fixed while its cargo moves into the lumen.
      let pore = GalaxySSIHealthAtlasGastricChiefGeometry.fusionPore
      line(226, 184, 226, 206, 0xCFE5E0, 3.4)
      fill(pore, 0xCFE5E0); stroke(pore, 0x6D6088, 1.4)
      if GalaxySSIHealthAtlasGastricChiefMotion.release(t, 0) == 0 { gastricChiefMolecule(219, 195, 4, cleavage: 0) }
    }
    for (i, route) in GalaxySSIHealthAtlasGastricChiefRoutes.secretionTracks.enumerated() {
      let f = GalaxySSIHealthAtlasGastricChiefMotion.release(t, i)
      if f > 0 { at(route, f) { x, y in gastricChiefMolecule(x, y, 5.6, cleavage: 0) } }
    }
    gastricChiefMolecule(270, 103, 6.4, cleavage: 0)
  }
}
