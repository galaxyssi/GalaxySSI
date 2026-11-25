import SwiftUI

extension GalaxySSIHealthAtlasHomeostasisDrawing {
  func glucagonScene(_ motion: Motion) {
    switch motion.chapter {
    case 0, 1: alphaCell(release: motion.chapter == 1, t: motion.fraction)
    case 2: liverSignal(motion.fraction)
    case 3: glycogen(motion)
    default: exportGlucose(motion.fraction)
    }
  }
  private func alphaCell(release: Bool, t: Double) {
    var local = context; local.translateBy(x: 0, y: 42); let drawing = copy(local)
    drawing.picture("HealthAtlasFunctionAlpha", 0, 0, 360, 280)
    if release {
      drawing.ring(204, 154, 13 + 5 * sin(t * .pi), Self.violet)
      for i in 0...5 { drawing.marker(Motion.alphaExit, Motion.loop(t * 1.24 + Double(i) / 6), draw: drawing.hormone) }
    } else {
      let count = 6 - Int(t * 4)
      for i in 0..<count {
        let x = 62 + 233 * Motion.loop(t + Double(i) / 6)
        drawing.sugar(x, 236 - 8 * sin((x - 50) * .pi / 255), 4.8)
      }
    }
    leader(80, 99, 147, 145, "glucagon_alpha", Self.red)
    key(203, 324, release ? "glucagon_hormone" : "glucagon_glucose", hormone: release)
  }
  private func liverSignal(_ t: Double) {
    picture("HealthAtlasLiver", 77, 17, 283, 223); label(180, 36, "glucagon_liver")
    line(28, 203, 328, 203, 0xE4ACB5, 30); line(27, 203, 329, 203, 0xF5D0D0, 16)
    rounded(23, 244, 337, 314, 14, 0xEBC8AF); line(27, 244, 334, 244, Self.red, 3.5)
    tube(167, 236, 193, 264, Self.violet)
    var path = Path(); path.move(to: CGPoint(x: 160, y: 225)); path.addQuadCurve(to: CGPoint(x: 200, y: 225), control: CGPoint(x: 180, y: 245)); stroke(path, Self.violet, 5)
    for i in 0...3 { marker(Motion.liverEntry, Motion.loop(t * 1.30 + Double(i) / 4), draw: hormone) }
    if t > 0.38 {
      let f = Motion.loop(t * 2.1); ring(180, 266 + 15 * f, 6 + 4 * f, Self.red)
    }
    label(61, 174, "glucagon_blood"); leader(246, 339, 194, 250, "glucagon_receptor", Self.violet)
  }
  private func glycogen(_ motion: Motion) {
    let t = motion.fraction
    box(20, 100, 340, 328, 22, 162, 332, 0xFAE4CB, 0xE5C3AD)
    for i in 0..<motion.glycogenCount {
      let column = i % 4, x = Double(58 + 21 * column), y = Double(173 + 34 * (i / 4) + column % 2 * 6)
      if column > 0 { line(x - 21, y - (column % 2 == 0 ? -6 : 6), x, y, Self.gold, 2) }
      if column == 1 && i >= 4 { line(x, y - 34, x, y, Self.gold, 2) }
      sugar(x, y, 7.5)
    }
    arrow(152, 211, 207, 211, Self.gold)
    for i in 0...3 {
      let f = Motion.loop(t * 1.14 + Double(i) * 0.25)
      sugar(219 + 67 * f, 194 + Double(i % 3) * 15 + 9 * sin(f * 3), 7.4)
    }
    label(93, 134, "glucagon_glycogen"); label(258, 134, "glucagon_glucose"); label(178, 305, "glucagon_cell")
  }
  private func exportGlucose(_ t: Double) {
    box(23, 92, 337, 151, 16, 95, 151, 0xF5C8C9, 0xDC9BA6)
    for i in 0...3 { oval(37 + 280 * Motion.loop(t + Double(i) * 0.25), 138, 10, 3.6, Self.red) }
    box(23, 165, 337, 311, 18, 162, 332, 0xFAE4CB, 0xE5C3AD)
    line(28, 175, 165, 175, Self.red, 3); line(195, 175, 333, 175, Self.red, 3)
    tube(161, 155, 171, 195, Self.teal); tube(189, 155, 199, 195, Self.teal)
    for i in 0...5 { marker(Motion.glucoseExit, Motion.loop(t * 1.19 + Double(i) / 6)) { sugar($0, $1, 5.5) } }
    label(180, 61, "glucagon_blood"); label(102, 284, "glucagon_cell")
    leader(266, 236, 198, 176, "glucagon_transporter", Self.teal)
  }
}
