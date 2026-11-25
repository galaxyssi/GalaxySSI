import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func thoracicFront(_ b: Double, bucket: Bool = false, cutaway: Bool = false) {
    let m = GalaxySSIHealthAtlasThoracicMotion.self, g = GalaxySSIHealthAtlasThoracicGeometry.self
    thoracicSpine(180, 60, 14.7, side: false)
    for side in [-1.0, 1.0] {
      var c = context; c.translateBy(x: 180, y: 0); c.scaleBy(x: side, y: 1)
      let art = copy(c)
      for i in m.lateral.indices { art.thoracicRibbon(g.rearRib(i,b), 0xAEBDC4, 0xDCE5E6, 5.8) }
      if cutaway { art.thoracicFrontLung(b, heartSide: side > 0) }
      if bucket { art.thoracicDashed(g.frontRib(7,0), 1.25) }
      for i in m.lateral.indices {
        let strong = bucket && (5...8).contains(i)
        art.thoracicRibbon(g.frontRib(i,b), strong ? 0x2C766E : cutaway ? 0xA3B3BA : 0x81949B,
          strong ? 0xD1E9DC : cutaway ? 0xE3EDEF : 0xF1F1E7, strong ? 8.1 : (i == 0 || i >= 10) ? 5.4 : 7.1)
      }
      for i in 0...5 { art.thoracicRibbon(g.cartilage(i,b), 0x658893, 0xBDDEE3, 5.8) }
      art.thoracicRibbon(g.costalMargin(b), 0x658893, 0xBDDEE3, 6.3)
    }
    var c = context; c.translateBy(x: 180, y: -6*b)
    let art = copy(c), bone = GalaxySSIHealthAtlasThoracicSternum.self
    art.thoracicWashed(bone.front, 65, 211, 0xFFF0E3, 0xCEB5BD, 0x8B536B)
    art.line(-10, 99, 10, 99, 0xB791A0, 1.3); art.line(-4, 195, 4, 195, 0xB791A0, 1.1)
    art.stroke(bone.relief, 0xF9E8E4, 2.6)
  }
}
