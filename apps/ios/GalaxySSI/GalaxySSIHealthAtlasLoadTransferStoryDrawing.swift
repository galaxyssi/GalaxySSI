import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func pelvicLoadScene(_ step: Int, _ t: Double) {
    context.draw(Image("HealthAtlasCompletePelvicRing"), in: CGRect(x: 0, y: 49, width: 360, height: 280))
    let ink: UInt32 = 0x307B75, tint: UInt32 = 0xD3EEE3
    if step == 0 {
      var ring = Path(); ring.move(to: CGPoint(x: 145, y: 123))
      ring.addCurve(to: CGPoint(x: 78, y: 166), control1: CGPoint(x: 123, y: 112), control2: CGPoint(x: 82, y: 117))
      ring.addCurve(to: CGPoint(x: 144, y: 238), control1: CGPoint(x: 72, y: 203), control2: CGPoint(x: 104, y: 229))
      ring.addQuadCurve(to: CGPoint(x: 216, y: 238), control: CGPoint(x: 180, y: 245))
      ring.addCurve(to: CGPoint(x: 282, y: 166), control1: CGPoint(x: 256, y: 229), control2: CGPoint(x: 288, y: 203))
      ring.addCurve(to: CGPoint(x: 215, y: 123), control1: CGPoint(x: 278, y: 117), control2: CGPoint(x: 237, y: 112))
      var local = context; local.opacity = Double(Int(125 + 115 * sin(t * .pi))) / 255
      copy(local).stroke(ring, 0x78ADA3, 2.2 + 1.8 * sin(t * .pi))
      for (key, x, targetX, targetY) in [("pelvic_ring_sacrum", 180.0, 180.0, 131.0),
        ("pelvic_ring_joint", 69.0, 147.0, 125.0), ("pelvic_ring_socket", 293.0, 267.0, 198.0)] {
        let elbow = x + (targetX < x ? -13 : targetX > x ? 13 : 0)
        line(x, 34, elbow, 47, 0x709593, 1); line(elbow, 47, targetX, targetY, 0x709593, 1)
        disc(targetX, targetY, 3.1, ink, border: Self.cream); label(key, x, 27, 107)
      }
      line(180, 248, 180, 315, ink, 1); disc(180, 237, 3.5, ink, border: Self.cream)
      label("pelvic_ring_symphysis", 180, 339, 214)
      return
    }
    let smooth = t * t * (3 - 2 * t)
    let shift = step == 1 ? 0 : step == 2 ? 0.8 * smooth : 0.8 * (1 - smooth)
    let fraction = 0.5 + shift / 2
    line(180, 44, 180, 106, tint, 8); line(180, 44, 180, 106, ink, 3.4)
    for side in [-1.0, 1.0] {
      let share = side < 0 ? 1 - fraction : fraction, route = Self.pelvicLoadRoute(side)
      let path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
      stroke(path, tint, 5 + 5 * share); stroke(path, ink, 1.15 + 4 * share)
      let endX = side < 0 ? 62.0 : 298.0
      arrow(endX, 286, endX, 310, ink)
      if t >= 0.24 { at(route, (t - 0.24) / 0.76) { disc($0, $1, 2.8 + 2.8 * share, 0xFFE491, border: ink) } }
    }
    if t < 0.24 { disc(180, 44 + 62 * t / 0.24, 4.7, 0xFFE491, border: ink) }
    line(83, 340, 277, 340, 0x85A4A3, 1.5)
    disc(83, 340, 3.4, 0xB1CAC5); disc(277, 340, 3.4, 0xB1CAC5)
    disc(180 + shift * 97, 340, 5.2, ink, border: Self.cream)
    label("pelvic_ring_incoming", 180, 24, 290)
  }
  private static func pelvicLoadRoute(_ side: Double) -> GalaxySSIHealthAtlasSectionLesson.Route {
    .init(start: .init(x: 180, y: 106), commands: [
      .init(kind: .cubic, points: [.init(x: 180 + side * 20, y: 113), .init(x: 180 + side * 29, y: 118), .init(x: 180 + side * 40, y: 128)]),
      .init(kind: .cubic, points: [.init(x: 180 + side * 58, y: 148), .init(x: 180 + side * 66, y: 175), .init(x: 180 + side * 84, y: 197)]),
      .init(kind: .cubic, points: [.init(x: 180 + side * 99, y: 215), .init(x: 180 + side * 109, y: 223), .init(x: 180 + side * 111, y: 251)]),
      .init(kind: .quad, points: [.init(x: 180 + side * 114, y: 276), .init(x: 180 + side * 118, y: 287)])])
  }
  func subcutaneousScene(_ step: Int, _ t: Double, _ compression: Double) {
    let pressure: UInt32 = 0x477F8D
    if step == 0 {
      let halo = 2 + 5 * sin(t * .pi)
      for (key, x, targetX, targetY) in [("subcutaneous_epidermis", 72.0, 84.0, 103.0),
        ("subcutaneous_lobule", 180.0, 160.0, 191.0), ("subcutaneous_fascia", 293.0, 294.0, 268.0)] {
        line(x, 46, targetX, targetY, 0x71938E, 1.2)
        disc(targetX, targetY, halo + 3, 0x8079B6AD); disc(targetX, targetY, 3.2, 0x668983, border: Self.cream)
        label(key, x, 35, 110)
      }
      label("subcutaneous_deep_muscle", 180, 329, 160)
      return
    }
    let y = 91 + 28 * compression, radius = 31 + 13 * compression
    rounded(180 - radius, y - 12, 180 + radius, y + 2, 5, 0xC3E2E1)
    line(182 - radius, y + 1.7, 178 + radius, y + 1.7, pressure, 1.7)
    for x in [160.0, 180.0, 200.0] { arrow(x, y - 36, x, y - 15, pressure) }
    label("subcutaneous_load", 180, 29, 234)
    if step == 2 {
      for side in [-1.0, 1.0] {
        let route = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 180, y: 148), commands: [
          .init(kind: .cubic, points: [.init(x: 180 + side * 24, y: 176), .init(x: 180 + side * 39, y: 204), .init(x: 180 + side * 86, y: 222)])])
        let path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
        stroke(path, 0xC3E2E1, 7.2); stroke(path, pressure, 1.9)
        arrow(180 + side * 70, 216, 180 + side * 86, 222, pressure)
        at(route, t) { disc($0, $1, 5.2, Self.cream, border: pressure) }
      }
      label("subcutaneous_force_spread", 180, 334, 260)
    } else if step > 2 {
      for index in 0..<11 { let x = 119 + Double(index) * 11; line(x, 91, x + 5, 91, 0x9A9685, 1.3) }
      label("subcutaneous_reference_surface", 180, 334, 265)
    }
  }
}
