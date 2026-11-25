import SwiftUI

// Android #4385 source coordinates, including the open superior tunica attachment.
enum GalaxySSIHealthAtlasScrotalHeatGeometry {
  static let sac = Path { p in
    p.move(to: CGPoint(x: 80, y: 113))
    p.addCurve(to: CGPoint(x: 44, y: 205), control1: CGPoint(x: 70, y: 134), control2: CGPoint(x: 45, y: 155))
    p.addCurve(to: CGPoint(x: 131, y: 280), control1: CGPoint(x: 39, y: 260), control2: CGPoint(x: 87, y: 290))
    p.addQuadCurve(to: CGPoint(x: 176, y: 275), control: CGPoint(x: 155, y: 276))
    p.addCurve(to: CGPoint(x: 308, y: 254), control1: CGPoint(x: 219, y: 300), control2: CGPoint(x: 283, y: 301))
    p.addCurve(to: CGPoint(x: 280, y: 120), control1: CGPoint(x: 336, y: 206), control2: CGPoint(x: 307, y: 154))
    p.addQuadCurve(to: CGPoint(x: 231, y: 120), control: CGPoint(x: 257, y: 112))
    p.addQuadCurve(to: CGPoint(x: 129, y: 113), control: CGPoint(x: 178, y: 130))
    p.addQuadCurve(to: CGPoint(x: 80, y: 113), control: CGPoint(x: 103, y: 104))
    p.closeSubpath()
  }
  static let dartos = Path { p in
    p.move(to: CGPoint(x: 82, y: 126))
    p.addCurve(to: CGPoint(x: 55, y: 220), control1: CGPoint(x: 69, y: 151), control2: CGPoint(x: 50, y: 182))
    p.addCurve(to: CGPoint(x: 131, y: 270), control1: CGPoint(x: 60, y: 256), control2: CGPoint(x: 94, y: 276))
    p.addQuadCurve(to: CGPoint(x: 178, y: 264), control: CGPoint(x: 157, y: 265))
    p.addCurve(to: CGPoint(x: 298, y: 250), control1: CGPoint(x: 219, y: 287), control2: CGPoint(x: 274, y: 289))
    p.addCurve(to: CGPoint(x: 279, y: 134), control1: CGPoint(x: 324, y: 207), control2: CGPoint(x: 297, y: 160))
  }
  static let septum = Path { p in
    p.move(to: CGPoint(x: 173, y: 126))
    p.addCurve(to: CGPoint(x: 178, y: 264), control1: CGPoint(x: 165, y: 171), control2: CGPoint(x: 187, y: 218))
  }
  static let cord = Path { p in
    p.move(to: CGPoint(x: 77, y: 69))
    p.addCurve(to: CGPoint(x: 93, y: 164), control1: CGPoint(x: 76, y: 108), control2: CGPoint(x: 83, y: 144))
    p.addLine(to: CGPoint(x: 120, y: 156))
    p.addCurve(to: CGPoint(x: 112, y: 69), control1: CGPoint(x: 109, y: 134), control2: CGPoint(x: 108, y: 98))
    p.closeSubpath()
  }
  static let cordCore = Path { p in
    p.move(to: CGPoint(x: 86, y: 74))
    p.addCurve(to: CGPoint(x: 100, y: 153), control1: CGPoint(x: 84, y: 102), control2: CGPoint(x: 89, y: 135))
    p.move(to: CGPoint(x: 101, y: 74))
    p.addCurve(to: CGPoint(x: 110, y: 148), control1: CGPoint(x: 96, y: 102), control2: CGPoint(x: 101, y: 128))
  }
  static let tunica = Path { p in
    p.move(to: CGPoint(x: 99, y: 146))
    p.addCurve(to: CGPoint(x: 70, y: 218), control1: CGPoint(x: 73, y: 151), control2: CGPoint(x: 66, y: 187))
    p.addCurve(to: CGPoint(x: 116, y: 259), control1: CGPoint(x: 73, y: 245), control2: CGPoint(x: 93, y: 264))
    p.addCurve(to: CGPoint(x: 149, y: 189), control1: CGPoint(x: 144, y: 253), control2: CGPoint(x: 157, y: 217))
    p.addCurve(to: CGPoint(x: 120, y: 148), control1: CGPoint(x: 145, y: 169), control2: CGPoint(x: 135, y: 153))
  }
  static let testis = Path { p in
    p.move(to: CGPoint(x: 98, y: 155))
    p.addCurve(to: CGPoint(x: 79, y: 217), control1: CGPoint(x: 78, y: 160), control2: CGPoint(x: 74, y: 191))
    p.addCurve(to: CGPoint(x: 114, y: 250), control1: CGPoint(x: 82, y: 237), control2: CGPoint(x: 95, y: 255))
    p.addCurve(to: CGPoint(x: 141, y: 191), control1: CGPoint(x: 136, y: 245), control2: CGPoint(x: 148, y: 215))
    p.addCurve(to: CGPoint(x: 98, y: 155), control1: CGPoint(x: 136, y: 171), control2: CGPoint(x: 119, y: 150))
    p.closeSubpath()
  }
  static let testisContour = Path { p in
    p.move(to: CGPoint(x: 100, y: 166))
    p.addCurve(to: CGPoint(x: 88, y: 202), control1: CGPoint(x: 90, y: 169), control2: CGPoint(x: 86, y: 188))
    p.move(to: CGPoint(x: 124, y: 223))
    p.addQuadCurve(to: CGPoint(x: 106, y: 239), control: CGPoint(x: 119, y: 237))
  }
  static let artery = Path { p in
    p.move(to: CGPoint(x: 112, y: 74))
    p.addCurve(to: CGPoint(x: 112, y: 152), control1: CGPoint(x: 84, y: 108), control2: CGPoint(x: 122, y: 124))
    p.addCurve(to: CGPoint(x: 113, y: 232), control1: CGPoint(x: 93, y: 185), control2: CGPoint(x: 120, y: 206))
    p.addQuadCurve(to: CGPoint(x: 113, y: 286), control: CGPoint(x: 107, y: 262))
  }
  static let vein = Path { p in
    p.move(to: CGPoint(x: 243, y: 286))
    p.addCurve(to: CGPoint(x: 242, y: 211), control1: CGPoint(x: 216, y: 261), control2: CGPoint(x: 258, y: 239))
    p.addCurve(to: CGPoint(x: 243, y: 135), control1: CGPoint(x: 221, y: 185), control2: CGPoint(x: 255, y: 163))
    p.addCurve(to: CGPoint(x: 243, y: 74), control1: CGPoint(x: 228, y: 110), control2: CGPoint(x: 254, y: 91))
  }
  static let veinBranches = Path { p in
    p.move(to: CGPoint(x: 241, y: 278))
    p.addCurve(to: CGPoint(x: 243, y: 211), control1: CGPoint(x: 272, y: 250), control2: CGPoint(x: 272, y: 227))
    p.addCurve(to: CGPoint(x: 243, y: 135), control1: CGPoint(x: 284, y: 190), control2: CGPoint(x: 223, y: 160))
    p.addCurve(to: CGPoint(x: 243, y: 79), control1: CGPoint(x: 274, y: 114), control2: CGPoint(x: 271, y: 92))
    p.move(to: CGPoint(x: 240, y: 269))
    p.addCurve(to: CGPoint(x: 236, y: 199), control1: CGPoint(x: 203, y: 238), control2: CGPoint(x: 210, y: 221))
    p.addCurve(to: CGPoint(x: 238, y: 126), control1: CGPoint(x: 202, y: 169), control2: CGPoint(x: 209, y: 143))
    p.addCurve(to: CGPoint(x: 242, y: 81), control1: CGPoint(x: 207, y: 108), control2: CGPoint(x: 219, y: 95))
  }
  struct Track {
    let path: Path
    let length: Double
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
      length = GalaxySSIHealthAtlasCurveLength.route(route, width: 360, height: 360) ?? 0
    }
  }
  static let arteryTrack = Track(.init(start: .init(x: 112, y: 74), commands: [
    .init(kind: .cubic, points: [.init(x: 84, y: 108), .init(x: 122, y: 124), .init(x: 112, y: 152)]),
    .init(kind: .cubic, points: [.init(x: 93, y: 185), .init(x: 120, y: 206), .init(x: 113, y: 232)]),
    .init(kind: .quad, points: [.init(x: 107, y: 262), .init(x: 113, y: 286)]),
  ]))
  static let veinTrack = Track(.init(start: .init(x: 243, y: 286), commands: [
    .init(kind: .cubic, points: [.init(x: 216, y: 261), .init(x: 258, y: 239), .init(x: 242, y: 211)]),
    .init(kind: .cubic, points: [.init(x: 221, y: 185), .init(x: 255, y: 163), .init(x: 243, y: 135)]),
    .init(kind: .cubic, points: [.init(x: 228, y: 110), .init(x: 254, y: 91), .init(x: 243, y: 74)]),
  ]))
}
