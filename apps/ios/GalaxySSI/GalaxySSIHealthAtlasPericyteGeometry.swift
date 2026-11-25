import SwiftUI

// Generated from pinned Android #4388 constant curve declarations.
enum GalaxySSIHealthAtlasPericyteGeometry {
  static let sleeve = Path { p in
    p.addPath(Path(roundedRect: CGRect(x: 27, y: 127, width: 306, height: 120), cornerRadius: 16))
  }
  static let window = Path { p in
    p.addPath(Path(roundedRect: CGRect(x: 28, y: 158, width: 304, height: 58), cornerRadius: 9))
  }
  static let profile = Path { p in
    p.move(to: .init(x: 44, y: 130))
    p.addCurve(to: .init(x: 125, y: 117), control1: .init(x: 83, y: 125), control2: .init(x: 106, y: 127))
    p.addCurve(to: .init(x: 159, y: 94), control1: .init(x: 135, y: 111), control2: .init(x: 135, y: 95))
    p.addCurve(to: .init(x: 204, y: 118), control1: .init(x: 181, y: 92), control2: .init(x: 184, y: 109))
    p.addCurve(to: .init(x: 308, y: 133), control1: .init(x: 227, y: 126), control2: .init(x: 271, y: 122))
    p.addCurve(to: .init(x: 228, y: 136), control1: .init(x: 274, y: 130), control2: .init(x: 249, y: 131))
    p.addCurve(to: .init(x: 204, y: 154), control1: .init(x: 214, y: 140), control2: .init(x: 208, y: 149))
    p.addCurve(to: .init(x: 208, y: 135), control1: .init(x: 203, y: 145), control2: .init(x: 206, y: 140))
    p.addCurve(to: .init(x: 169, y: 127), control1: .init(x: 192, y: 132), control2: .init(x: 183, y: 124))
    p.addCurve(to: .init(x: 127, y: 134), control1: .init(x: 152, y: 132), control2: .init(x: 140, y: 129))
    p.addCurve(to: .init(x: 44, y: 130), control1: .init(x: 104, y: 136), control2: .init(x: 81, y: 129))
    p.closeSubpath()
  }
  static let wrap = Path { p in
    p.move(to: .init(x: 219, y: 91))
    p.addCurve(to: .init(x: 264, y: 166), control1: .init(x: 247, y: 107), control2: .init(x: 263, y: 135))
    p.addCurve(to: .init(x: 238, y: 234), control1: .init(x: 266, y: 196), control2: .init(x: 252, y: 220))
    p.addCurve(to: .init(x: 205, y: 246), control1: .init(x: 226, y: 243), control2: .init(x: 214, y: 246))
    p.addCurve(to: .init(x: 251, y: 169), control1: .init(x: 241, y: 230), control2: .init(x: 253, y: 197))
    p.addCurve(to: .init(x: 213, y: 111), control1: .init(x: 250, y: 141), control2: .init(x: 232, y: 123))
    p.addCurve(to: .init(x: 145, y: 99), control1: .init(x: 195, y: 101), control2: .init(x: 173, y: 91))
    p.addCurve(to: .init(x: 219, y: 91), control1: .init(x: 164, y: 83), control2: .init(x: 199, y: 80))
    p.closeSubpath()
  }
  static let wrapTrace = Path { p in
    p.move(to: .init(x: 214, y: 99))
    p.addCurve(to: .init(x: 257, y: 170), control1: .init(x: 241, y: 117), control2: .init(x: 257, y: 141))
    p.addCurve(to: .init(x: 212, y: 244), control1: .init(x: 259, y: 201), control2: .init(x: 243, y: 229))
  }
  static let wrapTraceRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 214, y: 99), commands: [
    .init(kind: .cubic, points: [.init(x: 241, y: 117), .init(x: 257, y: 141), .init(x: 257, y: 170)]),
    .init(kind: .cubic, points: [.init(x: 259, y: 201), .init(x: 243, y: 229), .init(x: 212, y: 244)])])
  static let matrix = Path { p in
    p.move(to: .init(x: 29, y: 155))
    p.addCurve(to: .init(x: 127, y: 128), control1: .init(x: 83, y: 156), control2: .init(x: 104, y: 156))
    p.addCurve(to: .init(x: 218, y: 116), control1: .init(x: 150, y: 96), control2: .init(x: 183, y: 96))
    p.addCurve(to: .init(x: 331, y: 148), control1: .init(x: 244, y: 131), control2: .init(x: 269, y: 144))
    p.addLine(to: .init(x: 331, y: 193))
    p.addLine(to: .init(x: 29, y: 194))
    p.closeSubpath()
  }
  static let liningDetail = Path { p in
    p.move(to: .init(x: 29, y: 189))
    p.addCurve(to: .init(x: 174, y: 186), control1: .init(x: 80, y: 175), control2: .init(x: 149, y: 174))
    p.addQuadCurve(to: .init(x: 207, y: 185), control: .init(x: 189, y: 205))
    p.addCurve(to: .init(x: 331, y: 189), control1: .init(x: 248, y: 171), control2: .init(x: 281, y: 184))
    p.addLine(to: .init(x: 331, y: 238))
    p.addCurve(to: .init(x: 29, y: 233), control1: .init(x: 232, y: 228), control2: .init(x: 109, y: 244))
    p.closeSubpath()
  }
  static let muralDetail = Path { p in
    p.move(to: .init(x: 48, y: 161))
    p.addCurve(to: .init(x: 135, y: 126), control1: .init(x: 98, y: 161), control2: .init(x: 115, y: 149))
    p.addCurve(to: .init(x: 211, y: 125), control1: .init(x: 150, y: 110), control2: .init(x: 185, y: 110))
    p.addCurve(to: .init(x: 304, y: 155), control1: .init(x: 244, y: 143), control2: .init(x: 272, y: 150))
    p.addCurve(to: .init(x: 207, y: 169), control1: .init(x: 257, y: 164), control2: .init(x: 227, y: 150))
    p.addQuadCurve(to: .init(x: 200, y: 191), control: .init(x: 198, y: 177))
    p.addQuadCurve(to: .init(x: 182, y: 192), control: .init(x: 190, y: 203))
    p.addQuadCurve(to: .init(x: 175, y: 168), control: .init(x: 185, y: 175))
    p.addCurve(to: .init(x: 48, y: 161), control1: .init(x: 144, y: 149), control2: .init(x: 108, y: 177))
    p.closeSubpath()
  }
}
