import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sinusLocate(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasSinusGeometry
    typealias Motion = GalaxySSIHealthAtlasSinusMotion
    sinusShaded(Geometry.front, 64, 281, 0xF8E8D7, 0xE5B29E)
    for side in 0...1 {
      var local = context
      if side == 1 { local.translateBy(x: 180, y: 0); local.scaleBy(x: -1, y: 1) }
      let art = copy(local)
      art.sinusArea(Geometry.orbitFront, 0xEECBC0, 0x886762)
      art.oval(39, 143, 66, 157, fill: 0xFCF3E6, border: 0x886762)
      art.disc(53, 150, 4.8, 0x718B8A); art.disc(53, 150, 2.1, 0x886762)
      art.sinusEmphasis(Geometry.frontalFront, 0xBBD6E0, Self.blue, Motion.highlight(t, 0))
      art.sinusEmphasis(Geometry.maxillaryFront, 0xBADBC9, 0x457970, Motion.highlight(t, 3))
      for i in 0...2 {
        let x = 78 + Double(i % 2) * 3, y = 139 + Double(i) * 8
        art.oval(x - 5, y - 4, x + 5, y + 4, fill: 0xEFD5A1, border: Self.sienna)
      }
      art.disc(84, 202, 2.7, 0x886762)
    }
    stroke(Geometry.faceDetails, 0x886762, 1.35)
    sinusShaded(Geometry.profile, 64, 281, 0xF8E8D7, 0xE5B29E)
    sinusArea(Geometry.mouthProfile, 0xE3A999, 0x886762)
    sinusArea(Geometry.noseProfile, 0xF4CFB4, 0x9B655E)
    stroke(Geometry.noseDetails, 0x9B655E, 1.2)
    sinusEmphasis(Geometry.frontalProfile, 0xBBD6E0, Self.blue, Motion.highlight(t, 0))
    for i in 0...3 {
      let x = 231 + Double(i) * 6, y = 149 - Double(i % 2) * 4
      disc(x, y, 4.3 + 1.5 * Motion.highlight(t, 1), 0xEFD5A1, border: Self.sienna)
    }
    sinusEmphasis(Geometry.sphenoid, 0xD7C8E2, Self.violet, Motion.highlight(t, 2))
  }
}
