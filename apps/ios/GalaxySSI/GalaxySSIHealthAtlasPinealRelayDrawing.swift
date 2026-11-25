import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func pinealRelay(_ t: Double) {
    let g = GalaxySSIHealthAtlasPinealGeometry.self, r = GalaxySSIHealthAtlasPinealRoutes.self
    gradient(g.cranialProfile, 56, 284, 0xEEF3F5, 0xCBD9E3); stroke(g.cranialProfile, 0x8FA5B4, 1.35)
    pinealBrain(104, 43, 0.374)
    stroke(g.canal, 0xBAC7D5, 17); stroke(g.canal, 0xEAF0F5, 12)
    for i in 0...10 {
      let y = 150+Double(i)*10, x = 191-Double(i)*2.1+Double(i*i)*0.23
      line(x+1, y, x+7, y+1.5, 0x9FAEC0, 1.2)
    }
    stroke(g.canal, 0x6B80A1, 2.7)
    oval(140, 160, 150, 173, fill: 0xDECEEA, border: 0x81609C)
    for (i, track) in [r.relay0, r.relay1, r.relay2, r.relay3].enumerated() {
      let color: UInt32 = i == 0 ? 0x267D78 : i == 1 ? 0x5C709A : 0x81609C
      let f = GalaxySSIHealthAtlasPinealMotion.relay(t, i)
      stroke(track.path, 0xAEBAC6, 1.7); pinealSegment(track, f, color, 2.4)
      pinealDirection(track, f > 0.98 ? color : 0x8194A6)
      if f > 0 && f < 1 { at(track.route, f) { x, y in disc(x, y, 4, color, border: 0xFAFFFF) } }
    }
    disc(147, 105, 3.8, 0x267D78, border: 0xFAFFFF)
    disc(152, 90, 3.8, 0x5C709A, border: 0xFAFFFF)
    disc(187, 232, 4.2, 0x5C709A, border: 0xFAFFFF)
    disc(145, 167, 4.2, 0x81609C, border: 0xFAFFFF)
    disc(197, 98, 3.6, 0x73518E, border: 0xFAFFFF)
    pinealCrescent(295, 144, 11, 0xEBF2F6)
  }
}
