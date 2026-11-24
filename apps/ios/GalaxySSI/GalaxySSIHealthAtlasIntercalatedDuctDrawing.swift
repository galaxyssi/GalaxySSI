import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func intercalatedDuct() {
    typealias Geometry = GalaxySSIHealthAtlasIntercalatedGeometry
    gradient(Geometry.lumen, 64, 157, 0xD1E8E9, 0xEBF6F1)
    fill(Geometry.oppositeWall, 0xD9E4D8); stroke(Geometry.oppositeWall, 0x668780, 1.2)
    for i in 0...4 {
      let x = 55 + Double(i) * 55, y = 60 - Double(i) * 0.65
      oval(x - 10, y - 3.2, x + 10, y + 3.2, fill: 0x94ADA1, border: 0x668780)
      line(x + 26, y - 11, x + 28, y + 11, 0xA3B7A9, 1)
    }
    gradient(Geometry.nearWall, 147, 232, 0xE6F0E7, 0xB9D1C3)
    stroke(Geometry.nearWall, 0x668780, 1.3)
    line(278, 149, 274, 231, 0x668780, 1.2)
    intercalatedNucleus(71, 181, 0x9CB9AD, 0x668780)
    intercalatedNucleus(249, 189, 0x9CB9AD, 0x668780)
    intercalatedNucleus(308, 191, 0x9CB9AD, 0x668780)
    for i in 0...2 {
      let x = 57 + Double(i) * 7
      line(x, 150, x + 1, 146, 0x668780, 1.1)
    }
    gradient(Geometry.typeA, 134, 231, 0xF8DDD0, 0xE5AEB0)
    stroke(Geometry.typeA, 0x97606E, 1.6)
    intercalatedNucleus(169, 185, 0xBD8999, 0x97606E)
    for i in 0...4 {
      let x = 164 + 8 * Double(i), y = 131 + 0.01 * (x - 167) * (x - 167)
      line(x, y + 0.2, x + 1, y - 5.5, 0x97606E, 1.45)
    }
    for i in 0...2 {
      let x = 179 + Double(i) * 8
      oval(x - 3, 152 + 3 * Double(i), x + 3, 156 + 3 * Double(i), fill: 0xE1AA9F, border: 0x97606E)
    }
    rounded(145, 132, 157, 143, 3, 0xA02E40)
    oval(146, 140, 156, 148, fill: 0xE5A7A4, border: 0xA02E40)
    rounded(194, 224, 208, 233, 2.5, 0x246E61)
    line(198, 228, 204, 228, 0xEBF6EA, 1.2)
  }
  private func intercalatedNucleus(_ x: Double, _ y: Double, _ color: UInt32, _ border: UInt32) {
    oval(x - 12, y - 8, x + 12, y + 8, fill: color, border: border)
    disc(x - 3, y + 1, 2.4, border)
  }
  func intercalatedCapillary(_ f: Double) {
    let capillary = GalaxySSIHealthAtlasIntercalatedGeometry.capillary
    gradient(capillary, 265, 304, 0xF7DDD2, 0xEDC1BF); stroke(capillary, 0xA4616A, 1.55)
    var clipped = context; clipped.clip(to: capillary)
    for i in 0...4 {
      let x = 23 + (16 + Double(i) * 64 + f * 132).truncatingRemainder(dividingBy: 320), y = 282 + 6 * Double(i % 2)
      var local = clipped
      local.translateBy(x: x, y: y); local.rotate(by: .degrees(i % 2 == 0 ? -13 : 17))
      let art = copy(local)
      art.oval(-10, -4.7, 10, 4.7, fill: 0xD7898B, border: 0xA4616A)
      art.oval(-5, -1.8, 5, 1.8, fill: 0xEFB3A9, border: 0xC58083)
    }
  }
}
