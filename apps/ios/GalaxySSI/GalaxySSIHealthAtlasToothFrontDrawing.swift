import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func toothFrontSection(_ dx: Double, _ dy: Double, _ reach: Double) {
    typealias Geometry = GalaxySSIHealthAtlasToothGeometry
    toothArea(Geometry.frontVault, 0xEFD2AA, 0xA77C67, 1.4)
    stroke(Geometry.palateEdge, 0xEFBDB3, 9); stroke(Geometry.palateEdge, 0x986A70, 1.2)
    var local = context; local.translateBy(x: dx, y: dy)
    let jaw = copy(local)
    jaw.toothArea(Geometry.frontJaw, 0xEFD2AA, 0xA77C67, 1.5)
    jaw.stroke(Geometry.frontGum, 0xDC9B97, 10); jaw.stroke(Geometry.frontGum, 0x986A70, 1.2)
    local.translateBy(x: 0, y: -0.42 * dy)
    let tongue = copy(local), tip = 227 + 34 * reach, lift = 8 * reach
    tongue.toothArea(Geometry.tongue(tip, lift), 0xDC979B, 0x9B646B, 1.3)
    tongue.stroke(Geometry.tongueMidline(tip, lift), 0xB6777C, 1.15)
  }
  func toothFrontCrowns(_ dx: Double, _ dy: Double) {
    for x in GalaxySSIHealthAtlasToothAnatomyData.frontMolarCenters {
      toothCrown(.molar, x, 150, 54, 24, focus: x > 180)
      toothCrown(.molar, x + dx, 210 + dy, 52, -34, focus: x > 180)
    }
  }
}
