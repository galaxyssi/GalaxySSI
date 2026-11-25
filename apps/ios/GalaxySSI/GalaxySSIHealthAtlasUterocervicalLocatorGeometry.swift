import SwiftUI

// Android #4385 declarations evaluated with original Float arithmetic and relative controls.
enum GalaxySSIHealthAtlasUterocervicalLocatorGeometry {
  static let locatorVagina = Path { p in
    p.move(to: CGPoint(x: 51, y: 168))
    p.addCurve(to: CGPoint(x: 61, y: 214), control1: CGPoint(x: 43, y: 180), control2: CGPoint(x: 49, y: 200))
    p.addCurve(to: CGPoint(x: 95, y: 269), control1: CGPoint(x: 72, y: 231), control2: CGPoint(x: 85, y: 252))
    p.addQuadCurve(to: CGPoint(x: 114, y: 269), control: CGPoint(x: 104, y: 278))
    p.addCurve(to: CGPoint(x: 86, y: 211), control1: CGPoint(x: 107, y: 246), control2: CGPoint(x: 92, y: 229))
    p.addCurve(to: CGPoint(x: 94, y: 167), control1: CGPoint(x: 81, y: 194), control2: CGPoint(x: 110, y: 183))
    p.addQuadCurve(to: CGPoint(x: 51, y: 168), control: CGPoint(x: 72, y: 157))
    p.closeSubpath()
  }
  static let locatorVaginalSpace = Path { p in
    p.move(to: CGPoint(x: 55, y: 176))
    p.addCurve(to: CGPoint(x: 99, y: 268), control1: CGPoint(x: 52, y: 202), control2: CGPoint(x: 85, y: 226))
    p.addQuadCurve(to: CGPoint(x: 109, y: 268), control: CGPoint(x: 104, y: 271))
    p.addCurve(to: CGPoint(x: 78, y: 197), control1: CGPoint(x: 96, y: 234), control2: CGPoint(x: 72, y: 218))
    p.addQuadCurve(to: CGPoint(x: 92, y: 176), control: CGPoint(x: 94, y: 182))
    p.closeSubpath()
  }
  static let locatorCervix = Path { p in
    p.move(to: CGPoint(x: 56, y: 138))
    p.addQuadCurve(to: CGPoint(x: 86, y: 138), control: CGPoint(x: 72, y: 129))
    p.addCurve(to: CGPoint(x: 87, y: 186), control1: CGPoint(x: 84, y: 151), control2: CGPoint(x: 94, y: 167))
    p.addQuadCurve(to: CGPoint(x: 60, y: 185), control: CGPoint(x: 74, y: 197))
    p.addCurve(to: CGPoint(x: 56, y: 138), control1: CGPoint(x: 54, y: 171), control2: CGPoint(x: 62, y: 153))
    p.closeSubpath()
  }
  static let locatorUterus = Path { p in
    p.move(to: CGPoint(x: 27, y: 77))
    p.addCurve(to: CGPoint(x: 72, y: 59), control1: CGPoint(x: 36, y: 64), control2: CGPoint(x: 49, y: 59))
    p.addCurve(to: CGPoint(x: 119, y: 78), control1: CGPoint(x: 95, y: 59), control2: CGPoint(x: 110, y: 66))
    p.addCurve(to: CGPoint(x: 101, y: 123), control1: CGPoint(x: 109, y: 92), control2: CGPoint(x: 113, y: 110))
    p.addQuadCurve(to: CGPoint(x: 85, y: 147), control: CGPoint(x: 88, y: 136))
    p.addQuadCurve(to: CGPoint(x: 58, y: 147), control: CGPoint(x: 72, y: 154))
    p.addQuadCurve(to: CGPoint(x: 42, y: 121), control: CGPoint(x: 56, y: 133))
    p.addCurve(to: CGPoint(x: 27, y: 77), control1: CGPoint(x: 31, y: 108), control2: CGPoint(x: 34, y: 91))
    p.closeSubpath()
  }
  static let locatorCavity = Path { p in
    p.move(to: CGPoint(x: 37, y: 80))
    p.addQuadCurve(to: CGPoint(x: 108, y: 80), control: CGPoint(x: 72, y: 91))
    p.addCurve(to: CGPoint(x: 76, y: 126), control1: CGPoint(x: 88, y: 93), control2: CGPoint(x: 86, y: 112))
    p.addQuadCurve(to: CGPoint(x: 74, y: 138), control: CGPoint(x: 73, y: 130))
    p.addLine(to: CGPoint(x: 68, y: 138))
    p.addQuadCurve(to: CGPoint(x: 65, y: 125), control: CGPoint(x: 69, y: 132))
    p.addCurve(to: CGPoint(x: 37, y: 80), control1: CGPoint(x: 54, y: 110), control2: CGPoint(x: 55, y: 95))
    p.closeSubpath()
  }
  static let locatorCanal = Path { p in
    p.move(to: CGPoint(x: 71, y: 137))
    p.addCurve(to: CGPoint(x: 74, y: 192), control1: CGPoint(x: 71, y: 153), control2: CGPoint(x: 77, y: 175))
  }
  static let locatorTraces: [Path] = [
    Path { p in
      p.move(to: CGPoint(x: 72, y: 89))
      p.addQuadCurve(to: CGPoint(x: 71, y: 137), control: CGPoint(x: 67, y: 114))
    },
    Path { p in
      p.move(to: CGPoint(x: 71, y: 137))
      p.addCurve(to: CGPoint(x: 74, y: 192), control1: CGPoint(x: 71, y: 153), control2: CGPoint(x: 77, y: 175))
    },
    Path { p in
      p.move(to: CGPoint(x: 74, y: 192))
      p.addCurve(to: CGPoint(x: 104, y: 269), control1: CGPoint(x: 66, y: 211), control2: CGPoint(x: 92, y: 236))
    }
  ]
  static let tracks = [
    GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 72, y: 89), commands: [
      .init(kind: .quad, points: [.init(x: 67, y: 114), .init(x: 71, y: 137)]),
    ])),
    GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 71, y: 137), commands: [
      .init(kind: .cubic, points: [.init(x: 71, y: 153), .init(x: 77, y: 175), .init(x: 74, y: 192)]),
    ])),
    GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 74, y: 192), commands: [
      .init(kind: .cubic, points: [.init(x: 66, y: 211), .init(x: 92, y: 236), .init(x: 104, y: 269)]),
    ]))
  ]
  static let locatorOs = Path { p in
    p.move(to: CGPoint(x: 62, y: 188))
    p.addQuadCurve(to: CGPoint(x: 86, y: 188), control: CGPoint(x: 74, y: 194))
  }
  static let locatorWallTexture = Path { p in
    p.move(to: CGPoint(x: 38, y: 89))
    p.addQuadCurve(to: CGPoint(x: 55, y: 122), control: CGPoint(x: 42, y: 112))
    p.move(to: CGPoint(x: 107, y: 93))
    p.addQuadCurve(to: CGPoint(x: 91, y: 123), control: CGPoint(x: 104, y: 112))
    p.move(to: CGPoint(x: 54, y: 204))
    p.addQuadCurve(to: CGPoint(x: 63, y: 202), control: CGPoint(x: 58, y: 201))
    p.move(to: CGPoint(x: 61, y: 216))
    p.addQuadCurve(to: CGPoint(x: 70, y: 213), control: CGPoint(x: 65, y: 212))
    p.move(to: CGPoint(x: 69, y: 229))
    p.addQuadCurve(to: CGPoint(x: 78, y: 227), control: CGPoint(x: 73, y: 225))
    p.move(to: CGPoint(x: 77, y: 241))
    p.addQuadCurve(to: CGPoint(x: 86, y: 240), control: CGPoint(x: 81, y: 237))
  }
}
