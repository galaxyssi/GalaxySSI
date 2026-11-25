import SwiftUI

// Generated from pinned Android #4388 constant curve declarations.
enum GalaxySSIHealthAtlasLactotrophGeometry {
  static let cell = Path { p in
    p.move(to: .init(x: 103, y: 191))
    p.addCurve(to: .init(x: 135, y: 125), control1: .init(x: 90, y: 165), control2: .init(x: 108, y: 137))
    p.addCurve(to: .init(x: 254, y: 160), control1: .init(x: 174, y: 105), control2: .init(x: 243, y: 127))
    p.addCurve(to: .init(x: 136, y: 218), control1: .init(x: 281, y: 214), control2: .init(x: 194, y: 237))
    p.addQuadCurve(to: .init(x: 103, y: 191), control: .init(x: 112, y: 213))
    p.closeSubpath()
  }
  static let mammaryBlood = Path { p in
    p.move(to: .init(x: 73, y: 149))
    p.addCurve(to: .init(x: 113, y: 220), control1: .init(x: 170, y: 95), control2: .init(x: 184, y: 209))
    p.addCurve(to: .init(x: 170, y: 254), control1: .init(x: 67, y: 229), control2: .init(x: 90, y: 274))
    p.addCurve(to: .init(x: 275, y: 220), control1: .init(x: 202, y: 245), control2: .init(x: 233, y: 229))
  }
  static let mammaryBloodRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 73, y: 149), commands: [
    .init(kind: .cubic, points: [.init(x: 170, y: 95), .init(x: 184, y: 209), .init(x: 113, y: 220)]),
    .init(kind: .cubic, points: [.init(x: 67, y: 229), .init(x: 90, y: 274), .init(x: 170, y: 254)]),
    .init(kind: .cubic, points: [.init(x: 202, y: 245), .init(x: 233, y: 229), .init(x: 275, y: 220)])])
  static let ducts = Path { p in
    p.move(to: .init(x: 263, y: 151))
    p.addQuadCurve(to: .init(x: 327, y: 128), control: .init(x: 297, y: 163))
    p.move(to: .init(x: 251, y: 116))
    p.addQuadCurve(to: .init(x: 279, y: 152), control: .init(x: 266, y: 143))
    p.move(to: .init(x: 255, y: 184))
    p.addQuadCurve(to: .init(x: 281, y: 153), control: .init(x: 268, y: 171))
    p.move(to: .init(x: 285, y: 106))
    p.addQuadCurve(to: .init(x: 296, y: 148), control: .init(x: 284, y: 132))
    p.move(to: .init(x: 302, y: 185))
    p.addQuadCurve(to: .init(x: 300, y: 145), control: .init(x: 297, y: 168))
  }
  static let lumenClip = Path { p in
    p.addEllipse(in: CGRect(x: 123, y: 124, width: 94, height: 94))
  }
  static let topPortal = Path { p in
    p.move(to: .init(x: 32, y: 89))
    p.addCurve(to: .init(x: 326, y: 87), control1: .init(x: 103, y: 68), control2: .init(x: 168, y: 102))
  }
  static let releaseBlood = Path { p in
    p.move(to: .init(x: 32, y: 265))
    p.addCurve(to: .init(x: 328, y: 254), control1: .init(x: 103, y: 245), control2: .init(x: 203, y: 276))
  }
  static let releaseBloodRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 32, y: 265), commands: [
    .init(kind: .cubic, points: [.init(x: 103, y: 245), .init(x: 203, y: 276), .init(x: 328, y: 254)])])
  static let nearAlveolus = Path { p in
    p.move(to: .init(x: 34, y: 267))
    p.addCurve(to: .init(x: 327, y: 249), control1: .init(x: 119, y: 244), control2: .init(x: 271, y: 282))
  }
  static let nearAlveolusRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 34, y: 267), commands: [
    .init(kind: .cubic, points: [.init(x: 119, y: 244), .init(x: 271, y: 282), .init(x: 327, y: 249)])])
}
