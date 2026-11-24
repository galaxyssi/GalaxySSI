import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func tonsilLocate(_ t: Double) {
    typealias Geometry = GalaxySSIHealthAtlasTonsilGeometry
    typealias Motion = GalaxySSIHealthAtlasTonsilMotion
    tonsilPane(Geometry.head, top: 46, bottom: 316, from: 0xF7DFCC, to: 0xD8A69D)
    for i in 0...4 {
      let x = 190 - Double(i) * 1.4, y = 210 + Double(i) * 19
      oval(x - 7, y, x + 9, y + 15, fill: 0xEDCFB7, border: 0xBF9381)
    }
    tonsilPane(Geometry.airway, top: 95, bottom: 288, from: 0xFCFAF0, to: 0xD4E5E4)
    stroke(Geometry.nasalRidges, 0xB1797D, 1.5)
    tonsilPane(Geometry.palate, fill: 0xE6AF96); tonsilPane(Geometry.tongue, fill: 0xD598A0)
    line(64, 121, 80, 119, 0x855D67, 1.3)
    line(53, 164, 61, 163, 0x855D67, 1.3)
    line(61, 202, 75, 199, Self.cream, 2.6)
    tonsilPane(Geometry.adenoidPatch, fill: 0xAD91B5, edge: 0x6C557E)
    oval(141, 181, 158, 204, fill: 0xCD8BA4, border: 0x8F4B66)
    for i in 0...2 { disc(146 + Double(i) * 3, 188 + Double(i) * 4, 1.05, 0x8F4B66) }
    tonsilFocus(165, 125, 22, 0x6C557E, Motion.adenoidFocus(t))
    tonsilFocus(150, 192, 15, 0x8F4B66, Motion.palatineFocus(t))
  }
}
