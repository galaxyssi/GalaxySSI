import SwiftUI

// Generated from pinned Android #4388 constant curve declarations.
enum GalaxySSIHealthAtlasImmuneGeometry {
  static let lymphocyteRim = Path { p in
    p.move(to: .init(x: 0, y: -43))
    p.addCurve(to: .init(x: 42, y: -13), control1: .init(x: 22, y: -45), control2: .init(x: 38, y: -29))
    p.addCurve(to: .init(x: 38, y: 22), control1: .init(x: 46, y: 1), control2: .init(x: 40, y: 13))
    p.addCurve(to: .init(x: -5, y: 43), control1: .init(x: 31, y: 39), control2: .init(x: 14, y: 44))
    p.addCurve(to: .init(x: -43, y: 8), control1: .init(x: -24, y: 43), control2: .init(x: -42, y: 30))
    p.addCurve(to: .init(x: -23, y: -36), control1: .init(x: -46, y: -12), control2: .init(x: -35, y: -32))
    p.addQuadCurve(to: .init(x: 0, y: -43), control: .init(x: -12, y: -41))
    p.closeSubpath()
  }
  static let cueRim = Path { p in
    p.move(to: .init(x: 4, y: -40))
    p.addCurve(to: .init(x: 39, y: -20), control1: .init(x: 22, y: -41), control2: .init(x: 26, y: -24))
    p.addQuadCurve(to: .init(x: 40, y: 1), control: .init(x: 58, y: -11))
    p.addCurve(to: .init(x: 32, y: 34), control1: .init(x: 31, y: 8), control2: .init(x: 50, y: 23))
    p.addCurve(to: .init(x: -28, y: 32), control1: .init(x: 15, y: 46), control2: .init(x: -12, y: 48))
    p.addCurve(to: .init(x: -45, y: -2), control1: .init(x: -44, y: 21), control2: .init(x: -33, y: 11))
    p.addQuadCurve(to: .init(x: -41, y: -23), control: .init(x: -57, y: -17))
    p.addCurve(to: .init(x: 4, y: -40), control1: .init(x: -24, y: -29), control2: .init(x: -17, y: -38))
    p.closeSubpath()
  }
  static let upperPath = Path { p in
    p.move(to: .init(x: 138, y: 160))
    p.addCurve(to: .init(x: 234, y: 104), control1: .init(x: 167, y: 150), control2: .init(x: 169, y: 103))
  }
  static let upperPathRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 138, y: 160), commands: [
    .init(kind: .cubic, points: [.init(x: 167, y: 150), .init(x: 169, y: 103), .init(x: 234, y: 104)])])
  static let lowerPath = Path { p in
    p.move(to: .init(x: 138, y: 185))
    p.addCurve(to: .init(x: 234, y: 243), control1: .init(x: 176, y: 196), control2: .init(x: 178, y: 241))
  }
  static let lowerPathRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 138, y: 185), commands: [
    .init(kind: .cubic, points: [.init(x: 176, y: 196), .init(x: 178, y: 241), .init(x: 234, y: 243)])])
  static let bodyRim = Path { p in
    p.move(to: .init(x: -20, y: -50))
    p.addCurve(to: .init(x: 44, y: -39), control1: .init(x: 2, y: -60), control2: .init(x: 26, y: -54))
    p.addCurve(to: .init(x: 60, y: 6), control1: .init(x: 62, y: -23), control2: .init(x: 54, y: -10))
    p.addCurve(to: .init(x: 18, y: 55), control1: .init(x: 68, y: 29), control2: .init(x: 41, y: 59))
    p.addCurve(to: .init(x: -42, y: 46), control1: .init(x: -10, y: 51), control2: .init(x: -26, y: 62))
    p.addQuadCurve(to: .init(x: -59, y: 16), control: .init(x: -59, y: 31))
    p.addLine(to: .init(x: -59, y: -15))
    p.addQuadCurve(to: .init(x: -20, y: -50), control: .init(x: -54, y: -37))
    p.closeSubpath()
  }
  static let shell = Path { p in
    p.move(to: .init(x: -16, y: -59))
    p.addCurve(to: .init(x: 50, y: -37), control1: .init(x: 12, y: -68), control2: .init(x: 39, y: -55))
    p.addCurve(to: .init(x: 62, y: 15), control1: .init(x: 62, y: -27), control2: .init(x: 65, y: -6))
    p.addCurve(to: .init(x: 4, y: 63), control1: .init(x: 60, y: 45), control2: .init(x: 29, y: 65))
    p.addCurve(to: .init(x: -61, y: 11), control1: .init(x: -29, y: 66), control2: .init(x: -61, y: 48))
    p.addCurve(to: .init(x: -16, y: -59), control1: .init(x: -67, y: -21), control2: .init(x: -47, y: -52))
    p.closeSubpath()
  }
  static let skinTop = Path { p in
    p.move(to: .init(x: 0, y: -22))
    p.addLine(to: .init(x: 178, y: -22))
    p.addLine(to: .init(x: 178, y: -12))
    p.addCurve(to: .init(x: 126, y: -10), control1: .init(x: 156, y: -1), control2: .init(x: 146, y: -23))
    p.addCurve(to: .init(x: 67, y: -10), control1: .init(x: 100, y: 6), control2: .init(x: 89, y: -22))
    p.addCurve(to: .init(x: 0, y: -9), control1: .init(x: 39, y: 3), control2: .init(x: 31, y: -21))
    p.closeSubpath()
  }
}
