import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func autonomicAnatomy(_ showSympathetic: Bool) {
    typealias Geometry = GalaxySSIHealthAtlasAutonomicGeometry
    autonomicTissue(Geometry.torso, 88, 320, 0xF5E8DC, 0xEFE3D7, 0xC9B7A7)
    fill(Geometry.lung, 0xECD4CB)
    var mirror = context; mirror.translateBy(x: 360, y: 0); mirror.scaleBy(x: -1, y: 1)
    copy(mirror).fill(Geometry.lung, 0xECD4CB)
    for i in 0...5 {
      let y = 122 + Double(i) * 16
      rounded(166, y, 183, y + 12, 3, 0xE1C9B8)
    }
    stroke(Geometry.cord, 0x9B778B, 9); stroke(Geometry.cord, 0xE7BFB7, 6.4)
    oval(182, 66, 212, 87, fill: 0xD8AEAC, border: 0x9B778B)
    for i in 0...2 { line(192, 76 + 3 * Double(i), 206, 75 + 3 * Double(i), 0x9B778B, 0.9) }
    autonomicTissue(Geometry.brain, 38, 150, 0xECD1BF, 0xD9B1AE, 0x9B778B)
    stroke(Geometry.folds, 0x9B778B, 1.2)
    if showSympathetic {
      stroke(Geometry.sympatheticTrunk, 0xBE9470, 2.2)
      oval(119, 124, 128, 134, fill: Self.sand, border: 0x98602F)
      oval(112, 168, 122, 179, fill: Self.sand, border: 0x98602F)
      oval(111, 192, 120, 202, fill: Self.sand, border: 0x98602F)
      oval(115, 145, 125, 157, fill: Self.sand, border: 0x98602F)
    }
    autonomicHeart()
  }
  func autonomicHeart() {
    typealias Geometry = GalaxySSIHealthAtlasAutonomicGeometry
    autonomicVessel(Geometry.venaCava, 0xA2B7C6, 13)
    autonomicVessel(Geometry.aorta, 0xDBA09E, 15)
    line(194, 178, 191, 167, 0x925E6E, 5.6); line(194, 178, 191, 167, 0xDBA09E, 3.9)
    line(204, 177, 205, 166, 0x925E6E, 5.2); line(204, 177, 205, 166, 0xDBA09E, 3.5)
    autonomicVessel(Geometry.pulmonaryTrunk, 0xA2B7C6, 10)
    autonomicTissue(Geometry.heart, 212, 302, 0xEFB8AC, 0xCB8391, 0x925E6E)
    stroke(Geometry.heartDetail, 0x925E6E, 1.35)
  }
  private func autonomicVessel(_ shape: Path, _ color: UInt32, _ width: Double) {
    stroke(shape, 0x925E6E, width); stroke(shape, color, width - 2.5)
  }
  private func autonomicTissue(_ shape: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ edge: UInt32) {
    gradient(shape, top, bottom, from, to); stroke(shape, edge, 1.45)
  }
}
