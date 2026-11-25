import SwiftUI

enum GalaxySSIHealthAtlasAdrenalGeometry {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static let guide: UInt32 = 0x5A6C72, rim: UInt32 = 0x96623D, medullaInk: UInt32 = 0x8B5969, cellInk: UInt32 = 0x986568
  static let cargo: UInt32 = 0x6D4A80, vesselInk: UInt32 = 0xA36571, nerveInk: UInt32 = 0x8C682D
  static let kidney = Path { p in
    p.move(to: CGPoint(x: 104, y: 139))
    p.addCurve(to: CGPoint(x: 129, y: 174), control1: CGPoint(x: 124, y: 140), control2: CGPoint(x: 134, y: 158))
    p.addCurve(to: CGPoint(x: 108, y: 204), control1: CGPoint(x: 125, y: 189), control2: CGPoint(x: 109, y: 190))
    p.addCurve(to: CGPoint(x: 122, y: 238), control1: CGPoint(x: 106, y: 216), control2: CGPoint(x: 125, y: 220))
    p.addCurve(to: CGPoint(x: 66, y: 268), control1: CGPoint(x: 118, y: 263), control2: CGPoint(x: 91, y: 279))
    p.addCurve(to: CGPoint(x: 42, y: 187), control1: CGPoint(x: 35, y: 255), control2: CGPoint(x: 34, y: 221))
    p.addCurve(to: CGPoint(x: 104, y: 139), control1: CGPoint(x: 49, y: 155), control2: CGPoint(x: 75, y: 133))
    p.closeSubpath()
  }
  static let gland = Path { p in
    p.move(to: CGPoint(x: 60, y: 151))
    p.addCurve(to: CGPoint(x: 74, y: 125), control1: CGPoint(x: 56, y: 145), control2: CGPoint(x: 66, y: 135))
    p.addCurve(to: CGPoint(x: 98, y: 101), control1: CGPoint(x: 84, y: 114), control2: CGPoint(x: 89, y: 95))
    p.addCurve(to: CGPoint(x: 119, y: 133), control1: CGPoint(x: 107, y: 108), control2: CGPoint(x: 110, y: 121))
    p.addCurve(to: CGPoint(x: 109, y: 144), control1: CGPoint(x: 122, y: 140), control2: CGPoint(x: 117, y: 145))
    p.addCurve(to: CGPoint(x: 60, y: 151), control1: CGPoint(x: 91, y: 138), control2: CGPoint(x: 73, y: 144))
    p.closeSubpath()
  }
  static let cortex = Path { p in
    p.move(to: CGPoint(x: 227, y: 104))
    p.addCurve(to: CGPoint(x: 280, y: 125), control1: CGPoint(x: 241, y: 88), control2: CGPoint(x: 263, y: 101))
    p.addCurve(to: CGPoint(x: 317, y: 198), control1: CGPoint(x: 294, y: 145), control2: CGPoint(x: 302, y: 173))
    p.addCurve(to: CGPoint(x: 285, y: 239), control1: CGPoint(x: 334, y: 226), control2: CGPoint(x: 312, y: 251))
    p.addCurve(to: CGPoint(x: 198, y: 244), control1: CGPoint(x: 255, y: 225), control2: CGPoint(x: 229, y: 227))
    p.addCurve(to: CGPoint(x: 166, y: 211), control1: CGPoint(x: 169, y: 259), control2: CGPoint(x: 155, y: 235))
    p.addCurve(to: CGPoint(x: 227, y: 104), control1: CGPoint(x: 181, y: 179), control2: CGPoint(x: 198, y: 136))
    p.closeSubpath()
  }
  static let medulla = Path { p in
    p.move(to: CGPoint(x: 226, y: 151))
    p.addCurve(to: CGPoint(x: 267, y: 152), control1: CGPoint(x: 235, y: 130), control2: CGPoint(x: 255, y: 134))
    p.addCurve(to: CGPoint(x: 292, y: 203), control1: CGPoint(x: 278, y: 169), control2: CGPoint(x: 283, y: 188))
    p.addCurve(to: CGPoint(x: 276, y: 216), control1: CGPoint(x: 299, y: 216), control2: CGPoint(x: 290, y: 222))
    p.addCurve(to: CGPoint(x: 207, y: 222), control1: CGPoint(x: 255, y: 207), control2: CGPoint(x: 233, y: 208))
    p.addCurve(to: CGPoint(x: 194, y: 210), control1: CGPoint(x: 197, y: 225), control2: CGPoint(x: 188, y: 222))
    p.addCurve(to: CGPoint(x: 226, y: 151), control1: CGPoint(x: 201, y: 189), control2: CGPoint(x: 214, y: 173))
    p.closeSubpath()
  }
  static let receivingCell = Path { p in
    p.move(to: CGPoint(x: 105, y: 205))
    p.addCurve(to: CGPoint(x: 159, y: 134), control1: CGPoint(x: 101, y: 166), control2: CGPoint(x: 124, y: 139))
    p.addCurve(to: CGPoint(x: 266, y: 147), control1: CGPoint(x: 198, y: 128), control2: CGPoint(x: 230, y: 128))
    p.addCurve(to: CGPoint(x: 301, y: 234), control1: CGPoint(x: 304, y: 166), control2: CGPoint(x: 323, y: 206))
    p.addCurve(to: CGPoint(x: 166, y: 259), control1: CGPoint(x: 274, y: 272), control2: CGPoint(x: 216, y: 273))
    p.addCurve(to: CGPoint(x: 105, y: 205), control1: CGPoint(x: 134, y: 249), control2: CGPoint(x: 111, y: 237))
    p.closeSubpath()
  }
  static let cortexRoute = Route(start: .init(x: 227, y: 104), commands: [
    .init(kind: .cubic, points: [.init(x: 241, y: 88), .init(x: 263, y: 101), .init(x: 280, y: 125)]),
    .init(kind: .cubic, points: [.init(x: 294, y: 145), .init(x: 302, y: 173), .init(x: 317, y: 198)]),
    .init(kind: .cubic, points: [.init(x: 334, y: 226), .init(x: 312, y: 251), .init(x: 285, y: 239)]),
    .init(kind: .cubic, points: [.init(x: 255, y: 225), .init(x: 229, y: 227), .init(x: 198, y: 244)]),
    .init(kind: .cubic, points: [.init(x: 169, y: 259), .init(x: 155, y: 235), .init(x: 166, y: 211)]),
    .init(kind: .cubic, points: [.init(x: 181, y: 179), .init(x: 198, y: 136), .init(x: 227, y: 104)]),
  ])
  static let medullaRoute = Route(start: .init(x: 226, y: 151), commands: [
    .init(kind: .cubic, points: [.init(x: 235, y: 130), .init(x: 255, y: 134), .init(x: 267, y: 152)]),
    .init(kind: .cubic, points: [.init(x: 278, y: 169), .init(x: 283, y: 188), .init(x: 292, y: 203)]),
    .init(kind: .cubic, points: [.init(x: 299, y: 216), .init(x: 290, y: 222), .init(x: 276, y: 216)]),
    .init(kind: .cubic, points: [.init(x: 255, y: 207), .init(x: 233, y: 208), .init(x: 207, y: 222)]),
    .init(kind: .cubic, points: [.init(x: 197, y: 225), .init(x: 188, y: 222), .init(x: 194, y: 210)]),
    .init(kind: .cubic, points: [.init(x: 201, y: 189), .init(x: 214, y: 173), .init(x: 226, y: 151)]),
  ])
  static let nerveRoute = Route(start: .init(x: 32, y: 118), commands: [
    .init(kind: .cubic, points: [.init(x: 71, y: 115), .init(x: 77, y: 84), .init(x: 110, y: 86)]),
    .init(kind: .cubic, points: [.init(x: 145, y: 84), .init(x: 159, y: 113), .init(x: 179, y: 113)]),
  ])
  static let nerveBranchRoute = Route(start: .init(x: 126, y: 89), commands: [
    .init(kind: .quad, points: [.init(x: 136, y: 100), .init(x: 142, y: 116)]),
  ])
  static let capillaryRoute = Route(start: .init(x: 28, y: 235), commands: [
    .init(kind: .cubic, points: [.init(x: 96, y: 223), .init(x: 138, y: 251), .init(x: 199, y: 238)]),
    .init(kind: .cubic, points: [.init(x: 248, y: 227), .init(x: 285, y: 202), .init(x: 332, y: 211)]),
  ])
  static let entryTrackRoute = Route(start: .init(x: 178, y: 177), commands: [
    .init(kind: .cubic, points: [.init(x: 183, y: 200), .init(x: 159, y: 218), .init(x: 175, y: 238)]),
    .init(kind: .cubic, points: [.init(x: 203, y: 252), .init(x: 275, y: 200), .init(x: 327, y: 211)]),
  ])
  static let restingVesselRoute = Route(start: .init(x: 29, y: 117), commands: [
    .init(kind: .cubic, points: [.init(x: 113, y: 88), .init(x: 220, y: 142), .init(x: 331, y: 115)]),
  ])
  static let recoveryCurveRoute = Route(start: .init(x: 61, y: 202), commands: [
    .init(kind: .cubic, points: [.init(x: 112, y: 211), .init(x: 126, y: 246), .init(x: 176, y: 263)]),
    .init(kind: .cubic, points: [.init(x: 219, y: 279), .init(x: 264, y: 279), .init(x: 313, y: 280)]),
  ])
  static func path(_ route: Route) -> Path { GalaxySSIHealthAtlasSectionLessonView.path(route,width: 360,height: 360) }
  static func secretingCell(pore: Double) -> Path {
    let center = 184.0, mouth = 2 + 4 * pore
    return Path { p in
      p.move(to: CGPoint(x: 54, y: 172))
      p.addCurve(to: CGPoint(x: 160, y: 94), control1: CGPoint(x: 50, y: 121), control2: CGPoint(x: 97, y: 94))
      p.addCurve(to: CGPoint(x: 303, y: 157), control1: CGPoint(x: 222, y: 92), control2: CGPoint(x: 282, y: 112))
      p.addCurve(to: CGPoint(x: 254, y: 220), control1: CGPoint(x: 321, y: 195), control2: CGPoint(x: 291, y: 220))
      if pore > 0 {
        p.addLine(to: CGPoint(x: center + mouth, y: 220))
        p.addCurve(to: CGPoint(x: center, y: 195), control1: CGPoint(x: 206, y: 204), control2: CGPoint(x: 198, y: 195))
        p.addCurve(to: CGPoint(x: center - mouth, y: 220), control1: CGPoint(x: 170, y: 195), control2: CGPoint(x: 162, y: 204))
      }
      p.addLine(to: CGPoint(x: 113, y: 220))
      p.addCurve(to: CGPoint(x: 54, y: 172), control1: CGPoint(x: 79, y: 220), control2: CGPoint(x: 59, y: 204)); p.closeSubpath()
    }
  }
}
