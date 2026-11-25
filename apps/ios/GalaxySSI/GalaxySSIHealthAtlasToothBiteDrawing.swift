import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func toothIncisorBite(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasToothGeometry
    let frame = GalaxySSIHealthAtlasToothMotion.bite(t)
    toothProfileBones(frame.angle)
    var local = context; local.translateBy(x: 69, y: 183)
    if t <= 0.52 {
      local.scaleBy(x: 1, y: 1 - 0.55 * frame.close)
      let art = copy(local)
      art.toothArea(Geometry.bite, 0xC98547, 0x854C2E, 1.3)
      art.line(-25, -2, 22, -3, 0xF2BF78, 1.2)
    } else {
      let art = copy(local)
      art.toothBitePiece(Geometry.outerBite, -11 * frame.separation, 7 * frame.separation, -24, -7)
      art.toothBitePiece(Geometry.innerBite, 17 * frame.separation, 3 * frame.separation, 8, 24)
    }
    toothProfileCrowns(frame.angle, focus: .incisor)
    toothCallout("tooth_mastication_story_incisors", 60, 73, 94, 58, 83, 73, 163)
  }
  func toothCanineTear(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasToothGeometry
    let frame = GalaxySSIHealthAtlasToothMotion.tear(t)
    toothProfileBones(frame.angle)
    var local = context; local.translateBy(x: 122, y: 186)
    let art = copy(local), dx = -22 * frame.pull, dy = 7 * frame.pull
    art.toothBitePiece(Geometry.innerBite, 0, 0, 8, 26)
    art.toothBitePiece(Geometry.outerBite, dx, dy, -24, -5)
    for i in -1...1 {
      let y = 3 * Double(i)
      if t < 0.53 + 0.05 * Double(i + 1) { art.line(dx - 3, dy + y, 7, y, 0xF2BF78, 1.45) }
    }
    toothProfileCrowns(frame.angle, focus: .canine)
    toothCallout("tooth_mastication_story_canines", 123, 72, 90, 123, 82, 124, 163)
  }
}
