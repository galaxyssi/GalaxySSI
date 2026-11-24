import SwiftUI

// Generated from pinned Android #4388 constant curve declarations.
enum GalaxySSIHealthAtlasSomatotrophGeometry {
  static let cell = Path { p in
    p.move(to: .init(x: 74, y: 169))
    p.addCurve(to: .init(x: 151, y: 99), control1: .init(x: 64, y: 132), control2: .init(x: 97, y: 102))
    p.addCurve(to: .init(x: 280, y: 161), control1: .init(x: 211, y: 92), control2: .init(x: 277, y: 107))
    p.addCurve(to: .init(x: 173, y: 219), control1: .init(x: 286, y: 199), control2: .init(x: 228, y: 222))
    p.addCurve(to: .init(x: 74, y: 169), control1: .init(x: 132, y: 221), control2: .init(x: 86, y: 206))
    p.closeSubpath()
  }
  static let liverShape = Path { p in
    p.move(to: .init(x: 8, y: 42))
    p.addCurve(to: .init(x: 74, y: 14), control1: .init(x: 11, y: 18), control2: .init(x: 40, y: 7))
    p.addCurve(to: .init(x: 141, y: 25), control1: .init(x: 100, y: 16), control2: .init(x: 117, y: 26))
    p.addCurve(to: .init(x: 94, y: 67), control1: .init(x: 138, y: 46), control2: .init(x: 114, y: 62))
    p.addCurve(to: .init(x: 34, y: 99), control1: .init(x: 76, y: 71), control2: .init(x: 65, y: 95))
    p.addCurve(to: .init(x: 8, y: 42), control1: .init(x: 13, y: 99), control2: .init(x: 5, y: 71))
    p.closeSubpath()
  }
  static let fiber = Path { p in
    p.move(to: .init(x: 2, y: 10))
    p.addCurve(to: .init(x: 122, y: 6), control1: .init(x: 14, y: 1), control2: .init(x: 90, y: 0))
    p.addQuadCurve(to: .init(x: 124, y: 18), control: .init(x: 132, y: 10))
    p.addCurve(to: .init(x: 7, y: 21), control1: .init(x: 101, y: 26), control2: .init(x: 25, y: 25))
    p.addQuadCurve(to: .init(x: 2, y: 10), control: .init(x: 1, y: 19))
    p.closeSubpath()
  }
  static let capillary = Path { p in
    p.move(to: .init(x: 34, y: 247))
    p.addCurve(to: .init(x: 326, y: 242), control1: .init(x: 115, y: 223), control2: .init(x: 250, y: 268))
  }
  static let capillaryRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 34, y: 247), commands: [
    .init(kind: .cubic, points: [.init(x: 115, y: 223), .init(x: 250, y: 268), .init(x: 326, y: 242)])])
  static let trunk = Path { p in
    p.move(to: .init(x: 89, y: 182))
    p.addCurve(to: .init(x: 143, y: 182), control1: .init(x: 103, y: 180), control2: .init(x: 121, y: 178))
  }
  static let trunkRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 89, y: 182), commands: [
    .init(kind: .cubic, points: [.init(x: 103, y: 180), .init(x: 121, y: 178), .init(x: 143, y: 182)])])
  static let upperBranch = Path { p in
    p.move(to: .init(x: 143, y: 182))
    p.addCurve(to: .init(x: 246, y: 111), control1: .init(x: 179, y: 182), control2: .init(x: 173, y: 111))
  }
  static let upperBranchRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 143, y: 182), commands: [
    .init(kind: .cubic, points: [.init(x: 179, y: 182), .init(x: 173, y: 111), .init(x: 246, y: 111)])])
  static let lowerBranch = Path { p in
    p.move(to: .init(x: 143, y: 182))
    p.addCurve(to: .init(x: 240, y: 248), control1: .init(x: 175, y: 183), control2: .init(x: 178, y: 248))
  }
  static let lowerBranchRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 143, y: 182), commands: [
    .init(kind: .cubic, points: [.init(x: 175, y: 183), .init(x: 178, y: 248), .init(x: 240, y: 248)])])
  static let liverDivision = Path { p in
    p.move(to: .init(x: 76, y: 16))
    p.addCurve(to: .init(x: 93, y: 67), control1: .init(x: 66, y: 40), control2: .init(x: 81, y: 56))
  }
  static let input = Path { p in
    p.move(to: .init(x: 39, y: 84))
    p.addCurve(to: .init(x: 140, y: 148), control1: .init(x: 95, y: 83), control2: .init(x: 130, y: 103))
  }
  static let inputRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 39, y: 84), commands: [
    .init(kind: .cubic, points: [.init(x: 95, y: 83), .init(x: 130, y: 103), .init(x: 140, y: 148)])])
  static let hepaticOut = Path { p in
    p.move(to: .init(x: 153, y: 187))
    p.addCurve(to: .init(x: 316, y: 259), control1: .init(x: 200, y: 195), control2: .init(x: 216, y: 263))
  }
  static let hepaticOutRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 153, y: 187), commands: [
    .init(kind: .cubic, points: [.init(x: 200, y: 195), .init(x: 216, y: 263), .init(x: 316, y: 259)])])
  static let muscleGh = Path { p in
    p.move(to: .init(x: 47, y: 98))
    p.addCurve(to: .init(x: 129, y: 168), control1: .init(x: 82, y: 99), control2: .init(x: 96, y: 146))
  }
  static let muscleGhRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 47, y: 98), commands: [
    .init(kind: .cubic, points: [.init(x: 82, y: 99), .init(x: 96, y: 146), .init(x: 129, y: 168)])])
  static let muscleIgf = Path { p in
    p.move(to: .init(x: 312, y: 98))
    p.addCurve(to: .init(x: 237, y: 168), control1: .init(x: 283, y: 99), control2: .init(x: 270, y: 146))
  }
  static let muscleIgfRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 312, y: 98), commands: [
    .init(kind: .cubic, points: [.init(x: 283, y: 99), .init(x: 270, y: 146), .init(x: 237, y: 168)])])
}
