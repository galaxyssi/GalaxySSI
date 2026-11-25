import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func sinusSecretion(_ t: Double) {
    var local = context
    local.translateBy(x: 108, y: 4); local.scaleBy(x: 0.43, y: 0.43)
    copy(local).sinusSectionArt()
    disc(165, 115, 10, 0xD4E9DB, border: 0x457970)
    disc(165, 115, 2.5, 0x457970)
    line(157, 123, 36, 173, 0x89A8A1, 1.1); line(173, 123, 324, 173, 0x89A8A1, 1.1)
    rounded(31, 217, 329, 293, 7, 0xECD1C2)
    rounded(34, 208, 326, 232, 5, 0xE1EFF0)
    for i in 0...7 {
      let x = 35 + 36 * Double(i)
      if i != 3 {
        oval(x, 222, x + 38, 280, top: 224, bottom: 279, from: 0xF5D0B6, to: 0xCB8B86, border: 0x886762)
        oval(x + 12, 253 + Double(i % 2) * 4, x + 26, 268 + Double(i % 2) * 4, fill: 0xAD7D9B, border: Self.violet)
        for j in 0...3 { sinusDetailCilium(x + 7 + 7 * Double(j), index: i * 4 + j, t: t) }
      }
    }
    sinusArea(GalaxySSIHealthAtlasSinusGeometry.secretoryCell, 0xB8D6BE, 0x457970)
    oval(157, 260, 168, 273, fill: 0xAD7D9B, border: Self.violet)
    rounded(34, 197, 326, 210, 6, 0x9BC8B6)
    line(44, 200, 316, 200, 0xD7EBD6, 1.2)
    for i in 0...2 {
      let release = GalaxySSIHealthAtlasSinusMotion.secretion(t, i)
      let x = 162 + Double(i - 1) * 6, y = 244 + 4 * Double(i) - (40 + 4 * Double(i)) * release
      let spread = min(1, max(0, (release - 0.78) / 0.22))
      oval(x - 3 - 10 * spread, y - 3.9, x + 3 + 10 * spread, y + 3.9, fill: 0x68AA92, border: 0x457970)
    }
  }
  private func sinusDetailCilium(_ x: Double, index: Int, t: Double) {
    let bend = GalaxySSIHealthAtlasSinusMotion.ciliumBend(t * 0.43, index) * 6
    var cilium = Path()
    cilium.move(to: CGPoint(x: x, y: 227))
    cilium.addCurve(to: CGPoint(x: x + bend, y: 212), control1: CGPoint(x: x, y: 222), control2: CGPoint(x: x + bend * 0.5, y: 217))
    stroke(cilium, 0x457970, 1.35)
  }
}
