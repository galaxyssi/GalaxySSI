import SwiftUI

// Generated from pinned Android #4388 constant curve declarations.
enum GalaxySSIHealthAtlasGonadotrophGeometry {
  static let ovary = Path { p in
    p.move(to: .init(x: 262, y: 107))
    p.addCurve(to: .init(x: 304, y: 82), control1: .init(x: 256, y: 87), control2: .init(x: 281, y: 75))
    p.addCurve(to: .init(x: 323, y: 115), control1: .init(x: 322, y: 86), control2: .init(x: 331, y: 103))
    p.addCurve(to: .init(x: 262, y: 107), control1: .init(x: 308, y: 138), control2: .init(x: 271, y: 133))
    p.closeSubpath()
  }
  static let sertoliCell = Path { p in
    p.move(to: .init(x: 105, y: 137))
    p.addQuadCurve(to: .init(x: 133, y: 129), control: .init(x: 118, y: 129))
    p.addCurve(to: .init(x: 145, y: 182), control1: .init(x: 130, y: 149), control2: .init(x: 149, y: 161))
    p.addQuadCurve(to: .init(x: 133, y: 187), control: .init(x: 143, y: 193))
    p.addCurve(to: .init(x: 105, y: 137), control1: .init(x: 127, y: 180), control2: .init(x: 125, y: 157))
    p.closeSubpath()
  }
  static let input = Path { p in
    p.move(to: .init(x: 77, y: 156))
    p.addCurve(to: .init(x: 237, y: 181), control1: .init(x: 138, y: 108), control2: .init(x: 157, y: 215))
  }
  static let inputRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 77, y: 156), commands: [
    .init(kind: .cubic, points: [.init(x: 138, y: 108), .init(x: 157, y: 215), .init(x: 237, y: 181)])])
  static let trunk = Path { p in
    p.move(to: .init(x: 87, y: 178))
    p.addCurve(to: .init(x: 178, y: 175), control1: .init(x: 124, y: 184), control2: .init(x: 159, y: 180))
  }
  static let trunkRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 87, y: 178), commands: [
    .init(kind: .cubic, points: [.init(x: 124, y: 184), .init(x: 159, y: 180), .init(x: 178, y: 175)])])
  static let ovarianBranch = Path { p in
    p.move(to: .init(x: 178, y: 175))
    p.addCurve(to: .init(x: 271, y: 104), control1: .init(x: 214, y: 158), control2: .init(x: 211, y: 103))
  }
  static let ovarianBranchRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 178, y: 175), commands: [
    .init(kind: .cubic, points: [.init(x: 214, y: 158), .init(x: 211, y: 103), .init(x: 271, y: 104)])])
  static let testisBranch = Path { p in
    p.move(to: .init(x: 178, y: 175))
    p.addCurve(to: .init(x: 272, y: 239), control1: .init(x: 214, y: 189), control2: .init(x: 217, y: 241))
  }
  static let testisBranchRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 178, y: 175), commands: [
    .init(kind: .cubic, points: [.init(x: 214, y: 189), .init(x: 217, y: 241), .init(x: 272, y: 239)])])
  static let ovarianFsh = Path { p in
    p.move(to: .init(x: 34, y: 115))
    p.addCurve(to: .init(x: 136, y: 156), control1: .init(x: 82, y: 109), control2: .init(x: 104, y: 129))
  }
  static let ovarianFshRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 34, y: 115), commands: [
    .init(kind: .cubic, points: [.init(x: 82, y: 109), .init(x: 104, y: 129), .init(x: 136, y: 156)])])
  static let ovarianLh = Path { p in
    p.move(to: .init(x: 331, y: 132))
    p.addCurve(to: .init(x: 260, y: 146), control1: .init(x: 301, y: 126), control2: .init(x: 283, y: 130))
  }
  static let ovarianLhRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 331, y: 132), commands: [
    .init(kind: .cubic, points: [.init(x: 301, y: 126), .init(x: 283, y: 130), .init(x: 260, y: 146)])])
  static let testisFsh = Path { p in
    p.move(to: .init(x: 37, y: 103))
    p.addCurve(to: .init(x: 117, y: 136), control1: .init(x: 74, y: 106), control2: .init(x: 99, y: 112))
  }
  static let testisFshRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 37, y: 103), commands: [
    .init(kind: .cubic, points: [.init(x: 74, y: 106), .init(x: 99, y: 112), .init(x: 117, y: 136)])])
  static let testisLh = Path { p in
    p.move(to: .init(x: 326, y: 103))
    p.addCurve(to: .init(x: 249, y: 171), control1: .init(x: 280, y: 107), control2: .init(x: 270, y: 138))
  }
  static let testisLhRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 326, y: 103), commands: [
    .init(kind: .cubic, points: [.init(x: 280, y: 107), .init(x: 270, y: 138), .init(x: 249, y: 171)])])
}
