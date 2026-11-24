import SwiftUI

enum GalaxySSIHealthAtlasSatelliteGeometry {
  static let signal = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 62, y: 117), commands: [
    .init(kind: .cubic, points: [.init(x: 85, y: 110), .init(x: 113, y: 116), .init(x: 139, y: 145)])])
  static func progress(_ value: Double, _ start: Double, _ end: Double) -> Double {
    let t = min(1, max(0, (value - start) / (end - start))); return t * t * (3 - 2 * t)
  }
  static func mix(_ from: UInt32, _ to: UInt32, _ t: Double) -> UInt32 {
    var result: UInt32 = 0xFF000000
    for shift in stride(from: 0, through: 16, by: 8) {
      let a = Double((from >> shift) & 255), b = Double((to >> shift) & 255)
      result |= UInt32(Int(a + (b - a) * t)) << shift
    }
    return result
  }
  static func cell(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) -> Path {
    Path { p in
      p.move(to: CGPoint(x: x - rx, y: y + 0.08 * ry))
      p.addCurve(to: CGPoint(x: x + 0.06 * rx, y: y - ry), control1: CGPoint(x: x - 0.65 * rx, y: y - 0.8 * ry), control2: CGPoint(x: x - 0.39 * rx, y: y - ry))
      p.addCurve(to: CGPoint(x: x + rx, y: y + 0.06 * ry), control1: CGPoint(x: x + 0.49 * rx, y: y - ry), control2: CGPoint(x: x + 0.74 * rx, y: y - 0.42 * ry))
      p.addCurve(to: CGPoint(x: x - 0.06 * rx, y: y + ry), control1: CGPoint(x: x + 0.68 * rx, y: y + 0.59 * ry), control2: CGPoint(x: x + 0.33 * rx, y: y + ry))
      p.addCurve(to: CGPoint(x: x - rx, y: y + 0.08 * ry), control1: CGPoint(x: x - 0.49 * rx, y: y + ry), control2: CGPoint(x: x - 0.8 * rx, y: y + 0.45 * ry)); p.closeSubpath()
    }
  }
  static func sarcolemma(_ rise: Double) -> Path {
    Path { p in
      p.move(to: CGPoint(x: 50, y: 202))
      if rise > 0 {
        p.addLine(to: CGPoint(x: 204, y: 202))
        p.addCurve(to: CGPoint(x: 247, y: 202 - rise), control1: CGPoint(x: 219, y: 202), control2: CGPoint(x: 220, y: 202 - rise))
        p.addCurve(to: CGPoint(x: 290, y: 202), control1: CGPoint(x: 274, y: 202 - rise), control2: CGPoint(x: 275, y: 202))
      }
      p.addLine(to: CGPoint(x: 310, y: 202))
    }
  }
  static func fiber(_ rise: Double) -> Path {
    var p = sarcolemma(rise)
    p.addCurve(to: CGPoint(x: 334, y: 229), control1: CGPoint(x: 326, y: 202), control2: CGPoint(x: 334, y: 213))
    p.addLine(to: CGPoint(x: 334, y: 267)); p.addCurve(to: CGPoint(x: 308, y: 294), control1: CGPoint(x: 334, y: 284), control2: CGPoint(x: 325, y: 294))
    p.addLine(to: CGPoint(x: 52, y: 294)); p.addCurve(to: CGPoint(x: 26, y: 267), control1: CGPoint(x: 35, y: 294), control2: CGPoint(x: 26, y: 284))
    p.addLine(to: CGPoint(x: 26, y: 229)); p.addCurve(to: CGPoint(x: 50, y: 202), control1: CGPoint(x: 26, y: 213), control2: CGPoint(x: 34, y: 202)); p.closeSubpath(); return p
  }
  static func lamina(_ x: Double, _ lift: Double, _ x2: Double = 0, _ lift2: Double = 0, span: Double = 58) -> Path {
    var p = Path(); p.move(to: CGPoint(x: 32, y: 188))
    func arch(_ center: Double, _ height: Double, _ width: Double) {
      let top = 188 - height
      p.addLine(to: CGPoint(x: center - width, y: 188))
      p.addCurve(to: CGPoint(x: center, y: top), control1: CGPoint(x: center - 0.67 * width, y: 188), control2: CGPoint(x: center - 0.68 * width, y: top))
      p.addCurve(to: CGPoint(x: center + width, y: 188), control1: CGPoint(x: center + 0.68 * width, y: top), control2: CGPoint(x: center + 0.67 * width, y: 188))
    }
    arch(x, lift, span); if lift2 > 0 { arch(x2, lift2, 68) }; p.addLine(to: CGPoint(x: 328, y: 188)); return p
  }
  static func branchLamina(_ left: Double, _ right: Double, _ leftTop: Double, _ rightTop: Double) -> Path {
    let mid = (left + right) / 2, bridge = max(leftTop, rightTop) + 9
    return Path { p in
      p.move(to: CGPoint(x: 32, y: 188)); p.addLine(to: CGPoint(x: left - 61, y: 188))
      p.addCurve(to: CGPoint(x: left, y: leftTop), control1: CGPoint(x: left - 40, y: 188), control2: CGPoint(x: left - 42, y: leftTop))
      p.addCurve(to: CGPoint(x: mid, y: bridge), control1: CGPoint(x: left + 22, y: leftTop), control2: CGPoint(x: mid - 12, y: bridge))
      p.addCurve(to: CGPoint(x: right, y: rightTop), control1: CGPoint(x: mid + 12, y: bridge), control2: CGPoint(x: right - 22, y: rightTop))
      p.addCurve(to: CGPoint(x: right + 63, y: 188), control1: CGPoint(x: right + 42, y: rightTop), control2: CGPoint(x: right + 42, y: 188)); p.addLine(to: CGPoint(x: 328, y: 188))
    }
  }
  static func dividing(_ y: Double, _ pinch: Double) -> Path {
    let offset = 9 + 21 * pinch, ry = 24 - 2 * pinch, neck = ry * (1 - pinch)
    return Path { p in
      p.move(to: CGPoint(x: 180 - offset - 30, y: y))
      for direction in [1.0, -1.0] {
        let dy = -ry * direction, waistY = y - neck * direction, from = 180 - offset * direction, to = 180 + offset * direction
        p.addCurve(to: CGPoint(x: from, y: y + dy), control1: CGPoint(x: from - 28 * direction, y: y + dy * 0.72), control2: CGPoint(x: from - 16 * direction, y: y + dy))
        p.addCurve(to: CGPoint(x: 180, y: waistY), control1: CGPoint(x: from + 0.62 * offset * direction, y: y + dy), control2: CGPoint(x: 180 - 5 * direction, y: waistY))
        p.addCurve(to: CGPoint(x: to, y: y + dy), control1: CGPoint(x: 180 + 5 * direction, y: waistY), control2: CGPoint(x: to - 0.62 * offset * direction, y: y + dy))
        p.addCurve(to: CGPoint(x: to + 30 * direction, y: y), control1: CGPoint(x: to + 16 * direction, y: y + dy), control2: CGPoint(x: to + 28 * direction, y: y + dy * 0.72))
      }
      p.closeSubpath()
    }
  }
}
