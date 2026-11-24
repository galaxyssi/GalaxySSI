import SwiftUI

// Generated from pinned Android #4388 constant curve declarations.
enum GalaxySSIHealthAtlasLangerhansGeometry {
  static let diamond = Path { p in
    p.move(to: .init(x: 0, y: -1))
    p.addLine(to: .init(x: 1, y: 0))
    p.addLine(to: .init(x: 0, y: 1))
    p.addLine(to: .init(x: -1, y: 0))
    p.closeSubpath()
  }
  static let body = Path { p in
    p.move(to: .init(x: -28, y: 3))
    p.addCurve(to: .init(x: -12, y: -21), control1: .init(x: -24, y: -10), control2: .init(x: -17, y: -12))
    p.addCurve(to: .init(x: 17, y: -15), control1: .init(x: -2, y: -31), control2: .init(x: 11, y: -24))
    p.addCurve(to: .init(x: 28, y: 7), control1: .init(x: 25, y: -11), control2: .init(x: 27, y: -1))
    p.addCurve(to: .init(x: 10, y: 21), control1: .init(x: 23, y: 17), control2: .init(x: 18, y: 17))
    p.addCurve(to: .init(x: -22, y: 14), control1: .init(x: -8, y: 31), control2: .init(x: -14, y: 17))
    p.addQuadCurve(to: .init(x: -28, y: 3), control: .init(x: -29, y: 11))
    p.closeSubpath()
  }
  static let tissueBranches = Path { p in
    p.move(to: .init(x: -11, y: 11))
    p.addCurve(to: .init(x: -48, y: 11), control1: .init(x: -23, y: 18), control2: .init(x: -39, y: 21))
    p.addQuadCurve(to: .init(x: -60, y: 10), control: .init(x: -53, y: 7))
    p.move(to: .init(x: -37, y: 17))
    p.addQuadCurve(to: .init(x: -24, y: 35), control: .init(x: -32, y: 25))
    p.move(to: .init(x: 14, y: 14))
    p.addCurve(to: .init(x: 49, y: 10), control1: .init(x: 27, y: 19), control2: .init(x: 37, y: 6))
    p.addQuadCurve(to: .init(x: 60, y: 12), control: .init(x: 54, y: 11))
    p.move(to: .init(x: 35, y: 13))
    p.addQuadCurve(to: .init(x: 53, y: 1), control: .init(x: 43, y: 2))
    p.move(to: .init(x: -7, y: 16))
    p.addQuadCurve(to: .init(x: 1, y: 55), control: .init(x: -9, y: 36))
  }
  static let detailBranches = Path { p in
    p.move(to: .init(x: -11, y: 11))
    p.addCurve(to: .init(x: -53, y: 29), control1: .init(x: -28, y: 23), control2: .init(x: -34, y: 28))
    p.addQuadCurve(to: .init(x: -69, y: 40), control: .init(x: -62, y: 30))
    p.move(to: .init(x: -39, y: 26))
    p.addQuadCurve(to: .init(x: -64, y: 20), control: .init(x: -49, y: 18))
    p.move(to: .init(x: -7, y: 16))
    p.addQuadCurve(to: .init(x: 1, y: 55), control: .init(x: -9, y: 36))
  }
  static let displayBranches = Path { p in
    p.move(to: .init(x: 14, y: 14))
    p.addCurve(to: .init(x: 52, y: 39), control1: .init(x: 28, y: 19), control2: .init(x: 38, y: 35))
    p.addQuadCurve(to: .init(x: 66, y: 39), control: .init(x: 58, y: 41))
    p.move(to: .init(x: 36, y: 28))
    p.addQuadCurve(to: .init(x: 59, y: 16), control: .init(x: 50, y: 25))
  }
  static let keratinocyte = Path { p in
    p.move(to: .init(x: -0.95, y: -0.29))
    p.addQuadCurve(to: .init(x: -0.48, y: -0.95), control: .init(x: -0.88, y: -0.88))
    p.addQuadCurve(to: .init(x: 0.55, y: -0.89), control: .init(x: -0.06, y: -1.05))
    p.addQuadCurve(to: .init(x: 0.99, y: -0.36), control: .init(x: 0.95, y: -0.83))
    p.addQuadCurve(to: .init(x: 0.79, y: 0.66), control: .init(x: 1.06, y: 0.2))
    p.addQuadCurve(to: .init(x: -0.14, y: 0.99), control: .init(x: 0.36, y: 1.02))
    p.addQuadCurve(to: .init(x: -0.91, y: 0.45), control: .init(x: -0.81, y: 0.91))
    p.addQuadCurve(to: .init(x: -0.95, y: -0.29), control: .init(x: -1.04, y: 0.13))
    p.closeSubpath()
  }
}
