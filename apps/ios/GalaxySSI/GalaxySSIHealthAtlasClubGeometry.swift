import SwiftUI

enum GalaxySSIHealthAtlasClubGeometry {
  static let clubPositions: Set<Int> = [0, 3, 7, 10, 14]
  static let branch = Path { p in
    p.move(to: CGPoint(x: 103, y: 105))
    p.addCurve(to: CGPoint(x: 241, y: 58), control1: CGPoint(x: 158, y: 90), control2: CGPoint(x: 201, y: 64))
    p.addCurve(to: CGPoint(x: 331, y: 116), control1: CGPoint(x: 288, y: 49), control2: CGPoint(x: 325, y: 78))
    p.addCurve(to: CGPoint(x: 287, y: 196), control1: CGPoint(x: 337, y: 154), control2: CGPoint(x: 319, y: 180))
    p.addQuadCurve(to: CGPoint(x: 231, y: 243), control: CGPoint(x: 258, y: 212))
    p.addLine(to: CGPoint(x: 103, y: 105))
    p.closeSubpath()
  }
  static let branchFibers = Path { p in
    p.move(to: CGPoint(x: 175, y: 94))
    p.addCurve(to: CGPoint(x: 279, y: 68), control1: CGPoint(x: 226, y: 77), control2: CGPoint(x: 250, y: 61))
    p.move(to: CGPoint(x: 206, y: 106))
    p.addCurve(to: CGPoint(x: 306, y: 92), control1: CGPoint(x: 253, y: 86), control2: CGPoint(x: 282, y: 76))
    p.move(to: CGPoint(x: 229, y: 127))
    p.addCurve(to: CGPoint(x: 326, y: 113), control1: CGPoint(x: 262, y: 109), control2: CGPoint(x: 302, y: 100))
    p.move(to: CGPoint(x: 242, y: 154))
    p.addCurve(to: CGPoint(x: 328, y: 134), control1: CGPoint(x: 267, y: 135), control2: CGPoint(x: 307, y: 127))
    p.move(to: CGPoint(x: 249, y: 179))
    p.addCurve(to: CGPoint(x: 323, y: 156), control1: CGPoint(x: 274, y: 161), control2: CGPoint(x: 306, y: 156))
    p.move(to: CGPoint(x: 241, y: 209))
    p.addQuadCurve(to: CGPoint(x: 307, y: 181), control: CGPoint(x: 277, y: 180))
  }
  static let rimClub = Path { p in
    p.move(to: CGPoint(x: -14, y: 72))
    p.addQuadCurve(to: CGPoint(x: -10, y: 55), control: CGPoint(x: -12, y: 61))
    p.addCurve(to: CGPoint(x: 10, y: 55), control1: CGPoint(x: -7, y: 44), control2: CGPoint(x: 7, y: 44))
    p.addQuadCurve(to: CGPoint(x: 14, y: 72), control: CGPoint(x: 12, y: 61))
    p.addQuadCurve(to: CGPoint(x: -14, y: 72), control: CGPoint(x: 0, y: 76))
    p.closeSubpath()
  }
  static let rimCiliated = Path { p in
    p.move(to: CGPoint(x: -14, y: 72))
    p.addLine(to: CGPoint(x: -11, y: 55))
    p.addQuadCurve(to: CGPoint(x: 11, y: 55), control: CGPoint(x: 0, y: 54))
    p.addLine(to: CGPoint(x: 14, y: 72))
    p.addQuadCurve(to: CGPoint(x: -14, y: 72), control: CGPoint(x: 0, y: 76))
    p.closeSubpath()
  }
  static let bed = Path { p in
    p.move(to: CGPoint(x: 24, y: 244))
    p.addLine(to: CGPoint(x: 335, y: 244))
    p.addLine(to: CGPoint(x: 335, y: 276))
    p.addCurve(to: CGPoint(x: 173, y: 281), control1: CGPoint(x: 275, y: 285), control2: CGPoint(x: 235, y: 269))
    p.addCurve(to: CGPoint(x: 24, y: 282), control1: CGPoint(x: 117, y: 291), control2: CGPoint(x: 68, y: 277))
    p.closeSubpath()
  }
  static let bedFibers = Path { p in
    p.move(to: CGPoint(x: 35, y: 270))
    p.addQuadCurve(to: CGPoint(x: 107, y: 268), control: CGPoint(x: 71, y: 260))
    p.move(to: CGPoint(x: 86, y: 274))
    p.addQuadCurve(to: CGPoint(x: 174, y: 270), control: CGPoint(x: 140, y: 280))
    p.move(to: CGPoint(x: 191, y: 266))
    p.addQuadCurve(to: CGPoint(x: 260, y: 267), control: CGPoint(x: 224, y: 259))
    p.move(to: CGPoint(x: 251, y: 271))
    p.addQuadCurve(to: CGPoint(x: 323, y: 267), control: CGPoint(x: 293, y: 278))
  }
  static let ciliatedCell = Path { p in
    p.move(to: CGPoint(x: -47, y: 191))
    p.addQuadCurve(to: CGPoint(x: 47, y: 191), control: CGPoint(x: 0, y: 188))
    p.addCurve(to: CGPoint(x: 47, y: 253), control1: CGPoint(x: 45, y: 209), control2: CGPoint(x: 49, y: 234))
    p.addLine(to: CGPoint(x: -47, y: 253))
    p.addCurve(to: CGPoint(x: -47, y: 191), control1: CGPoint(x: -49, y: 235), control2: CGPoint(x: -45, y: 209))
    p.closeSubpath()
  }
  static let clubCell = Path { p in
    p.move(to: CGPoint(x: 118, y: 191))
    p.addCurve(to: CGPoint(x: 176, y: 151), control1: CGPoint(x: 137, y: 190), control2: CGPoint(x: 138, y: 151))
    p.addCurve(to: CGPoint(x: 234, y: 191), control1: CGPoint(x: 213, y: 151), control2: CGPoint(x: 216, y: 188))
    p.addCurve(to: CGPoint(x: 234, y: 253), control1: CGPoint(x: 233, y: 219), control2: CGPoint(x: 240, y: 241))
    p.addQuadCurve(to: CGPoint(x: 118, y: 253), control: CGPoint(x: 171, y: 257))
    p.addCurve(to: CGPoint(x: 118, y: 191), control1: CGPoint(x: 113, y: 234), control2: CGPoint(x: 121, y: 211))
    p.closeSubpath()
  }
  static let apicalLight = Path { p in
    p.move(to: CGPoint(x: 147, y: 174))
    p.addCurve(to: CGPoint(x: 176, y: 157), control1: CGPoint(x: 155, y: 160), control2: CGPoint(x: 164, y: 157))
    p.addQuadCurve(to: CGPoint(x: 200, y: 169), control: CGPoint(x: 190, y: 156))
  }
  static let film = Path { p in
    p.move(to: CGPoint(x: 24, y: 170))
    p.addQuadCurve(to: CGPoint(x: 112, y: 171), control: CGPoint(x: 71, y: 168))
    p.addCurve(to: CGPoint(x: 176, y: 129), control1: CGPoint(x: 130, y: 169), control2: CGPoint(x: 132, y: 129))
    p.addCurve(to: CGPoint(x: 241, y: 170), control1: CGPoint(x: 220, y: 129), control2: CGPoint(x: 225, y: 168))
    p.addQuadCurve(to: CGPoint(x: 335, y: 170), control: CGPoint(x: 284, y: 168))
    p.addLine(to: CGPoint(x: 335, y: 191))
    p.addLine(to: CGPoint(x: 234, y: 191))
    p.addCurve(to: CGPoint(x: 176, y: 151), control1: CGPoint(x: 216, y: 188), control2: CGPoint(x: 213, y: 151))
    p.addCurve(to: CGPoint(x: 118, y: 191), control1: CGPoint(x: 138, y: 151), control2: CGPoint(x: 137, y: 190))
    p.addLine(to: CGPoint(x: 24, y: 191))
    p.closeSubpath()
  }
  static let filmSurface = Path { p in
    p.move(to: CGPoint(x: 24, y: 170))
    p.addQuadCurve(to: CGPoint(x: 112, y: 171), control: CGPoint(x: 71, y: 168))
    p.addCurve(to: CGPoint(x: 176, y: 129), control1: CGPoint(x: 130, y: 169), control2: CGPoint(x: 132, y: 129))
    p.addCurve(to: CGPoint(x: 241, y: 170), control1: CGPoint(x: 220, y: 129), control2: CGPoint(x: 225, y: 168))
    p.addQuadCurve(to: CGPoint(x: 335, y: 170), control: CGPoint(x: 284, y: 168))
  }
  static let releasePore = Path { p in
    p.move(to: CGPoint(x: 170, y: 151))
    p.addCurve(to: CGPoint(x: 172, y: 161), control1: CGPoint(x: 173, y: 153), control2: CGPoint(x: 169, y: 157))
    p.addQuadCurve(to: CGPoint(x: 180, y: 161), control: CGPoint(x: 176, y: 166))
    p.addCurve(to: CGPoint(x: 182, y: 151), control1: CGPoint(x: 183, y: 157), control2: CGPoint(x: 179, y: 153))
  }
  static func renewal(_ right: Double, _ joinY: Double, _ shoulderY: Double) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 90, y: 191))
    p.addCurve(to: CGPoint(x: 126, y: 153), control1: CGPoint(x: 104, y: 190), control2: CGPoint(x: 103, y: 153))
    p.addCurve(to: CGPoint(x: 163, y: joinY), control1: CGPoint(x: 150, y: 153), control2: CGPoint(x: 147, y: joinY))
    p.addCurve(to: CGPoint(x: right, y: 191), control1: CGPoint(x: 173, y: shoulderY), control2: CGPoint(x: right - 10, y: shoulderY))
    p.addQuadCurve(to: CGPoint(x: right, y: 253), control: CGPoint(x: right + 2, y: 219))
    p.addLine(to: CGPoint(x: 90, y: 253))
    p.closeSubpath()
    return p
  }
}
