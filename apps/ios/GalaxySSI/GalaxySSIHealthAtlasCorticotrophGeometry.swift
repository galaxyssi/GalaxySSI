import SwiftUI

// Generated from pinned Android #4388 constant curve declarations.
enum GalaxySSIHealthAtlasCorticotrophGeometry {
  static let hypothalamus = Path { p in
    p.move(to: .init(x: 65, y: 93))
    p.addCurve(to: .init(x: 169, y: 86), control1: .init(x: 87, y: 58), control2: .init(x: 144, y: 58))
    p.addCurve(to: .init(x: 148, y: 116), control1: .init(x: 183, y: 103), control2: .init(x: 162, y: 116))
    p.addQuadCurve(to: .init(x: 109, y: 113), control: .init(x: 124, y: 143))
    p.addCurve(to: .init(x: 65, y: 93), control1: .init(x: 85, y: 119), control2: .init(x: 64, y: 113))
    p.closeSubpath()
  }
  static let systemic = Path { p in
    p.move(to: .init(x: 78, y: 137))
    p.addCurve(to: .init(x: 182, y: 239), control1: .init(x: 139, y: 150), control2: .init(x: 98, y: 242))
    p.addCurve(to: .init(x: 264, y: 127), control1: .init(x: 239, y: 237), control2: .init(x: 220, y: 136))
  }
  static let systemicRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 78, y: 137), commands: [
    .init(kind: .cubic, points: [.init(x: 139, y: 150), .init(x: 98, y: 242), .init(x: 182, y: 239)]),
    .init(kind: .cubic, points: [.init(x: 239, y: 237), .init(x: 220, y: 136), .init(x: 264, y: 127)])])
  static let kidney = Path { p in
    p.move(to: .init(x: 290, y: 136))
    p.addCurve(to: .init(x: 323, y: 196), control1: .init(x: 320, y: 140), control2: .init(x: 334, y: 168))
    p.addCurve(to: .init(x: 312, y: 238), control1: .init(x: 317, y: 212), control2: .init(x: 324, y: 224))
    p.addCurve(to: .init(x: 255, y: 204), control1: .init(x: 285, y: 269), control2: .init(x: 249, y: 235))
    p.addCurve(to: .init(x: 273, y: 166), control1: .init(x: 258, y: 186), control2: .init(x: 276, y: 183))
    p.addQuadCurve(to: .init(x: 290, y: 136), control: .init(x: 272, y: 135))
    p.closeSubpath()
  }
  static let adrenal = Path { p in
    p.move(to: .init(x: 258, y: 133))
    p.addQuadCurve(to: .init(x: 279, y: 96), control: .init(x: 272, y: 115))
    p.addQuadCurve(to: .init(x: 292, y: 98), control: .init(x: 284, y: 82))
    p.addCurve(to: .init(x: 320, y: 143), control1: .init(x: 307, y: 120), control2: .init(x: 308, y: 130))
    p.addQuadCurve(to: .init(x: 263, y: 141), control: .init(x: 287, y: 132))
    p.addQuadCurve(to: .init(x: 258, y: 133), control: .init(x: 253, y: 143))
    p.closeSubpath()
  }
  static let cortexSection = Path { p in
    p.move(to: .init(x: 41, y: 231))
    p.addCurve(to: .init(x: 165, y: 93), control1: .init(x: 80, y: 214), control2: .init(x: 107, y: 102))
    p.addCurve(to: .init(x: 314, y: 215), control1: .init(x: 220, y: 84), control2: .init(x: 255, y: 175))
    p.addQuadCurve(to: .init(x: 309, y: 242), control: .init(x: 327, y: 226))
    p.addCurve(to: .init(x: 170, y: 249), control1: .init(x: 264, y: 270), control2: .init(x: 214, y: 246))
    p.addCurve(to: .init(x: 41, y: 251), control1: .init(x: 126, y: 249), control2: .init(x: 80, y: 286))
    p.addQuadCurve(to: .init(x: 41, y: 231), control: .init(x: 32, y: 243))
    p.closeSubpath()
  }
  static let fasciculata = Path { p in
    p.move(to: .init(x: 48, y: 239))
    p.addCurve(to: .init(x: 167, y: 108), control1: .init(x: 86, y: 225), control2: .init(x: 117, y: 116))
    p.addCurve(to: .init(x: 310, y: 225), control1: .init(x: 216, y: 101), control2: .init(x: 251, y: 185))
    p.addQuadCurve(to: .init(x: 271, y: 245), control: .init(x: 304, y: 244))
    p.addCurve(to: .init(x: 131, y: 247), control1: .init(x: 215, y: 244), control2: .init(x: 172, y: 232))
    p.addQuadCurve(to: .init(x: 48, y: 246), control: .init(x: 73, y: 267))
    p.closeSubpath()
  }
  static let reticularis = Path { p in
    p.move(to: .init(x: 84, y: 242))
    p.addCurve(to: .init(x: 168, y: 146), control1: .init(x: 110, y: 224), control2: .init(x: 135, y: 153))
    p.addCurve(to: .init(x: 276, y: 235), control1: .init(x: 204, y: 138), control2: .init(x: 244, y: 205))
    p.addQuadCurve(to: .init(x: 192, y: 232), control: .init(x: 230, y: 237))
    p.addCurve(to: .init(x: 84, y: 242), control1: .init(x: 146, y: 226), control2: .init(x: 109, y: 252))
    p.closeSubpath()
  }
  static let medulla = Path { p in
    p.move(to: .init(x: 114, y: 234))
    p.addCurve(to: .init(x: 174, y: 170), control1: .init(x: 132, y: 225), control2: .init(x: 148, y: 175))
    p.addCurve(to: .init(x: 248, y: 226), control1: .init(x: 202, y: 165), control2: .init(x: 225, y: 208))
    p.addQuadCurve(to: .init(x: 182, y: 220), control: .init(x: 207, y: 225))
    p.addQuadCurve(to: .init(x: 114, y: 234), control: .init(x: 149, y: 222))
    p.closeSubpath()
  }
  static let portal = Path { p in
    p.move(to: .init(x: 132, y: 118))
    p.addCurve(to: .init(x: 211, y: 217), control1: .init(x: 119, y: 156), control2: .init(x: 206, y: 148))
  }
  static let portalRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 132, y: 118), commands: [
    .init(kind: .cubic, points: [.init(x: 119, y: 156), .init(x: 206, y: 148), .init(x: 211, y: 217)])])
  static let cortexArc = Path { p in
    p.move(to: .init(x: 73, y: 231))
    p.addCurve(to: .init(x: 223, y: 156), control1: .init(x: 140, y: 83), control2: .init(x: 164, y: 79))
    p.addQuadCurve(to: .init(x: 289, y: 224), control: .init(x: 253, y: 198))
  }
  static let cortexArcRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 73, y: 231), commands: [
    .init(kind: .cubic, points: [.init(x: 140, y: 83), .init(x: 164, y: 79), .init(x: 223, y: 156)]),
    .init(kind: .quad, points: [.init(x: 253, y: 198), .init(x: 289, y: 224)])])
  static let cortisolBlood = Path { p in
    p.move(to: .init(x: 238, y: 88))
    p.addCurve(to: .init(x: 313, y: 264), control1: .init(x: 203, y: 155), control2: .init(x: 277, y: 204))
  }
  static let cortisolBloodRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 238, y: 88), commands: [
    .init(kind: .cubic, points: [.init(x: 203, y: 155), .init(x: 277, y: 204), .init(x: 313, y: 264)])])
}
