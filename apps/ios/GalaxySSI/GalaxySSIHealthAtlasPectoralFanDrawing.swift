import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func pectoralFan(_ tx: Double, _ ty: Double, _ step: Int, _ t: Double) {
    let joinX = tx - 15, joinY = ty + 4
    let clavicular = Path { p in
      p.move(to: CGPoint(x: 153, y: 171))
      p.addCurve(to: CGPoint(x: 205, y: 154), control1: CGPoint(x: 174, y: 153), control2: CGPoint(x: 191, y: 151))
      p.addCurve(to: CGPoint(x: joinX + 2, y: joinY - 4), control1: CGPoint(x: 218, y: 155), control2: CGPoint(x: joinX - 7, y: joinY - 11))
      p.addCurve(to: CGPoint(x: 153, y: 181), control1: CGPoint(x: joinX - 15, y: joinY + 2), control2: CGPoint(x: 177, y: 171))
      p.closeSubpath()
    }
    gradient(clavicular, 149, 203, 0xE8B7C0, 0xCB8E9D); stroke(clavicular, 0x945964, 1.35)
    let sternocostal = Path { p in
      p.move(to: CGPoint(x: 153, y: 179))
      p.addCurve(to: CGPoint(x: joinX + 2, y: joinY - 4), control1: CGPoint(x: 184, y: 174), control2: CGPoint(x: joinX - 18, y: joinY + 1))
      p.addLine(to: CGPoint(x: joinX + 4, y: joinY + 4))
      p.addCurve(to: CGPoint(x: 155, y: 206), control1: CGPoint(x: joinX - 17, y: joinY + 17), control2: CGPoint(x: 180, y: 206))
      p.addQuadCurve(to: CGPoint(x: 153, y: 179), control: CGPoint(x: 159, y: 196)); p.closeSubpath()
    }
    gradient(sternocostal, 158, 206, 0xDF9C90, 0xEDC2AD); stroke(sternocostal, 0xA65F55, 1.35)
    for i in 0...4 {
      let index = Double(i), focus = step == 0 ? t : 0
      stroke(Path { p in
        p.move(to: CGPoint(x: 158, y: 183 + 4.4 * index))
        p.addCurve(to: CGPoint(x: joinX + 1, y: joinY - 2 + index), control1: CGPoint(x: 183, y: 181 + 4 * index), control2: CGPoint(x: joinX - 15, y: joinY + 3 * index - 3))
      }, i.isMultiple(of: 2) ? 0xAAFFF0E6 : 0xA65F55, 1 + 0.4 * focus)
    }
    stroke(Path { p in
      p.move(to: CGPoint(x: 163, y: 169)); p.addQuadCurve(to: CGPoint(x: joinX, y: joinY - 4), control: CGPoint(x: 187, y: 152))
    }, 0xCFFFF1E9, 1.35)
    line(joinX + 2, joinY, tx, ty, 0x945964, 7); line(joinX + 2, joinY, tx, ty, 0xF3DDBB, 4.5)
    disc(tx, ty, 2.3, Self.cream, border: 0x945964)
  }
}
