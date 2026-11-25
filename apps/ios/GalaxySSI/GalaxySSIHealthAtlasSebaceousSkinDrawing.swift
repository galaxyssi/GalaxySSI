import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sebaceousSkin(_ step: Int, _ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasSebaceousGeometry
    sebaceousFill(Geometry.skin, 68, 299, 0xF7D9CA, 0xECC2BB, 0xC29390)
    var clipped = context; clipped.clip(to: Geometry.skin)
    let skin = copy(clipped)
    skin.stroke(Geometry.skinEdge, 0xEDAAA6, 21)
    skin.stroke(Geometry.skinEdge, 0xCF999C, 1.2)
    skin.stroke(Geometry.skinSurface, 0xD39389, 5)
    sebaceousFill(Geometry.follicleWall, 75, 290, 0xF1BAB0, 0xCF8994, 0x99696B)
    stroke(Geometry.shaft, 0x875344, 9); stroke(Geometry.shaft, 0xAE7858, 3.2)
    sebaceousFill(Geometry.locatorGland, 79, 288, 0xFFEAD0, 0xE2B99E, 0x99696B)
    for point in Geometry.locatorCells {
      disc(point.x, point.y, 5.3, 0xFFE4AE, border: 0xCF9C62)
      disc(point.x + 1, point.y - 1, 1.8, 0xD69742)
    }
    line(111, 140, 94, 124, 0x99696B, 7); line(111, 140, 94, 124, 0xE6BB7F, 4.1)
    line(146, 140, 161, 140, 0x668181, 1.1); line(161, 140, 175, 166, 0x668181, 1.1)
    sebaceousLeader("sebaceous_follicle", 56, 268, 84, 93, 227)
    label("sebaceous_surface", 117, 55, 80)
    line(117, 59, 117, 67, 0x668181, 1.1)
    if step == 0 {
      let target = 18 + 12 * t
      var arc = Path()
      arc.addArc(center: CGPoint(x: 130, y: 140), radius: target, startAngle: .degrees(-100),
        endAngle: .degrees(-100 + 130 + t * 220), clockwise: false)
      stroke(arc, Self.teal, 1.8)
    }
    if step == 4 {
      for i in 0...3 {
        at(Geometry.canalTrack, GalaxySSIHealthAtlasSebaceousMotion.canal(t, i)) { x, y in
          disc(x, y, 3, 0xD69742, border: 0x9B651E)
        }
      }
    }
  }
}
