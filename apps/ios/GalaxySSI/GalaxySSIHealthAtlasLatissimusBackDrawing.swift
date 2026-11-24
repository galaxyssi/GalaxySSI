import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func latissimusBack() {
    let g = GalaxySSIHealthAtlasLatissimusGeometry.self
    gradient(g.torso, 64, 296, 0xD5E5E2, 0xEAF0E4); stroke(g.torso, 0x637F82, 1.5)
    fill(g.scapula, 0xEEE9D9); stroke(g.scapula, 0xA09B87, 1.4)
    stroke(Path { p in p.move(to: CGPoint(x: 143, y: 123)); p.addQuadCurve(to: CGPoint(x: 205, y: 109), control: CGPoint(x: 174, y: 123)) }, 0xAAA18C, 2.1)
    fill(g.farSheet, 0xCB9B91); stroke(g.farSheet, 0xAC817B, 1.2)
    gradient(g.fasciaField, 151, 269, 0xD1E3DD, 0xA3C4BF); stroke(g.fasciaField, 0x557E80, 1.3)
    stroke(Path { p in
      p.move(to: CGPoint(x: 119, y: 84)); p.addCurve(to: CGPoint(x: 118, y: 277), control1: CGPoint(x: 110, y: 137), control2: CGPoint(x: 124, y: 211))
    }, 0x879D98, 1.5)
    for i in 0...7 { let y = 102 + Double(i) * 22; line(113, y, 121, y + 2, 0x91A39A, 1.1) }
    let rim = Path { p in p.move(to: CGPoint(x: 81, y: 264)); p.addQuadCurve(to: CGPoint(x: 168, y: 264), control: CGPoint(x: 120, y: 284)) }
    stroke(rim, 0xEEE5CF, 5); stroke(rim, 0x9F9884, 1.3)
  }
}
