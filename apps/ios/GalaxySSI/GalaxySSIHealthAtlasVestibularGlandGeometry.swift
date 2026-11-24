import SwiftUI

// Original Android #4385 path geometry and arc-length route controls.
enum GalaxySSIHealthAtlasVestibularGlandGeometry {
  static let upper = Path { p in
    p.move(to: CGPoint(x: 91, y: 113))
    p.addCurve(to: CGPoint(x: 175, y: 170), control1: CGPoint(x: 143, y: 113), control2: CGPoint(x: 154, y: 141))
    p.addQuadCurve(to: CGPoint(x: 212, y: 182), control: CGPoint(x: 184, y: 182))
  }
  static let middle = Path { p in
    p.move(to: CGPoint(x: 106, y: 182))
    p.addCurve(to: CGPoint(x: 212, y: 182), control1: CGPoint(x: 144, y: 182), control2: CGPoint(x: 174, y: 181))
  }
  static let lower = Path { p in
    p.move(to: CGPoint(x: 91, y: 251))
    p.addCurve(to: CGPoint(x: 175, y: 195), control1: CGPoint(x: 143, y: 251), control2: CGPoint(x: 154, y: 223))
    p.addQuadCurve(to: CGPoint(x: 212, y: 182), control: CGPoint(x: 184, y: 183))
  }
  static let main = Path { p in
    p.move(to: CGPoint(x: 212, y: 182))
    p.addCurve(to: CGPoint(x: 305, y: 172), control1: CGPoint(x: 241, y: 182), control2: CGPoint(x: 263, y: 169))
  }
  static let leftOutlet = Path { p in
    p.move(to: CGPoint(x: 94, y: 223))
    p.addCurve(to: CGPoint(x: 146, y: 201), control1: CGPoint(x: 113, y: 222), control2: CGPoint(x: 126, y: 208))
    p.addQuadCurve(to: CGPoint(x: 145, y: 211), control: CGPoint(x: 147, y: 205))
  }
  static let rightOutlet = Path { p in
    p.move(to: CGPoint(x: 266, y: 223))
    p.addCurve(to: CGPoint(x: 214, y: 201), control1: CGPoint(x: 247, y: 222), control2: CGPoint(x: 234, y: 208))
    p.addQuadCurve(to: CGPoint(x: 215, y: 211), control: CGPoint(x: 213, y: 205))
  }
  static let stroma = Path { p in
    p.move(to: CGPoint(x: 59, y: 90))
    p.addCurve(to: CGPoint(x: 153, y: 103), control1: CGPoint(x: 84, y: 71), control2: CGPoint(x: 118, y: 77))
    p.addCurve(to: CGPoint(x: 268, y: 146), control1: CGPoint(x: 198, y: 141), control2: CGPoint(x: 227, y: 142))
    p.addCurve(to: CGPoint(x: 324, y: 189), control1: CGPoint(x: 318, y: 149), control2: CGPoint(x: 331, y: 163))
    p.addCurve(to: CGPoint(x: 225, y: 213), control1: CGPoint(x: 319, y: 213), control2: CGPoint(x: 261, y: 208))
    p.addCurve(to: CGPoint(x: 112, y: 280), control1: CGPoint(x: 178, y: 219), control2: CGPoint(x: 157, y: 264))
    p.addCurve(to: CGPoint(x: 50, y: 247), control1: CGPoint(x: 74, y: 294), control2: CGPoint(x: 42, y: 276))
    p.addCurve(to: CGPoint(x: 60, y: 179), control1: CGPoint(x: 57, y: 218), control2: CGPoint(x: 51, y: 200))
    p.addCurve(to: CGPoint(x: 59, y: 90), control1: CGPoint(x: 67, y: 157), control2: CGPoint(x: 37, y: 111))
    p.closeSubpath()
  }
  static let upperTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 91, y: 113), commands: [
    .init(kind: .cubic, points: [.init(x: 143, y: 113), .init(x: 154, y: 141), .init(x: 175, y: 170)]),
    .init(kind: .quad, points: [.init(x: 184, y: 182), .init(x: 212, y: 182)]),
  ]))
  static let middleTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 106, y: 182), commands: [
    .init(kind: .cubic, points: [.init(x: 144, y: 182), .init(x: 174, y: 181), .init(x: 212, y: 182)]),
  ]))
  static let lowerTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 91, y: 251), commands: [
    .init(kind: .cubic, points: [.init(x: 143, y: 251), .init(x: 154, y: 223), .init(x: 175, y: 195)]),
    .init(kind: .quad, points: [.init(x: 184, y: 183), .init(x: 212, y: 182)]),
  ]))
  static let mainTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 212, y: 182), commands: [
    .init(kind: .cubic, points: [.init(x: 241, y: 182), .init(x: 263, y: 169), .init(x: 305, y: 172)]),
  ]))
  static let leftOutletTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 94, y: 223), commands: [
    .init(kind: .cubic, points: [.init(x: 113, y: 222), .init(x: 126, y: 208), .init(x: 146, y: 201)]),
    .init(kind: .quad, points: [.init(x: 147, y: 205), .init(x: 145, y: 211)]),
  ]))
  static let rightOutletTrack = GalaxySSIHealthAtlasRegionalTrack(.init(start: .init(x: 266, y: 223), commands: [
    .init(kind: .cubic, points: [.init(x: 247, y: 222), .init(x: 234, y: 208), .init(x: 214, y: 201)]),
    .init(kind: .quad, points: [.init(x: 213, y: 205), .init(x: 215, y: 211)]),
  ]))
}
