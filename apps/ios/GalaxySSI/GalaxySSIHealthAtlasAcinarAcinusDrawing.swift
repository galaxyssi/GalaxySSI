import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func acinarLocate(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasAcinarGeometry
    let p = GalaxySSIHealthAtlasAcinarMotion.locate(t)
    acinarFilled(Geometry.septum, fill: 0xF5DCCB, edge: 0xC6A095)
    acinarTube(Geometry.lobuleDucts, 8, 5)
    acinarAcinus(53, 132, 0.37)
    acinarAcinus(120, 122, 0.34)
    acinarAcinus(65, 183, 0.37)
    acinarAcinus(119, 176, 0.40)
    acinarAcinus(53, 237, 0.36)
    acinarAcinus(100, 248, 0.34)
    let r = 31 + 4 * (1 - p)
    stroke(Path(ellipseIn: CGRect(x: 119 - r, y: 176 - r, width: 2 * r, height: 2 * r)), 0x9C693D, 1.4)
    acinarZoomGuide(143, 153, 213, 129, p)
    acinarZoomGuide(144, 198, 213, 236, p)
    acinarAcinus(263, 183, 0.93)
  }
  func acinarAcinus(_ x: Double, _ y: Double, _ scale: Double) {
    typealias Geometry = GalaxySSIHealthAtlasAcinarGeometry
    var local = context; local.translateBy(x: x, y: y); local.scaleBy(x: scale, y: scale)
    let art = copy(local)
    art.acinarTube(Geometry.acinarOutlet, 13, 8)
    for i in 1...7 {
      var rotated = local; rotated.rotate(by: .degrees(45 * Double(i)))
      let cell = copy(rotated)
      cell.acinarFilled(Geometry.acinarWedge, top: -23, bottom: 27,
        from: i % 2 == 0 ? 0xF9D6C4 : 0xF3C4B0, to: i % 2 == 0 ? 0xDB9C9D : 0xD59197, edge: 0x995E66)
      cell.oval(44, -8, 57, 9, fill: 0xB886A6, border: 0x765780)
      cell.line(38, -9, 43, -12, 0xB27C8B, 1.2); cell.line(37, 9, 44, 12, 0xB27C8B, 1.2)
      cell.disc(18, -2.3, 2.2, 0x9C693D); cell.disc(24, 3.5, 2.4, 0x9C693D); cell.disc(29, -3, 2.1, 0x9C693D)
    }
    art.disc(0, 0, 8.8, 0xD7EFEA)
  }
  private func acinarZoomGuide(_ x: Double, _ y: Double, _ endX: Double, _ endY: Double, _ progress: Double) {
    typealias Motion = GalaxySSIHealthAtlasAcinarMotion
    for i in 0...9 {
      let from = Double(i) / 10, to = min(progress, Double(i) / 10 + 0.055)
      if to > from {
        line(Motion.mix(x, endX, from), Motion.mix(y, endY, from), Motion.mix(x, endX, to), Motion.mix(y, endY, to), 0x9C693D, 1.15)
      }
    }
  }
}
