import SwiftUI

enum GalaxySSIHealthAtlasSebaceousGeometry {
  static let skin = Path { p in
    p.move(to: CGPoint(x: 15, y: 69))
    p.addCurve(to: CGPoint(x: 73, y: 69), control1: CGPoint(x: 37, y: 62), control2: CGPoint(x: 54, y: 66))
    p.addCurve(to: CGPoint(x: 151, y: 68), control1: CGPoint(x: 95, y: 73), control2: CGPoint(x: 127, y: 64))
    p.addLine(to: CGPoint(x: 151, y: 283))
    p.addQuadCurve(to: CGPoint(x: 139, y: 295), control: CGPoint(x: 151, y: 295))
    p.addLine(to: CGPoint(x: 27, y: 295))
    p.addQuadCurve(to: CGPoint(x: 15, y: 283), control: CGPoint(x: 15, y: 295))
    p.closeSubpath()
  }
  static let skinSurface = Path { p in
    p.move(to: CGPoint(x: 15, y: 69))
    p.addCurve(to: CGPoint(x: 73, y: 69), control1: CGPoint(x: 37, y: 62), control2: CGPoint(x: 54, y: 66))
    p.addCurve(to: CGPoint(x: 151, y: 68), control1: CGPoint(x: 95, y: 73), control2: CGPoint(x: 127, y: 64))
  }
  static let skinEdge = Path { p in
    p.move(to: CGPoint(x: 15, y: 86))
    p.addCurve(to: CGPoint(x: 73, y: 86), control1: CGPoint(x: 38, y: 80), control2: CGPoint(x: 50, y: 85))
    p.addCurve(to: CGPoint(x: 151, y: 85), control1: CGPoint(x: 95, y: 93), control2: CGPoint(x: 125, y: 80))
  }
  static let follicleWall = Path { p in
    p.move(to: CGPoint(x: 67, y: 69))
    p.addCurve(to: CGPoint(x: 82, y: 154), control1: CGPoint(x: 70, y: 99), control2: CGPoint(x: 83, y: 108))
    p.addCurve(to: CGPoint(x: 92, y: 252), control1: CGPoint(x: 81, y: 194), control2: CGPoint(x: 91, y: 215))
    p.addCurve(to: CGPoint(x: 115, y: 280), control1: CGPoint(x: 90, y: 271), control2: CGPoint(x: 102, y: 285))
    p.addCurve(to: CGPoint(x: 124, y: 245), control1: CGPoint(x: 133, y: 275), control2: CGPoint(x: 133, y: 258))
    p.addCurve(to: CGPoint(x: 104, y: 139), control1: CGPoint(x: 108, y: 208), control2: CGPoint(x: 116, y: 170))
    p.addCurve(to: CGPoint(x: 87, y: 69), control1: CGPoint(x: 101, y: 113), control2: CGPoint(x: 91, y: 86))
    p.closeSubpath()
  }
  static let shaft = Path { p in
    p.move(to: CGPoint(x: 55, y: 39))
    p.addCurve(to: CGPoint(x: 84, y: 117), control1: CGPoint(x: 67, y: 55), control2: CGPoint(x: 74, y: 86))
    p.addCurve(to: CGPoint(x: 105, y: 233), control1: CGPoint(x: 98, y: 147), control2: CGPoint(x: 90, y: 192))
    p.addQuadCurve(to: CGPoint(x: 112, y: 265), control: CGPoint(x: 106, y: 248))
  }
  static let locatorGland = Path { p in
    p.move(to: CGPoint(x: 103, y: 133))
    p.addCurve(to: CGPoint(x: 122, y: 121), control1: CGPoint(x: 104, y: 121), control2: CGPoint(x: 115, y: 117))
    p.addCurve(to: CGPoint(x: 145, y: 138), control1: CGPoint(x: 141, y: 112), control2: CGPoint(x: 151, y: 125))
    p.addCurve(to: CGPoint(x: 138, y: 160), control1: CGPoint(x: 159, y: 145), control2: CGPoint(x: 149, y: 161))
    p.addCurve(to: CGPoint(x: 112, y: 154), control1: CGPoint(x: 134, y: 172), control2: CGPoint(x: 110, y: 169))
    p.addQuadCurve(to: CGPoint(x: 103, y: 133), control: CGPoint(x: 103, y: 148))
    p.closeSubpath()
  }
  static let canal = Path { p in
    p.move(to: CGPoint(x: 135, y: 147))
    p.addQuadCurve(to: CGPoint(x: 91, y: 121), control: CGPoint(x: 116, y: 146))
    p.addCurve(to: CGPoint(x: 74, y: 68), control1: CGPoint(x: 87, y: 101), control2: CGPoint(x: 77, y: 84))
    p.addQuadCurve(to: CGPoint(x: 36, y: 67), control: CGPoint(x: 63, y: 64))
  }
  static let canalTrack = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 135, y: 147), commands: [
    .init(kind: .quad, points: [.init(x: 116, y: 146), .init(x: 91, y: 121)]),
    .init(kind: .cubic, points: [.init(x: 87, y: 101), .init(x: 77, y: 84), .init(x: 74, y: 68)]),
    .init(kind: .quad, points: [.init(x: 63, y: 64), .init(x: 36, y: 67)]),
  ])
  static let lobule = Path { p in
    p.move(to: CGPoint(x: 180, y: 182))
    p.addCurve(to: CGPoint(x: 198, y: 137), control1: CGPoint(x: 184, y: 155), control2: CGPoint(x: 196, y: 156))
    p.addCurve(to: CGPoint(x: 242, y: 92), control1: CGPoint(x: 186, y: 105), control2: CGPoint(x: 213, y: 78))
    p.addCurve(to: CGPoint(x: 311, y: 107), control1: CGPoint(x: 266, y: 67), control2: CGPoint(x: 306, y: 80))
    p.addCurve(to: CGPoint(x: 337, y: 166), control1: CGPoint(x: 338, y: 116), control2: CGPoint(x: 350, y: 144))
    p.addCurve(to: CGPoint(x: 309, y: 222), control1: CGPoint(x: 350, y: 194), control2: CGPoint(x: 329, y: 224))
    p.addCurve(to: CGPoint(x: 239, y: 236), control1: CGPoint(x: 297, y: 254), control2: CGPoint(x: 257, y: 258))
    p.addCurve(to: CGPoint(x: 196, y: 202), control1: CGPoint(x: 219, y: 244), control2: CGPoint(x: 192, y: 225))
    p.addQuadCurve(to: CGPoint(x: 180, y: 182), control: CGPoint(x: 181, y: 198))
    p.closeSubpath()
  }
  static let duct = Path { p in
    p.move(to: CGPoint(x: 253, y: 176))
    p.addCurve(to: CGPoint(x: 197, y: 185), control1: CGPoint(x: 229, y: 169), control2: CGPoint(x: 218, y: 191))
    p.addQuadCurve(to: CGPoint(x: 168, y: 170), control: CGPoint(x: 182, y: 182))
  }
  static let ductTrack = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 253, y: 176), commands: [
    .init(kind: .cubic, points: [.init(x: 229, y: 169), .init(x: 218, y: 191), .init(x: 197, y: 185)]),
    .init(kind: .quad, points: [.init(x: 182, y: 182), .init(x: 168, y: 170)]),
  ])
  static let locatorCells: [CGPoint] = [
    CGPoint(x: 126, y: 130),
    CGPoint(x: 138, y: 139),
    CGPoint(x: 126, y: 154),
  ]
  static let basal: [CGPoint] = [
    CGPoint(x: 205, y: 119),
    CGPoint(x: 219, y: 104),
    CGPoint(x: 239, y: 101),
    CGPoint(x: 266, y: 94),
    CGPoint(x: 291, y: 96),
    CGPoint(x: 309, y: 118),
    CGPoint(x: 325, y: 137),
    CGPoint(x: 329, y: 164),
    CGPoint(x: 332, y: 188),
    CGPoint(x: 313, y: 211),
    CGPoint(x: 290, y: 229),
    CGPoint(x: 264, y: 238),
    CGPoint(x: 237, y: 225),
    CGPoint(x: 211, y: 216),
  ]
  static let mature: [CGPoint] = [
    CGPoint(x: 224, y: 132),
    CGPoint(x: 245, y: 118),
    CGPoint(x: 273, y: 116),
    CGPoint(x: 302, y: 137),
    CGPoint(x: 307, y: 178),
    CGPoint(x: 293, y: 204),
    CGPoint(x: 261, y: 215),
    CGPoint(x: 228, y: 202),
    CGPoint(x: 220, y: 158),
    CGPoint(x: 267, y: 148),
    CGPoint(x: 264, y: 188),
  ]
  static let lipidLocations: [CGPoint] = [
    CGPoint(x: -0.48, y: -0.09),
    CGPoint(x: 0.2, y: -0.47),
    CGPoint(x: 0.48, y: 0.11),
    CGPoint(x: 0.01, y: 0.34),
    CGPoint(x: -0.45, y: 0.42),
    CGPoint(x: 0.42, y: 0.53),
  ]
}
