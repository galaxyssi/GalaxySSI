import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func intercalatedProton(_ x: Double, _ y: Double) { disc(x, y, 3.2, 0xA02E40, border: Self.cream) }
  func intercalatedBicarbonate(_ x: Double, _ y: Double) {
    var p = Path()
    p.move(to: CGPoint(x: x, y: y - 4.6))
    p.addLine(to: CGPoint(x: x + 4.6, y: y))
    p.addLine(to: CGPoint(x: x, y: y + 4.6))
    p.addLine(to: CGPoint(x: x - 4.6, y: y))
    p.closeSubpath()
    fill(p, 0x246E61); stroke(p, Self.cream, 0.9)
  }
  func intercalatedBufferGlyph(_ x: Double, _ y: Double, phosphate: Bool, bound: Bool) {
    if phosphate {
      rounded(x - 6, y - 3.5, x + 5.5, y + 3.5, 1.5, 0x66517D)
      disc(x - 2, y, 1.1, 0xE9DAEF)
    } else {
      disc(x, y, 4.7, 0xD5AC66, border: 0x865E2B)
    }
    if bound { intercalatedProton(x + 4, y - 4) }
  }
}
