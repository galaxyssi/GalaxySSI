import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func nailDivision(_ t: Double) {
    var clipped = context; clipped.clip(to: GalaxySSIHealthAtlasNailGeometry.matrix)
    let art = copy(clipped)
    for i in 0...2 {
      let frame = GalaxySSIHealthAtlasNailMotion.division(t, i)
      for side in [-1.0, 1] {
        let dx = side * frame.separation
        art.oval(frame.x + dx - frame.radius, frame.y - frame.radius - dx * 0.26,
          frame.x + dx + frame.radius, frame.y + frame.radius - dx * 0.26, fill: 0xF7D3CF, border: 0x8C526B)
        art.disc(frame.x + dx, frame.y - dx * 0.26, 1.3, 0x8C526B)
      }
    }
  }
  func nailMaturation(_ t: Double) {
    for i in 0...2 {
      let frame = GalaxySSIHealthAtlasNailMotion.maturation(t, i)
      oval(frame.x - frame.rx, frame.y - frame.ry, frame.x + frame.rx, frame.y + frame.ry, fill: 0xE6E3C9, border: Self.teal)
      var local = context; local.opacity *= Double(frame.alpha) / 255
      copy(local).disc(frame.x, frame.y, 1.45, Self.teal)
    }
  }
}
