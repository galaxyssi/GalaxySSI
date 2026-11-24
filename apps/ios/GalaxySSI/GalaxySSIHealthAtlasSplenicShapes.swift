import SwiftUI

enum GalaxySSIHealthAtlasSplenicShapes {
  static let rose: UInt32 = 0xA35669, plum: UInt32 = 0x80475E, sinusEdge: UInt32 = 0x67988E
  static let fiber: UInt32 = 0xEAC3B5, leader: UInt32 = 0x627A77, iron: UInt32 = 0x97632D
  static let field = Path(roundedRect: CGRect(x: 24, y: 141, width: 312, height: 170), cornerRadius: 17)
  static let spleen = Path { p in
    p.move(to: CGPoint(x: 31, y: 85))
    p.addCurve(to: CGPoint(x: 67, y: 28), control1: CGPoint(x: 23, y: 65), control2: CGPoint(x: 41, y: 36))
    p.addCurve(to: CGPoint(x: 116, y: 41), control1: CGPoint(x: 87, y: 22), control2: CGPoint(x: 110, y: 30))
    p.addCurve(to: CGPoint(x: 100, y: 63), control1: CGPoint(x: 121, y: 52), control2: CGPoint(x: 107, y: 56))
    p.addCurve(to: CGPoint(x: 93, y: 86), control1: CGPoint(x: 92, y: 71), control2: CGPoint(x: 100, y: 77))
    p.addCurve(to: CGPoint(x: 31, y: 85), control1: CGPoint(x: 81, y: 104), control2: CGPoint(x: 42, y: 110)); p.closeSubpath()
  }
  static func macrophage(_ reach: Double) -> Path {
    Path { p in
      p.move(to: CGPoint(x: 59, y: 271))
      p.addCurve(to: CGPoint(x: 76, y: 241), control1: CGPoint(x: 56, y: 252), control2: CGPoint(x: 69, y: 249))
      p.addCurve(to: CGPoint(x: 111, y: 232), control1: CGPoint(x: 82, y: 231), control2: CGPoint(x: 97, y: 224))
      p.addCurve(to: CGPoint(x: 145 + 20 * reach, y: 245 - 7 * reach), control1: CGPoint(x: 126, y: 242 - 10 * reach), control2: CGPoint(x: 141 + 17 * reach, y: 234 - 9 * reach))
      p.addCurve(to: CGPoint(x: 134, y: 258), control1: CGPoint(x: 146 + 18 * reach, y: 251 - 5 * reach), control2: CGPoint(x: 133, y: 252))
      p.addCurve(to: CGPoint(x: 148 + 17 * reach, y: 269 + 6 * reach), control1: CGPoint(x: 135, y: 266), control2: CGPoint(x: 146 + 15 * reach, y: 259 + 7 * reach))
      p.addCurve(to: CGPoint(x: 125, y: 289), control1: CGPoint(x: 150, y: 284), control2: CGPoint(x: 131, y: 280))
      p.addCurve(to: CGPoint(x: 92, y: 295), control1: CGPoint(x: 115, y: 301), control2: CGPoint(x: 102, y: 300))
      p.addCurve(to: CGPoint(x: 59, y: 271), control1: CGPoint(x: 79, y: 289), control2: CGPoint(x: 61, y: 295)); p.closeSubpath()
    }
  }
  static func arc(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, start: Double, sweep: Double) -> Path {
    if abs(sweep) >= 360 { return Path(ellipseIn: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)) }
    var p = Path()
    p.addArc(center: .zero, radius: 1, startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false)
    return p.applying(CGAffineTransform(a: (x2 - x1) / 2, b: 0, c: 0, d: (y2 - y1) / 2, tx: (x1 + x2) / 2, ty: (y1 + y2) / 2))
  }
}
