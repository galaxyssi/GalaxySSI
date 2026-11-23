import SwiftUI

extension GalaxySSIHealthAtlasHomeostasisDrawing {
  func sweatScene(_ motion: Motion) {
    if motion.chapter == 4 { evaporation(motion.fraction) } else { gland(chapter: motion.chapter, t: motion.fraction) }
  }
  private func gland(chapter: Int, t: Double) {
    var local = context; local.translateBy(x: 0, y: 56); let drawing = copy(local)
    drawing.picture("HealthAtlasFunctionSweatGland", 0, 0, 360, 280)
    switch chapter {
    case 0:
      let nerve = GalaxySSIHealthAtlasSectionLessonView.path(Motion.nerve, width: 360, height: 360)
      drawing.stroke(nerve, 0xD9AB6A, 5.5); drawing.stroke(nerve, Self.gold, 1.3)
      for i in 0...3 { drawing.marker(Motion.nerve, Motion.loop(t * 1.35 + Double(i) / 4)) { drawing.dot($0, $1, Self.gold, 4.3) } }
      drawing.ring(150, 198, 10 + 7 * sin(.pi * t), Self.gold)
    case 1:
      for i in 0...5 { drawing.marker(Motion.sweatDuct, 1 - 0.68 * Motion.loop(t * 1.1 + Double(i) / 6)) { drawing.dot($0, $1, Self.water, 3.6) } }
    case 2:
      for i in 0...4 { drawing.marker(Motion.sweatDuct, 0.43 * (1 - Motion.loop(t * 1.23 + Double(i) / 5))) { drawing.dot($0, $1, Self.water, 3.5) } }
      for i in 0...5 {
        let f = Motion.loop(t * 1.08 + Double(i) / 6), side = i % 2 == 0 ? 1.0 : -1
        let x = 173 + side * (6 + 49 * f), y = 101 + Double(i) * 12 + sin(f * 3) * 5
        drawing.rounded(x - 2.8, y - 2.8, x + 2.8, y + 2.8, 0.8, Self.salt)
      }
    case 3:
      for i in 0...3 { drawing.marker(Motion.sweatDuct, 0.24 * (1 - Motion.loop(t * 1.17 + Double(i) / 4))) { drawing.dot($0, $1, Self.water, 3.4) } }
      drawing.drop(173, 60, 5.5 + 12 * t)
    default: break
    }
    switch chapter {
    case 0:
      leader(60, 314, 91, 267, "sweat_nerve", Self.gold); leader(251, 312, 198, 274, "sweat_coil", Self.teal)
    case 1:
      leader(260, 72, 178, 179, "sweat_duct", Self.teal); leader(254, 317, 192, 272, "sweat_coil", Self.teal)
    case 2: leader(251, 76, 218, 187, "sweat_salt_label", Self.salt)
    case 3:
      leader(112, 66, 169, 111, "sweat_droplet", Self.water); leader(264, 74, 180, 119, "sweat_pore", Self.teal)
    default: break
    }
  }
  private func evaporation(_ t: Double) {
    line(180, 69, 180, 279, 0xB6C8C7, 1.2)
    for humid in [false, true] {
      let x = humid ? 270.0 : 90, radius = 21 * sqrt(Motion.liquidRemaining(t, humid: humid))
      box(x - 71, 221, x + 71, 284, 9, 200, 303, 0xEAC0B2, 0xCC918D)
      line(x - 65, 221, x + 65, 221, Self.red, 3.2); drop(x, 220, radius)
      let count = humid ? 2 : 5
      for i in 0..<count {
        let f = Motion.loop(t * (humid ? 0.85 : 1.43) + Double(i) / Double(count))
        let dx = (Double(i) - Double(count - 1) / 2) * (humid ? 15 : 12), y = 181 - f * (humid ? 44 : 66)
        ring(x + dx, y, 2.9 + (1 - f) * 1.5, Self.water)
      }
      let arrowX = x - 57, lift = 8 * sin(t * 8)
      arrow(arrowX, 217, arrowX, 178 + lift, Self.gold)
      if !humid { arrow(x + 57, 217, x + 57, 169 + lift, Self.gold) }
      label(x, 64, humid ? "sweat_humid" : "sweat_dry")
    }
    label(180, 329, "sweat_heat")
  }
}
