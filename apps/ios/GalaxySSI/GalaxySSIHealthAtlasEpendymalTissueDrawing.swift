import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ependymalTissue(_ top: Double, _ depth: Double) {
    let rim = GalaxySSIHealthAtlasEpendymalMotion.rim
    let p = Path { p in
      p.move(to: CGPoint(x: 0, y: rim(0,top)+depth-8))
      p.addQuadCurve(to: CGPoint(x: 360, y: rim(360,top)+depth-8), control: CGPoint(x: 180, y: top+depth-48))
      p.addLine(to: CGPoint(x: 360, y: 360)); p.addLine(to: CGPoint(x: 0, y: 360)); p.closeSubpath()
    }
    gradient(p, 246, 355, 0xC4BFDC, 0xEEF0F6)
    var c = context; c.clip(to: p)
    let art = copy(c)
    for i in 0...10 {
      let x = 21+Double(i)*32, y = rim(x,top)+depth+17+Double(i % 3)*8
      let fiber = Path { p in
        p.move(to: CGPoint(x: x-36, y: y+14))
        p.addCurve(to: CGPoint(x: x+24, y: y-9),
          control1: CGPoint(x: x-22, y: y-10), control2: CGPoint(x: x+11, y: y+9))
        p.addQuadCurve(to: CGPoint(x: x+46, y: y-16), control: CGPoint(x: x+34, y: y-19))
      }
      art.stroke(fiber, 0x60928EAF, 4.7); art.stroke(fiber, 0x93F2F1F8, 1.4)
      art.oval(x-7, y-3, x+7, y+3, fill: 0xB6AFCD, border: 0xA29AB8)
    }
  }
}
