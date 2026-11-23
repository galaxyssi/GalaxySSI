import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func urinePassage(_ channel: GalaxySSIHealthAtlasUrineShapes.Channel, radius: (Double) -> Double) {
    let radii = (0...64).map { radius(Double($0) / 64) }
    let layers: [(Double, UInt32, UInt32)] = [(9, 0xE9B0AB, Self.coral), (3.5, 0xF7D7C2, 0xC68B87), (0, Self.cream, 0xBC8680)]
    for (margin, color, edge) in layers {
      var shape = Path()
      for side in [-1.0, 1.0] {
        for j in 0...64 {
          let i = side < 0 ? j : 64 - j, sample = channel.samples[i], r = side * (radii[i] + margin)
          let point = CGPoint(x: Double(sample.point.x) - r * Double(sample.direction.dy), y: Double(sample.point.y) + r * Double(sample.direction.dx))
          if side < 0 && j == 0 { shape.move(to: point) } else { shape.addLine(to: point) }
        }
      }
      shape.closeSubpath(); fill(shape, color); stroke(shape, edge, 1.2)
    }
  }
  func urinePulse(_ route: GalaxySSIHealthAtlasSectionLesson.Route, front: Double, length: Double, width: Double, from: Double = 0) {
    guard width > 0, let interval = GalaxySSIHealthAtlasUrineMotion.pulseInterval(front: front, length: length, from: from) else { return }
    let trace = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360).trimmedPath(from: CGFloat(interval.start), to: CGFloat(interval.end))
    stroke(trace, 0xB37532, width); stroke(trace, 0xF3C56C, width * 0.61)
  }
  func urineCallout(_ key: String, _ x: Double, _ y: Double, _ maxWidth: Double, _ toX: Double, _ toY: Double) {
    line(x, y + 5, toX, toY, 0x776C72, 1.15); disc(toX, toY, 2, Self.violet, border: Self.cream); label(key, x, y, maxWidth)
  }
}
