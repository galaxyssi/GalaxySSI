import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func latissimusSheet(_ tx: Double, _ ty: Double, _ step: Int, _ t: Double) {
    let wrapX = 205 + 0.27 * (tx - 220), wrapY = 151 + 0.37 * (ty - 121)
    let sheet = Path { p in
      p.move(to: CGPoint(x: 118, y: 154))
      p.addCurve(to: CGPoint(x: wrapX - 4, y: wrapY - 6), control1: CGPoint(x: 150, y: 154), control2: CGPoint(x: 181, y: 168))
      p.addQuadCurve(to: CGPoint(x: wrapX - 1, y: wrapY + 6), control: CGPoint(x: wrapX + 2, y: wrapY - 2))
      p.addCurve(to: CGPoint(x: 170, y: 263), control1: CGPoint(x: 178, y: 198), control2: CGPoint(x: 184, y: 234))
      p.addQuadCurve(to: CGPoint(x: 123, y: 272), control: CGPoint(x: 146, y: 276))
      p.addCurve(to: CGPoint(x: 118, y: 154), control1: CGPoint(x: 142, y: 238), control2: CGPoint(x: 126, y: 207)); p.closeSubpath()
    }
    gradient(sheet, 133, 273, 0xC78079, 0xE9B097); stroke(sheet, 0x95574E, 1.55)
    for i in 0...6 {
      let f = Double(i) / 6, focus = step == 0 ? sin(t * .pi) : 0
      stroke(Path { p in
        p.move(to: CGPoint(x: 123 + 19 * f * f, y: 159 + 107 * f))
        p.addCurve(to: CGPoint(x: wrapX - 4, y: wrapY - 4 + 8 * f), control1: CGPoint(x: 149 + 20 * f, y: 163 + 93 * f), control2: CGPoint(x: wrapX - 18, y: wrapY + 17 + 33 * f))
      }, i.isMultiple(of: 2) ? 0xBAFFEBE0 : 0x95574E, 1.05 + 0.45 * focus)
    }
    let rimX = (wrapX + tx) / 2 + 3, rimY = (wrapY + ty) / 2 + 2
    let tendon = Path { p in
      p.move(to: CGPoint(x: wrapX - 5, y: wrapY)); p.addQuadCurve(to: CGPoint(x: rimX, y: rimY), control: CGPoint(x: wrapX + 3, y: wrapY + 3))
    }
    stroke(tendon, 0x95574E, 7); stroke(tendon, 0xF1DFBE, 4.5)
    let hidden = Path { p in p.move(to: CGPoint(x: rimX, y: rimY)); p.addQuadCurve(to: CGPoint(x: tx, y: ty), control: CGPoint(x: tx + 3, y: rimY - 3)) }
    context.stroke(hidden, with: .color(Self.color(0x95574E)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round, dash: [3, 2.5]))
    disc(tx, ty, 2.4, Self.cream, border: 0x95574E)
  }
}
