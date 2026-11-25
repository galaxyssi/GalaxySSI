import SwiftUI

// Original Android #4385 outlines in the source drawing coordinate system.
enum GalaxySSIHealthAtlasPectoralGeometry {
  static let chest = Path { p in
    p.move(to: CGPoint(x: 60, y: 146))
    p.addCurve(to: CGPoint(x: 149, y: 84), control1: CGPoint(x: 62, y: 112), control2: CGPoint(x: 111, y: 85))
    p.addCurve(to: CGPoint(x: 242, y: 142), control1: CGPoint(x: 193, y: 82), control2: CGPoint(x: 237, y: 107))
    p.addCurve(to: CGPoint(x: 174, y: 210), control1: CGPoint(x: 249, y: 180), control2: CGPoint(x: 217, y: 202))
    p.addCurve(to: CGPoint(x: 60, y: 146), control1: CGPoint(x: 122, y: 220), control2: CGPoint(x: 63, y: 193))
    p.closeSubpath()
  }
  static let thorax = Path { p in
    p.move(to: CGPoint(x: 82, y: 147))
    p.addCurve(to: CGPoint(x: 147, y: 103), control1: CGPoint(x: 87, y: 121), control2: CGPoint(x: 122, y: 103))
    p.addCurve(to: CGPoint(x: 220, y: 148), control1: CGPoint(x: 180, y: 100), control2: CGPoint(x: 215, y: 119))
    p.addCurve(to: CGPoint(x: 151, y: 192), control1: CGPoint(x: 225, y: 177), control2: CGPoint(x: 185, y: 192))
    p.addCurve(to: CGPoint(x: 82, y: 147), control1: CGPoint(x: 119, y: 192), control2: CGPoint(x: 75, y: 176))
    p.closeSubpath()
  }
  static let farFan = Path { p in
    p.move(to: CGPoint(x: 146, y: 169))
    p.addCurve(to: CGPoint(x: 85, y: 154), control1: CGPoint(x: 117, y: 168), control2: CGPoint(x: 104, y: 159))
    p.addCurve(to: CGPoint(x: 147, y: 204), control1: CGPoint(x: 88, y: 179), control2: CGPoint(x: 116, y: 202))
    p.addQuadCurve(to: CGPoint(x: 146, y: 169), control: CGPoint(x: 151, y: 188))
    p.closeSubpath()
  }
  static let arm = Path { p in
    p.move(to: CGPoint(x: -8, y: -12))
    p.addCurve(to: CGPoint(x: 83, y: -10), control1: CGPoint(x: 24, y: -18), control2: CGPoint(x: 60, y: -14))
    p.addQuadCurve(to: CGPoint(x: 99, y: 3), control: CGPoint(x: 93, y: -7))
    p.addLine(to: CGPoint(x: 117, y: 20))
    p.addQuadCurve(to: CGPoint(x: 113, y: 34), control: CGPoint(x: 122, y: 28))
    p.addQuadCurve(to: CGPoint(x: 101, y: 29), control: CGPoint(x: 107, y: 37))
    p.addLine(to: CGPoint(x: 80, y: 13))
    p.addQuadCurve(to: CGPoint(x: -7, y: 15), control: CGPoint(x: 38, y: 16))
    p.addQuadCurve(to: CGPoint(x: -8, y: -12), control: CGPoint(x: -21, y: 4))
    p.closeSubpath()
  }
  static let humerus = Path { p in
    p.move(to: CGPoint(x: -8, y: -8))
    p.addQuadCurve(to: CGPoint(x: 17, y: -6), control: CGPoint(x: 4, y: -15))
    p.addCurve(to: CGPoint(x: 78, y: -6), control1: CGPoint(x: 38, y: -3), control2: CGPoint(x: 59, y: -5))
    p.addQuadCurve(to: CGPoint(x: 88, y: 4), control: CGPoint(x: 89, y: -6))
    p.addQuadCurve(to: CGPoint(x: 76, y: 8), control: CGPoint(x: 85, y: 11))
    p.addCurve(to: CGPoint(x: 17, y: 7), control1: CGPoint(x: 55, y: 5), control2: CGPoint(x: 38, y: 4))
    p.addQuadCurve(to: CGPoint(x: -8, y: 8), control: CGPoint(x: 4, y: 15))
    p.addQuadCurve(to: CGPoint(x: -8, y: -8), control: CGPoint(x: -15, y: 1))
    p.closeSubpath()
  }
}
