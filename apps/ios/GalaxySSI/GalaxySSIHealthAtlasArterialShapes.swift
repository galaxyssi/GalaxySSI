import SwiftUI

enum GalaxySSIHealthAtlasArterialShapes {
  static let outline: UInt32 = 0x995B67, guide: UInt32 = 0x5D797C, blood: UInt32 = 0x984957, pulse: UInt32 = 0x9C621E
  static func path(_ points: [GalaxySSIHealthAtlasSectionLesson.Point], closed: Bool = false) -> Path {
    var p = Path()
    for (i, point) in points.enumerated() {
      if i == 0 { p.move(to: CGPoint(x: point.x, y: point.y)) } else { p.addLine(to: CGPoint(x: point.x, y: point.y)) }
    }
    if closed { p.closeSubpath() }
    return p
  }
  static func arc(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, start: Double, sweep: Double) -> Path {
    var p = Path()
    p.addArc(center: .zero,radius: 1,startAngle: .degrees(start),endAngle: .degrees(start + sweep),clockwise: false)
    return p.applying(CGAffineTransform(a: (x2 - x1) / 2, b: 0, c: 0, d: (y2 - y1) / 2, tx: (x1 + x2) / 2, ty: (y1 + y2) / 2))
  }
}
