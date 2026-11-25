import SwiftUI

// Original Android #4385 path geometry and arc-length route controls.
enum GalaxySSIHealthAtlasClitoralSensoryGeometry {
  static let endingTissue = Path { p in
    p.move(to: CGPoint(x: 51, y: 133))
    p.addCurve(to: CGPoint(x: 286, y: 115), control1: CGPoint(x: 78, y: 78), control2: CGPoint(x: 217, y: 75))
    p.addCurve(to: CGPoint(x: 278, y: 223), control1: CGPoint(x: 320, y: 135), control2: CGPoint(x: 313, y: 202))
    p.addCurve(to: CGPoint(x: 57, y: 206), control1: CGPoint(x: 229, y: 256), control2: CGPoint(x: 91, y: 244))
    p.addCurve(to: CGPoint(x: 51, y: 133), control1: CGPoint(x: 41, y: 186), control2: CGPoint(x: 41, y: 157))
    p.closeSubpath()
  }
  static let endingEdge = Path { p in
    p.move(to: CGPoint(x: 55, y: 141))
    p.addCurve(to: CGPoint(x: 280, y: 125), control1: CGPoint(x: 89, y: 95), control2: CGPoint(x: 213, y: 93))
  }
  static let endingRoute = Path { p in
    p.move(to: CGPoint(x: 112, y: 135))
    p.addCurve(to: CGPoint(x: 155, y: 182), control1: CGPoint(x: 109, y: 164), control2: CGPoint(x: 141, y: 161))
    p.addCurve(to: CGPoint(x: 236, y: 239), control1: CGPoint(x: 176, y: 218), control2: CGPoint(x: 220, y: 211))
    p.addCurve(to: CGPoint(x: 250, y: 287), control1: CGPoint(x: 248, y: 257), control2: CGPoint(x: 247, y: 275))
  }
  static let endingBranches = Path { p in
    p.move(to: CGPoint(x: 155, y: 182))
    p.addCurve(to: CGPoint(x: 151, y: 125), control1: CGPoint(x: 147, y: 166), control2: CGPoint(x: 160, y: 141))
    p.move(to: CGPoint(x: 138, y: 169))
    p.addCurve(to: CGPoint(x: 92, y: 157), control1: CGPoint(x: 126, y: 174), control2: CGPoint(x: 107, y: 171))
    p.move(to: CGPoint(x: 197, y: 211))
    p.addCurve(to: CGPoint(x: 193, y: 129), control1: CGPoint(x: 202, y: 178), control2: CGPoint(x: 182, y: 159))
    p.move(to: CGPoint(x: 199, y: 182))
    p.addCurve(to: CGPoint(x: 227, y: 142), control1: CGPoint(x: 205, y: 166), control2: CGPoint(x: 222, y: 164))
    p.move(to: CGPoint(x: 232, y: 233))
    p.addCurve(to: CGPoint(x: 263, y: 178), control1: CGPoint(x: 250, y: 213), control2: CGPoint(x: 251, y: 190))
  }
  static let dorsalRoute = Path { p in
    p.move(to: CGPoint(x: 179, y: 145))
    p.addCurve(to: CGPoint(x: 167, y: 111), control1: CGPoint(x: 169, y: 137), control2: CGPoint(x: 168, y: 123))
    p.addCurve(to: CGPoint(x: 135, y: 129), control1: CGPoint(x: 162, y: 105), control2: CGPoint(x: 145, y: 118))
    p.addCurve(to: CGPoint(x: 83, y: 212), control1: CGPoint(x: 107, y: 154), control2: CGPoint(x: 91, y: 182))
    p.addCurve(to: CGPoint(x: 62, y: 263), control1: CGPoint(x: 77, y: 240), control2: CGPoint(x: 80, y: 250))
    p.addCurve(to: CGPoint(x: 51, y: 281), control1: CGPoint(x: 56, y: 268), control2: CGPoint(x: 52, y: 273))
  }
  static let pudendalBranch = Path { p in
    p.move(to: CGPoint(x: 72, y: 254))
    p.addCurve(to: CGPoint(x: 109, y: 291), control1: CGPoint(x: 94, y: 264), control2: CGPoint(x: 104, y: 277))
  }
  static let sacralRoute = Path { p in
    p.move(to: CGPoint(x: 41, y: 247))
    p.addCurve(to: CGPoint(x: 111, y: 190), control1: CGPoint(x: 70, y: 240), control2: CGPoint(x: 87, y: 216))
    p.addCurve(to: CGPoint(x: 199, y: 133), control1: CGPoint(x: 143, y: 147), control2: CGPoint(x: 167, y: 127))
    p.addCurve(to: CGPoint(x: 254, y: 157), control1: CGPoint(x: 220, y: 136), control2: CGPoint(x: 230, y: 145))
  }
  static let ventralRoot = Path { p in
    p.move(to: CGPoint(x: 111, y: 190))
    p.addCurve(to: CGPoint(x: 232, y: 200), control1: CGPoint(x: 156, y: 185), control2: CGPoint(x: 177, y: 225))
  }
  static let grayMatter = Path { p in
    p.move(to: CGPoint(x: 250, y: 152))
    p.addCurve(to: CGPoint(x: 271, y: 172), control1: CGPoint(x: 258, y: 153), control2: CGPoint(x: 260, y: 170))
    p.addCurve(to: CGPoint(x: 298, y: 152), control1: CGPoint(x: 284, y: 174), control2: CGPoint(x: 289, y: 154))
    p.addCurve(to: CGPoint(x: 286, y: 183), control1: CGPoint(x: 309, y: 150), control2: CGPoint(x: 294, y: 172))
    p.addCurve(to: CGPoint(x: 295, y: 212), control1: CGPoint(x: 282, y: 191), control2: CGPoint(x: 304, y: 200))
    p.addCurve(to: CGPoint(x: 273, y: 199), control1: CGPoint(x: 288, y: 221), control2: CGPoint(x: 278, y: 201))
    p.addCurve(to: CGPoint(x: 249, y: 213), control1: CGPoint(x: 266, y: 200), control2: CGPoint(x: 258, y: 221))
    p.addCurve(to: CGPoint(x: 257, y: 183), control1: CGPoint(x: 239, y: 202), control2: CGPoint(x: 259, y: 191))
    p.addCurve(to: CGPoint(x: 250, y: 152), control1: CGPoint(x: 255, y: 176), control2: CGPoint(x: 241, y: 153))
    p.closeSubpath()
  }
  static let endingRouteTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 112, y: 135), commands: [
    .init(kind: .cubic, points: [.init(x: 109, y: 164), .init(x: 141, y: 161), .init(x: 155, y: 182)]),
    .init(kind: .cubic, points: [.init(x: 176, y: 218), .init(x: 220, y: 211), .init(x: 236, y: 239)]),
    .init(kind: .cubic, points: [.init(x: 248, y: 257), .init(x: 247, y: 275), .init(x: 250, y: 287)]),
  ]))
  static let dorsalRouteTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 179, y: 145), commands: [
    .init(kind: .cubic, points: [.init(x: 169, y: 137), .init(x: 168, y: 123), .init(x: 167, y: 111)]),
    .init(kind: .cubic, points: [.init(x: 162, y: 105), .init(x: 145, y: 118), .init(x: 135, y: 129)]),
    .init(kind: .cubic, points: [.init(x: 107, y: 154), .init(x: 91, y: 182), .init(x: 83, y: 212)]),
    .init(kind: .cubic, points: [.init(x: 77, y: 240), .init(x: 80, y: 250), .init(x: 62, y: 263)]),
    .init(kind: .cubic, points: [.init(x: 56, y: 268), .init(x: 52, y: 273), .init(x: 51, y: 281)]),
  ]))
  static let sacralRouteTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 41, y: 247), commands: [
    .init(kind: .cubic, points: [.init(x: 70, y: 240), .init(x: 87, y: 216), .init(x: 111, y: 190)]),
    .init(kind: .cubic, points: [.init(x: 143, y: 147), .init(x: 167, y: 127), .init(x: 199, y: 133)]),
    .init(kind: .cubic, points: [.init(x: 220, y: 136), .init(x: 230, y: 145), .init(x: 254, y: 157)]),
  ]))
}
