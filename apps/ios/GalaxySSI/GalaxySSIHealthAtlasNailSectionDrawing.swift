import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func nailSection(emphasizeBed: Bool) {
    typealias Geometry = GalaxySSIHealthAtlasNailGeometry
    typealias Motion = GalaxySSIHealthAtlasNailMotion
    gradient(Geometry.finger, 140, 286, 0xF7D6BF, 0xE8AD9E)
    stroke(Geometry.outerSkin, 0xA76E64, 9); stroke(Geometry.outerSkin, 0xE9B09B, 6)
    gradient(Geometry.phalanx, 190, 255, 0xFFEFD1, 0xE3BD95)
    stroke(Geometry.phalanx, 0xAD8465, 1.7)
    for i in 0...11 {
      let x = 82 + Double(i) * 14, y = 241 - 0.0009 * (x - 81) * (x - 81)
      line(x, y, x + 5, y - 5, 0xD1A781, 1.2)
    }
    for i in 0...6 {
      let x = 173 + Double(i) * 15, y = 265 - 0.0036 * (x - 199) * (x - 199)
      line(x, y, x + 3, y - 11, 0xC68F7D, 1)
    }
    fill(Geometry.bed, emphasizeBed ? 0xB66D77 : 0xD68F95); stroke(Geometry.bed, 0xAB6A78, 1.1)
    for x in stride(from: 168.0, through: 265.0, by: 8) {
      let y = Motion.y(x) + Motion.thickness
      line(x, y + 2, x + 2, y + 4.5, 0xF4C5BD, 1.2)
    }
    fill(Geometry.matrix, 0xCD8FA2); stroke(Geometry.matrix, 0x8C526B, 1.4)
    for i in 0...5 {
      let x = 103 + Double(i) * 9, y = 192 - Double(i) * 3.2
      oval(x - 2.5, y - 2, x + 2.5, y + 2, fill: 0xECC0C5, border: 0x8C526B)
    }
  }
  func nailFold() {
    typealias Geometry = GalaxySSIHealthAtlasNailGeometry
    fill(Geometry.fold, 0xF6D3B9)
    stroke(Geometry.dorsalSkin, 0xA76E64, 7); stroke(Geometry.dorsalSkin, 0xE7AB94, 4.5)
    line(149, 154, 157, GalaxySSIHealthAtlasNailMotion.y(157), 0xB78573, 2.2)
  }
}
