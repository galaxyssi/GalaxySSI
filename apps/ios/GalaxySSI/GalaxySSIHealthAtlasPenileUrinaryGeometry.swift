import SwiftUI

// Original Android #4385 section outlines and continuous urethral centerline.
enum GalaxySSIHealthAtlasPenileUrinaryGeometry {
  static let section = Path { p in
    p.move(to: CGPoint(x: 180, y: 109))
    p.addCurve(to: CGPoint(x: 67, y: 128), control1: CGPoint(x: 143, y: 87), control2: CGPoint(x: 85, y: 93))
    p.addCurve(to: CGPoint(x: 117, y: 223), control1: CGPoint(x: 46, y: 170), control2: CGPoint(x: 66, y: 211))
    p.addCurve(to: CGPoint(x: 180, y: 276), control1: CGPoint(x: 124, y: 254), control2: CGPoint(x: 148, y: 275))
    p.addCurve(to: CGPoint(x: 243, y: 223), control1: CGPoint(x: 212, y: 275), control2: CGPoint(x: 236, y: 254))
    p.addCurve(to: CGPoint(x: 293, y: 128), control1: CGPoint(x: 294, y: 211), control2: CGPoint(x: 314, y: 170))
    p.addCurve(to: CGPoint(x: 180, y: 109), control1: CGPoint(x: 275, y: 93), control2: CGPoint(x: 217, y: 87))
    p.closeSubpath()
  }
  static let cavernosa = Path { p in
    p.move(to: CGPoint(x: 169, y: 128))
    p.addCurve(to: CGPoint(x: 88, y: 123), control1: CGPoint(x: 157, y: 107), control2: CGPoint(x: 110, y: 105))
    p.addCurve(to: CGPoint(x: 85, y: 192), control1: CGPoint(x: 68, y: 141), control2: CGPoint(x: 67, y: 175))
    p.addCurve(to: CGPoint(x: 170, y: 195), control1: CGPoint(x: 103, y: 211), control2: CGPoint(x: 156, y: 215))
    p.addCurve(to: CGPoint(x: 169, y: 128), control1: CGPoint(x: 177, y: 183), control2: CGPoint(x: 178, y: 141))
    p.closeSubpath()
  }
  static let weave = Path { p in
    p.move(to: CGPoint(x: 92, y: 151))
    p.addCurve(to: CGPoint(x: 157, y: 142), control1: CGPoint(x: 106, y: 129), control2: CGPoint(x: 143, y: 124))
    p.move(to: CGPoint(x: 86, y: 166))
    p.addCurve(to: CGPoint(x: 163, y: 156), control1: CGPoint(x: 103, y: 155), control2: CGPoint(x: 129, y: 145))
    p.move(to: CGPoint(x: 94, y: 179))
    p.addCurve(to: CGPoint(x: 161, y: 173), control1: CGPoint(x: 111, y: 166), control2: CGPoint(x: 143, y: 163))
    p.move(to: CGPoint(x: 110, y: 191))
    p.addQuadCurve(to: CGPoint(x: 153, y: 187), control: CGPoint(x: 136, y: 182))
  }
  static let spongiosum = Path { p in
    p.move(to: CGPoint(x: 180, y: 197))
    p.addCurve(to: CGPoint(x: 134, y: 227), control1: CGPoint(x: 158, y: 195), control2: CGPoint(x: 138, y: 207))
    p.addCurve(to: CGPoint(x: 180, y: 266), control1: CGPoint(x: 127, y: 247), control2: CGPoint(x: 151, y: 266))
    p.addCurve(to: CGPoint(x: 226, y: 227), control1: CGPoint(x: 209, y: 266), control2: CGPoint(x: 233, y: 247))
    p.addCurve(to: CGPoint(x: 180, y: 197), control1: CGPoint(x: 222, y: 207), control2: CGPoint(x: 202, y: 195))
    p.closeSubpath()
  }
  static let bladder = Path { p in
    p.move(to: CGPoint(x: 84, y: 179))
    p.addCurve(to: CGPoint(x: 44, y: 145), control1: CGPoint(x: 75, y: 167), control2: CGPoint(x: 50, y: 166))
    p.addCurve(to: CGPoint(x: 90, y: 78), control1: CGPoint(x: 30, y: 104), control2: CGPoint(x: 54, y: 78))
    p.addCurve(to: CGPoint(x: 132, y: 145), control1: CGPoint(x: 125, y: 78), control2: CGPoint(x: 145, y: 106))
    p.addCurve(to: CGPoint(x: 94, y: 179), control1: CGPoint(x: 124, y: 166), control2: CGPoint(x: 99, y: 163))
    p.closeSubpath()
  }
  static let bladderInterior = Path { p in
    p.move(to: CGPoint(x: 89, y: 168))
    p.addCurve(to: CGPoint(x: 53, y: 139), control1: CGPoint(x: 76, y: 155), control2: CGPoint(x: 60, y: 157))
    p.addCurve(to: CGPoint(x: 90, y: 88), control1: CGPoint(x: 44, y: 109), control2: CGPoint(x: 60, y: 88))
    p.addCurve(to: CGPoint(x: 123, y: 139), control1: CGPoint(x: 119, y: 88), control2: CGPoint(x: 133, y: 110))
    p.addCurve(to: CGPoint(x: 89, y: 168), control1: CGPoint(x: 115, y: 155), control2: CGPoint(x: 99, y: 154))
    p.closeSubpath()
  }
  static let shaftSection = Path { p in
    p.move(to: CGPoint(x: 132, y: 207))
    p.addCurve(to: CGPoint(x: 293, y: 187), control1: CGPoint(x: 157, y: 182), control2: CGPoint(x: 225, y: 179))
    p.addCurve(to: CGPoint(x: 309, y: 207), control1: CGPoint(x: 308, y: 189), control2: CGPoint(x: 316, y: 198))
    p.addCurve(to: CGPoint(x: 263, y: 215), control1: CGPoint(x: 304, y: 216), control2: CGPoint(x: 284, y: 217))
    p.addCurve(to: CGPoint(x: 142, y: 231), control1: CGPoint(x: 207, y: 210), control2: CGPoint(x: 161, y: 224))
    p.addQuadCurve(to: CGPoint(x: 132, y: 207), control: CGPoint(x: 125, y: 228))
    p.closeSubpath()
  }
  static let spongySection = Path { p in
    p.move(to: CGPoint(x: 105, y: 213))
    p.addCurve(to: CGPoint(x: 160, y: 222), control1: CGPoint(x: 125, y: 202), control2: CGPoint(x: 144, y: 210))
    p.addCurve(to: CGPoint(x: 264, y: 222), control1: CGPoint(x: 185, y: 236), control2: CGPoint(x: 226, y: 223))
    p.addCurve(to: CGPoint(x: 309, y: 209), control1: CGPoint(x: 287, y: 221), control2: CGPoint(x: 296, y: 207))
    p.addCurve(to: CGPoint(x: 330, y: 228), control1: CGPoint(x: 324, y: 210), control2: CGPoint(x: 332, y: 219))
    p.addCurve(to: CGPoint(x: 279, y: 248), control1: CGPoint(x: 328, y: 244), control2: CGPoint(x: 302, y: 253))
    p.addCurve(to: CGPoint(x: 158, y: 254), control1: CGPoint(x: 248, y: 244), control2: CGPoint(x: 198, y: 260))
    p.addCurve(to: CGPoint(x: 100, y: 238), control1: CGPoint(x: 143, y: 252), control2: CGPoint(x: 110, y: 253))
    p.addQuadCurve(to: CGPoint(x: 105, y: 213), control: CGPoint(x: 94, y: 222))
    p.closeSubpath()
  }
  static let proximalRoute = Path { p in
    p.move(to: CGPoint(x: 89, y: 120))
    p.addCurve(to: CGPoint(x: 90, y: 197), control1: CGPoint(x: 89, y: 147), control2: CGPoint(x: 88, y: 179))
    p.addCurve(to: CGPoint(x: 115, y: 225), control1: CGPoint(x: 91, y: 210), control2: CGPoint(x: 103, y: 222))
  }
  static let route: Path = {
    var p = proximalRoute
    p.addCurve(to: CGPoint(x: 168, y: 239), control1: CGPoint(x: 136, y: 225), control2: CGPoint(x: 146, y: 235))
    p.addCurve(to: CGPoint(x: 310, y: 229), control1: CGPoint(x: 208, y: 248), control2: CGPoint(x: 271, y: 224))
    p.addQuadCurve(to: CGPoint(x: 330, y: 228), control: CGPoint(x: 319, y: 230))
    return p
  }()
  struct Track {
    let path: Path
    let length: Double
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
      length = GalaxySSIHealthAtlasCurveLength.route(route, width: 360, height: 360) ?? 0
    }
  }
  static let proximalTrack = Track(.init(start: .init(x: 89, y: 120), commands: [
    .init(kind: .cubic, points: [.init(x: 89, y: 147), .init(x: 88, y: 179), .init(x: 90, y: 197)]),
    .init(kind: .cubic, points: [.init(x: 91, y: 210), .init(x: 103, y: 222), .init(x: 115, y: 225)]),
  ]))
  static let flow = Track(.init(start: .init(x: 89, y: 120), commands: [
    .init(kind: .cubic, points: [.init(x: 89, y: 147), .init(x: 88, y: 179), .init(x: 90, y: 197)]),
    .init(kind: .cubic, points: [.init(x: 91, y: 210), .init(x: 103, y: 222), .init(x: 115, y: 225)]),
    .init(kind: .cubic, points: [.init(x: 136, y: 225), .init(x: 146, y: 235), .init(x: 168, y: 239)]),
    .init(kind: .cubic, points: [.init(x: 208, y: 248), .init(x: 271, y: 224), .init(x: 310, y: 229)]),
    .init(kind: .quad, points: [.init(x: 319, y: 230), .init(x: 330, y: 228)]),
  ]))
}
