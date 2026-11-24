import SwiftUI

struct GalaxySSIHealthAtlasImmuneDrawing {
  let art: GalaxySSIHealthAtlasIllustratedDrawing
  static func ease(_ t: Double, _ start: Double = 0, _ end: Double = 1) -> Double {
    let f = min(1, max(0, (t - start) / (end - start))); return f * f * (3 - 2 * f)
  }
  func lymphocyte(_ x: Double, _ y: Double, _ size: Double, _ from: UInt32, _ to: UInt32, _ edge: UInt32) {
    var local = art.context; local.translateBy(x: x, y: y); local.scaleBy(x: size, y: size)
    let cell = art.copy(local), rim = GalaxySSIHealthAtlasImmuneGeometry.lymphocyteRim
    cell.gradient(rim, -43, 43, from, to); cell.stroke(rim, edge, 1.6)
    cell.oval(-30, -32, 23, 30, fill: 0x94839F, border: 0x66556F)
    cell.oval(-24, -26, 16, 23, fill: 0xA897B4, border: 0xA897B4); cell.disc(-12, -12, 4, 0xC9B9D3)
    cell.endocrineArc(0, 0, 37, 37, 207, 43, GalaxySSIHealthAtlasIllustratedDrawing.cream, 2)
  }
}
