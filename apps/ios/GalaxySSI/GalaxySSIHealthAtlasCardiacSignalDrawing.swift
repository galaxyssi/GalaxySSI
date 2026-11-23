import SwiftUI

private typealias CardiacSignalMotion = GalaxySSIHealthAtlasCardiacSignalMotion
private typealias CardiacSignalShapes = GalaxySSIHealthAtlasCardiacSignalShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func cardiacSignalHeart(step: Int, t: Double) {
    gradient(CardiacSignalShapes.wall, 28, 176, 0xF7C6B2, 0xD08083); stroke(CardiacSignalShapes.wall, CardiacSignalShapes.outline, 2)
    fill(CardiacSignalShapes.leftVentricle, 0xF5D8C7); fill(CardiacSignalShapes.rightVentricle, 0xF5D8C7)
    stroke(CardiacSignalShapes.leftVentricle, CardiacSignalShapes.outline, 1.4); stroke(CardiacSignalShapes.rightVentricle, CardiacSignalShapes.outline, 1.35)
    for (index, route) in CardiacSignalMotion.routes.enumerated() {
      let path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
      stroke(path, CardiacSignalShapes.circuit, 1.25)
      if let progress = CardiacSignalMotion.progress(step: step, fraction: t, route: index) {
        if progress > 0 { stroke(path.trimmedPath(from: 0, to: CGFloat(progress)), CardiacSignalShapes.excited, 2.8) }
        at(route, progress) { x, y in disc(x, y, 3.4, CardiacSignalShapes.excited, border: Self.cream) }
      }
    }
    disc(112, 48, step == 0 ? 7 + 2.4 * wave(t) : 5, CardiacSignalShapes.excited, border: CardiacSignalShapes.circuit)
    disc(140, 95, step == 1 ? 7 + 2.5 * wave(t) : 4.5, CardiacSignalShapes.excited, border: CardiacSignalShapes.circuit)
    line(118, 48, 248, 39, CardiacSignalShapes.circuit, 1.1); label("cardiac_sa_label", 294, 43, 100)
    line(146, 94, 251, 84, CardiacSignalShapes.circuit, 1.1); label("cardiac_av_label", 294, 88, 103)
    line(191, 153, 246, 147, CardiacSignalShapes.circuit, 1.1); label("cardiac_network_label", 291, 151, 108)
    line(164, 175, 75, 213, CardiacSignalShapes.outline, 1.05); line(178, 177, 289, 213, CardiacSignalShapes.outline, 1.05)
  }
  func cardiacSignalCell(step: Int, t: Double) {
    let shortening = CardiacSignalMotion.shortening(step: step, fraction: t), left = 33 + 33 * shortening, right = 326 - 33 * shortening, width = right - left
    label("cardiac_cell_label", 180, 231, 201)
    oval(left, 242, right, 305, top: 242, bottom: 310, from: 0xFFE2D0, to: 0xE5A8A4, border: CardiacSignalShapes.outline)
    for i in 0...3 {
      let x = left + 28 + (width - 56) * Double(i) / 3
      line(x, 260, x, 285, CardiacSignalShapes.outline, 1.8)
      if i > 0 {
        let previous = left + 28 + (width - 56) * Double(i - 1) / 3, center = (x + previous) * 0.5
        line(previous, 268, previous + 29, 268, CardiacSignalShapes.myofibril, 2.4)
        line(x - 29, 277, x, 277, CardiacSignalShapes.myofibril, 2.4); line(center - 14, 273, center + 14, 273, 0xBF8063, 2.8)
      }
    }
    if step == 2 && t > 0.72 {
      let pulseX = left + 13 + (width - 26) * ((t - 0.72) / 0.28)
      disc(pulseX, 297, 3.2, CardiacSignalShapes.excited, border: Self.cream)
    }
    var trace = Path(); trace.move(to: CGPoint(x: left + 15, y: 253))
    trace.addCurve(to: CGPoint(x: right - 15, y: 253), control1: CGPoint(x: left + width * 0.36, y: 246), control2: CGPoint(x: right - width * 0.35, y: 257))
    stroke(trace, 0xB0CEC4, 6)
    for i in 0...5 {
      let x = left + 25 + (width - 50) * Double(i) / 5, f = max(0, shortening - Double(i) * 0.06)
      disc(x, 252 + 15 * f, 2.7, Self.teal, border: Self.cream)
    }
    line(229, 321, 249, 283, CardiacSignalShapes.outline, 1.1); label("cardiac_filaments_label", 251, 338, 109)
    disc(94, 334, 3.5, Self.teal, border: Self.cream); label("cardiac_calcium_label", 128, 338, 60)
  }
}
