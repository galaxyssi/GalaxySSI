import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func thoracicProfile(_ b: Double, cutaway: Bool) {
    let m = GalaxySSIHealthAtlasThoracicMotion.self, g = GalaxySSIHealthAtlasThoracicGeometry.self
    thoracicSpine(95, 67, 16, side: true)
    if cutaway { thoracicProfileLung(b) }
    else {
      for i in 1...3 { thoracicDashed(g.sideRib(i), 1.15) }
      thoracicDashed(GalaxySSIHealthAtlasThoracicSternum.side(0), 1.4)
    }
    for i in stride(from: 6, through: 0, by: -1) {
      let strong = !cutaway && (1...3).contains(i), px = m.rearX(i), py = m.rearY(i)
      var c = context; c.translateBy(x: px, y: py); c.rotate(by: .degrees(-8*b)); c.translateBy(x: -px, y: -py)
      copy(c).thoracicRibbon(g.sideRib(i), strong ? 0x8B536B : cutaway ? 0xA0B2B9 : 0x81949B,
        strong ? 0xF4DAD8 : cutaway ? 0xE1EBEC : 0xF1F1E7, strong ? 8.8 : 6.9)
      thoracicRibbon(g.sideCartilage(i,b), 0x658893, 0xBDDEE3, strong ? 6.7 : 5.2)
    }
    if !cutaway { for i in 1...3 { disc(m.rearX(i), m.rearY(i), 3.5, 0xF8E4DF, border: 0x8B536B) } }
    var c = context; c.translateBy(x: 0, y: -9*b)
    let art = copy(c)
    art.thoracicWashed(GalaxySSIHealthAtlasThoracicSternum.side(b), 65, 211, 0xFFF0E3, 0xCEB5BD, 0x8B536B)
    art.line(m.sideSternumX(100,b)-4, 100, m.sideSternumX(100,b)+5, 100, 0xB791A0, 1.25)
    art.line(m.sideSternumX(194,b)-4, 194, m.sideSternumX(194,b)+4, 194, 0xB791A0, 1.1)
  }
}
