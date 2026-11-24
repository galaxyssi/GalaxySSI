import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ependymalTuft(_ x: Double, _ top: Double, _ length: Double,
    _ phase: Double, _ direction: Double, _ focused: Bool) {
    for i in -2...2 {
      let base = x+Double(i)*5, y = GalaxySSIHealthAtlasEpendymalMotion.rim(base,top)
      let beat = phase-Double(i)*0.046, sweep = wave(beat), recover = (1-cos(beat*2 * .pi))*0.5
      let span = length-2*Double(abs(i)), tipX = base+direction*span*(0.20+0.53*sweep)
      let tipY = y-span*(1-0.38*recover)
      let p = Path { p in
        p.move(to: CGPoint(x: base, y: y))
        p.addCurve(to: CGPoint(x: tipX, y: tipY),
          control1: CGPoint(x: base+direction*(0.16-0.32*recover)*span, y: y-span*0.30),
          control2: CGPoint(x: tipX-direction*span*0.28*recover, y: tipY+0.14*span))
      }
      stroke(p, focused ? 0x266E75 : 0x3F848C, focused ? 2.55 : 1.85)
      disc(base, y+1, focused ? 1.7 : 1.3, 0x437389)
    }
  }
}
