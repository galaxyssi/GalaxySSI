import SwiftUI

// Generated from pinned Android #4388 constant curve declarations.
enum GalaxySSIHealthAtlasAdrenalCortexGeometry {
  static let section = Path { p in
    p.move(to: .init(x: 52, y: 232))
    p.addCurve(to: .init(x: 141, y: 115), control1: .init(x: 59, y: 201), control2: .init(x: 103, y: 159))
    p.addCurve(to: .init(x: 195, y: 98), control1: .init(x: 161, y: 91), control2: .init(x: 180, y: 84))
    p.addCurve(to: .init(x: 306, y: 239), control1: .init(x: 229, y: 126), control2: .init(x: 266, y: 214))
    p.addCurve(to: .init(x: 268, y: 270), control1: .init(x: 333, y: 262), control2: .init(x: 307, y: 286))
    p.addCurve(to: .init(x: 175, y: 269), control1: .init(x: 238, y: 258), control2: .init(x: 210, y: 255))
    p.addCurve(to: .init(x: 52, y: 232), control1: .init(x: 121, y: 289), control2: .init(x: 38, y: 277))
    p.closeSubpath()
  }
  static let sectionRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 52, y: 232), commands: [
    .init(kind: .cubic, points: [.init(x: 59, y: 201), .init(x: 103, y: 159), .init(x: 141, y: 115)]),
    .init(kind: .cubic, points: [.init(x: 161, y: 91), .init(x: 180, y: 84), .init(x: 195, y: 98)]),
    .init(kind: .cubic, points: [.init(x: 229, y: 126), .init(x: 266, y: 214), .init(x: 306, y: 239)]),
    .init(kind: .cubic, points: [.init(x: 333, y: 262), .init(x: 307, y: 286), .init(x: 268, y: 270)]),
    .init(kind: .cubic, points: [.init(x: 238, y: 258), .init(x: 210, y: 255), .init(x: 175, y: 269)]),
    .init(kind: .cubic, points: [.init(x: 121, y: 289), .init(x: 38, y: 277), .init(x: 52, y: 232)])])
  static let sinusoid = Path { p in
    p.move(to: .init(x: 251, y: 82))
    p.addCurve(to: .init(x: 250, y: 172), control1: .init(x: 284, y: 111), control2: .init(x: 219, y: 137))
    p.addCurve(to: .init(x: 252, y: 260), control1: .init(x: 284, y: 202), control2: .init(x: 228, y: 229))
    p.addQuadCurve(to: .init(x: 305, y: 287), control: .init(x: 267, y: 278))
  }
  static let sinusoidRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 251, y: 82), commands: [
    .init(kind: .cubic, points: [.init(x: 284, y: 111), .init(x: 219, y: 137), .init(x: 250, y: 172)]),
    .init(kind: .cubic, points: [.init(x: 284, y: 202), .init(x: 228, y: 229), .init(x: 252, y: 260)]),
    .init(kind: .quad, points: [.init(x: 267, y: 278), .init(x: 305, y: 287)])])
}
