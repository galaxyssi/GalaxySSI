import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func pinealProduce(_ t: Double) {
    let g = GalaxySSIHealthAtlasPinealGeometry.self, motion = GalaxySSIHealthAtlasPinealMotion.self
    gradient(g.vessel, 204, 284, 0xECD6E0, 0xC7A0B8); stroke(g.vessel, 0x9F7F98, 1.35)
    stroke(g.vesselLight, 0xFAEBF0, 1.5)
    for i in 0...3 {
      let x = 220+Double(i)*31, y = 272-Double(i)*(5+Double(i)*2)
      var c = context; c.translateBy(x: x, y: y); c.rotate(by: .degrees(4-14*Double(i)))
      copy(c).oval(-8, -3.8, 8, 3.8, fill: 0xD7A3B1, border: 0xA0758C)
    }
    gradient(g.cell, 110, 268, 0xF0F6EE, 0xB0D2CC); stroke(g.cell, 0x637E8B, 1.65)
    stroke(g.axon, 0xCFBDDF, 6); stroke(g.axon, 0x81609C, 1.55)
    disc(69, 134, 5.9, 0xD6C2E1, border: 0x81609C)
    disc(51, 140, 4.7, 0xD6C2E1, border: 0x81609C)
    disc(55, 103, 3.8, 0xD6C2E1, border: 0x81609C)
    oval(144, 126, 193, 161, fill: 0xAAC2D1, border: 0x77929F)
    oval(149, 130, 188, 157, fill: 0xC4D7E0, border: 0xA2B9C8); disc(171, 143, 4.3, 0x8CA7B8)
    for i in 0...6 {
      let x = 99+Double(i)*19, y = i % 2 == 0 ? 226.0 : 232.0
      oval(x+3, y-1, x+8, y+1.7, fill: 0xDCEEE7, border: 0x9EBDBD)
    }
    // Source arc is an ellipse, with Android's positive angles following the screen y-axis.
    let arc = Path { p in
      p.addArc(center: .zero, radius: 1, startAngle: .degrees(168), endAngle: .degrees(300), clockwise: false)
    }.applying(CGAffineTransform(a: 7.5, b: 0, c: 0, d: 8, tx: 89.5, ty: 154))
    stroke(arc, 0x81609C, 2.15)
    for i in 0...2 {
      let f = motion.transmitter(t, i)
      if f > 0 {
        let x = 70+(16-2*Double(i))*f, y = 134+(12+4*Double(i))*f
        disc(x-Double(i)*(1-f), y, 2.5, 0x81609C, border: 0xFAFFFF)
      }
    }
    let first = motion.synthesis(t, 0), second = motion.synthesis(t, 1)
    pinealMolecule(108, 204, 0, true); pinealMolecule(159, 204, 1, first >= 0.98)
    pinealMolecule(210, 204, 2, second >= 0.98)
    arrow(118, 204, 149, 204, first > 0 ? 0x317C79 : 0x8CAEB0)
    arrow(169, 204, 200, 204, second > 0 ? 0x73518E : 0x8CAEB0)
    if first > 0 && first < 1 { pinealMolecule(108+51*first, 204, 1, true) }
    if second > 0 && second < 1 { pinealMolecule(159+51*second, 204, 2, true) }
    for i in 0...2 {
      let f = motion.secretion(t, i)
      if f > 0 {
        at(GalaxySSIHealthAtlasPinealRoutes.outgoing.route, f*(1-0.10*Double(i))) { x, y in
          disc(x, y, 3.1, 0x73518E, border: 0xFAFFFF)
        }
      }
    }
  }
}
