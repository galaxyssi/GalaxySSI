import SwiftUI

private typealias SmoothFrame = GalaxySSIHealthAtlasSmoothMuscleMotion
private typealias SmoothShapes = GalaxySSIHealthAtlasSmoothMuscleShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func smoothMuscleScene(_ frame: GalaxySSIHealthAtlasSmoothMuscleMotion, step: Int, t: Double) {
    let contour = stride(from: 16, through: 344, by: 2).map { frame.radius(Double($0)) }
    smoothLayer(contour, offset: 29, fill: 0xDCCFE7, edge: Self.violet)
    smoothLayer(contour, offset: 20, fill: 0xF4C5BD, edge: Self.coral)
    smoothLayer(contour, offset: 6, fill: 0xF8DCB7, edge: 0xBF8C79)
    smoothLayer(contour, offset: 0, fill: 0xFFF5E7, edge: 0xAF816E)
    smoothFibers(frame); smoothBolus(frame); smoothCallouts(frame, step: step, t: t); smoothLegend()
  }
  private func smoothLayer(_ contour: [Double], offset: Double, fill: UInt32, edge: UInt32) {
    var wall = Path(); wall.move(to: CGPoint(x: 16, y: 151 - contour[0] - offset))
    for i in 1..<contour.count { wall.addLine(to: CGPoint(x: Double(16 + 2 * i), y: 151 - contour[i] - offset)) }
    for i in contour.indices.reversed() { wall.addLine(to: CGPoint(x: Double(16 + 2 * i), y: 151 + contour[i] + offset)) }
    wall.closeSubpath(); self.fill(wall, fill)
    // Stroke the two longitudinal sides only; the tube ends remain open.
    var sides = Path()
    for side in [-1.0, 1.0] {
      sides.move(to: CGPoint(x: 16, y: 151 + side * (contour[0] + offset)))
      for i in 1..<contour.count { sides.addLine(to: CGPoint(x: Double(16 + 2 * i), y: 151 + side * (contour[i] + offset))) }
    }
    stroke(sides, edge, offset == 29 ? 1.6 : 1.1)
  }
  private func smoothFibers(_ frame: SmoothFrame) {
    for side in [-1.0, 1.0] {
      for x in stride(from: 24, through: 336, by: 9) {
        let start = Double(x), end = start + 3, squeeze = frame.squeezeAt(start), open = frame.openingAt(start)
        let color = squeeze > 5 ? SmoothShapes.squeeze : open > 5 ? SmoothShapes.open : Self.coral
        line(start, 151 + side * (frame.radius(start) + 8), end, 151 + side * (frame.radius(end) + 17), color, 1.4)
      }
      for x in stride(from: 24, through: 312, by: 32) {
        let start = Double(x), end = start + 23
        var wall = Path(); wall.move(to: CGPoint(x: start, y: 151 + side * (frame.radius(start) + 25)))
        for sample in stride(from: x + 4, through: x + 20, by: 4) {
          let at = Double(sample); wall.addLine(to: CGPoint(x: at, y: 151 + side * (frame.radius(at) + 25)))
        }
        wall.addLine(to: CGPoint(x: end, y: 151 + side * (frame.radius(end) + 25))); stroke(wall, Self.violet, 1.5)
      }
    }
  }
  private func smoothBolus(_ frame: SmoothFrame) {
    var local = context; local.translateBy(x: frame.center, y: 151); local.scaleBy(x: frame.stretch, y: frame.heightScale)
    let art = copy(local)
    art.fill(SmoothShapes.bolus, 0xECC174); art.stroke(SmoothShapes.bolus, Self.sienna, 1.7)
    art.oval(-21, -9, -5, -3, fill: 0xFFE3A3, border: 0xFFE3A3)
    art.disc(5, 8, 3.1, 0xC98D4C); art.disc(15, -5, 2.5, 0xD09650); art.disc(-13, 8, 2.2, 0xD09650)
  }
  private func smoothCallouts(_ frame: SmoothFrame, step: Int, t: Double) {
    let tip = 151 - 18 * frame.heightScale
    line(frame.center, 47, frame.center, tip, Self.cream, 3.2); line(frame.center, 47, frame.center, tip, Self.sienna, 1.2)
    disc(frame.center, tip, 2.2, Self.sienna, border: Self.cream); label("smooth_muscle_story_bolus", frame.center, 38, 68)
    if step == 0 { smoothWallArrows(frame, frame.center + 12, outward: true, color: Self.sienna, length: 8 + 9 * t) }
    if (1...3).contains(step) {
      smoothWallArrows(frame, frame.ahead, outward: true, color: SmoothShapes.open, length: 8 + 0.6 * frame.opening)
      smoothActivityLabel("smooth_muscle_story_ahead", 267, SmoothShapes.open)
    }
    if (2...3).contains(step) {
      smoothWallArrows(frame, frame.behind, outward: false, color: SmoothShapes.squeeze, length: 8 + 0.45 * frame.squeeze)
      smoothActivityLabel("smooth_muscle_story_behind", 93, SmoothShapes.squeeze)
    }
    if step == 4 {
      let wake = SmoothFrame.positions[4] - 48
      smoothWallArrows(frame, wake, outward: true, color: SmoothShapes.open, length: 8 + 10 * t)
      smoothActivityLabel("smooth_muscle_story_reopening", wake, SmoothShapes.open)
    }
  }
  private func smoothActivityLabel(_ key: String, _ x: Double, _ color: UInt32) {
    line(x - 58, 261, x - 50, 261, color, 2.6); label(key, x + 10, 265, 110)
  }
  private func smoothWallArrows(_ frame: SmoothFrame, _ x: Double, outward: Bool, color: UInt32, length: Double) {
    let radius = frame.radius(x) + 29
    for side in [-1.0, 1.0] {
      let near = 151 + side * (radius + 4), far = near + side * length
      arrow(x, outward ? near : far, x, outward ? far : near, color)
    }
  }
  private func smoothLegend() {
    rounded(61, 277, 125, 294, 4, 0xF4C5BD)
    for x in stride(from: 70, through: 116, by: 9) { line(Double(x), 290, Double(x + 3), 281, Self.coral, 1.5) }
    label("smooth_muscle_story_circular", 93, 311, 154)
    rounded(235, 277, 299, 294, 4, 0xDCCFE7)
    for y in stride(from: 282, through: 290, by: 4) { line(243, Double(y), 291, Double(y), Self.violet, 1.5) }
    label("smooth_muscle_story_longitudinal", 267, 311, 154)
    arrow(94, 325, 266, 325, Self.sienna); label("smooth_muscle_story_downstream", 180, 345, 200)
  }
}
