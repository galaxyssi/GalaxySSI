import SwiftUI

enum GalaxySSIHealthAtlasAcinarGeometry {
  static let acinarWedge = Path { p in
    p.move(to: CGPoint(x: 9, y: -4))
    p.addQuadCurve(to: CGPoint(x: 51, y: -21), control: CGPoint(x: 33, y: -12))
    p.addCurve(to: CGPoint(x: 67, y: -1), control1: CGPoint(x: 63, y: -27), control2: CGPoint(x: 67, y: -15))
    p.addCurve(to: CGPoint(x: 51, y: 22), control1: CGPoint(x: 67, y: 16), control2: CGPoint(x: 63, y: 27))
    p.addQuadCurve(to: CGPoint(x: 9, y: 4), control: CGPoint(x: 33, y: 14))
    p.closeSubpath()
  }
  static let acinarOutlet = Path { p in
    p.move(to: CGPoint(x: 0, y: 0))
    p.addCurve(to: CGPoint(x: 85, y: 0), control1: CGPoint(x: 24, y: -3), control2: CGPoint(x: 57, y: -2))
  }
  static let septum = Path { p in
    p.move(to: CGPoint(x: 20, y: 122))
    p.addCurve(to: CGPoint(x: 73, y: 100), control1: CGPoint(x: 23, y: 99), control2: CGPoint(x: 51, y: 93))
    p.addCurve(to: CGPoint(x: 146, y: 123), control1: CGPoint(x: 99, y: 85), control2: CGPoint(x: 133, y: 98))
    p.addCurve(to: CGPoint(x: 163, y: 190), control1: CGPoint(x: 171, y: 138), control2: CGPoint(x: 167, y: 168))
    p.addCurve(to: CGPoint(x: 146, y: 267), control1: CGPoint(x: 179, y: 211), control2: CGPoint(x: 166, y: 247))
    p.addCurve(to: CGPoint(x: 75, y: 277), control1: CGPoint(x: 121, y: 289), control2: CGPoint(x: 102, y: 266))
    p.addCurve(to: CGPoint(x: 25, y: 229), control1: CGPoint(x: 41, y: 283), control2: CGPoint(x: 20, y: 257))
    p.addCurve(to: CGPoint(x: 28, y: 166), control1: CGPoint(x: 12, y: 209), control2: CGPoint(x: 15, y: 187))
    p.addQuadCurve(to: CGPoint(x: 20, y: 122), control: CGPoint(x: 15, y: 145))
    p.closeSubpath()
  }
  static let lobuleDucts = Path { p in
    p.move(to: CGPoint(x: 151, y: 127))
    p.addCurve(to: CGPoint(x: 137, y: 268), control1: CGPoint(x: 149, y: 178), control2: CGPoint(x: 152, y: 222))
    p.move(to: CGPoint(x: 83, y: 131))
    p.addQuadCurve(to: CGPoint(x: 149, y: 144), control: CGPoint(x: 114, y: 127))
    p.move(to: CGPoint(x: 91, y: 183))
    p.addQuadCurve(to: CGPoint(x: 150, y: 195), control: CGPoint(x: 122, y: 181))
    p.move(to: CGPoint(x: 82, y: 237))
    p.addQuadCurve(to: CGPoint(x: 146, y: 226), control: CGPoint(x: 117, y: 237))
    p.move(to: CGPoint(x: 127, y: 250))
    p.addQuadCurve(to: CGPoint(x: 141, y: 251), control: CGPoint(x: 136, y: 249))
  }
  static let cell = Path { p in
    p.move(to: CGPoint(x: 240, y: 136))
    p.addCurve(to: CGPoint(x: 75, y: 94), control1: CGPoint(x: 190, y: 132), control2: CGPoint(x: 133, y: 84))
    p.addCurve(to: CGPoint(x: 42, y: 211), control1: CGPoint(x: 34, y: 101), control2: CGPoint(x: 32, y: 153))
    p.addCurve(to: CGPoint(x: 133, y: 240), control1: CGPoint(x: 51, y: 258), control2: CGPoint(x: 91, y: 260))
    p.addCurve(to: CGPoint(x: 240, y: 204), control1: CGPoint(x: 176, y: 220), control2: CGPoint(x: 206, y: 208))
    p.closeSubpath()
  }
  static let cellOuterMembrane = Path { p in
    p.move(to: CGPoint(x: 240, y: 136))
    p.addCurve(to: CGPoint(x: 75, y: 94), control1: CGPoint(x: 190, y: 132), control2: CGPoint(x: 133, y: 84))
    p.addCurve(to: CGPoint(x: 42, y: 211), control1: CGPoint(x: 34, y: 101), control2: CGPoint(x: 32, y: 153))
    p.addCurve(to: CGPoint(x: 133, y: 240), control1: CGPoint(x: 51, y: 258), control2: CGPoint(x: 91, y: 260))
    p.addCurve(to: CGPoint(x: 240, y: 204), control1: CGPoint(x: 176, y: 220), control2: CGPoint(x: 206, y: 208))
  }
  static let facingCell = Path { p in
    p.move(to: CGPoint(x: 272, y: 143))
    p.addCurve(to: CGPoint(x: 301, y: 116), control1: CGPoint(x: 281, y: 139), control2: CGPoint(x: 293, y: 128))
    p.addCurve(to: CGPoint(x: 332, y: 177), control1: CGPoint(x: 329, y: 120), control2: CGPoint(x: 341, y: 151))
    p.addCurve(to: CGPoint(x: 274, y: 209), control1: CGPoint(x: 323, y: 204), control2: CGPoint(x: 294, y: 220))
    p.addQuadCurve(to: CGPoint(x: 272, y: 143), control: CGPoint(x: 269, y: 182))
    p.closeSubpath()
  }
  static let acinarSpace = Path { p in
    p.move(to: CGPoint(x: 240, y: 136))
    p.addCurve(to: CGPoint(x: 299, y: 100), control1: CGPoint(x: 263, y: 135), control2: CGPoint(x: 279, y: 116))
    p.addQuadCurve(to: CGPoint(x: 324, y: 85), control: CGPoint(x: 307, y: 93))
    p.addLine(to: CGPoint(x: 332, y: 100))
    p.addCurve(to: CGPoint(x: 290, y: 129), control1: CGPoint(x: 316, y: 107), control2: CGPoint(x: 300, y: 117))
    p.addQuadCurve(to: CGPoint(x: 272, y: 143), control: CGPoint(x: 282, y: 138))
    p.addQuadCurve(to: CGPoint(x: 274, y: 209), control: CGPoint(x: 270, y: 183))
    p.addQuadCurve(to: CGPoint(x: 240, y: 204), control: CGPoint(x: 257, y: 216))
    p.closeSubpath()
  }
  static let fusionMouth = Path { p in
    p.move(to: CGPoint(x: 240, y: 169))
    p.addCurve(to: CGPoint(x: 224, y: 167), control1: CGPoint(x: 231, y: 169), control2: CGPoint(x: 230, y: 164))
    p.addCurve(to: CGPoint(x: 225, y: 186), control1: CGPoint(x: 215, y: 171), control2: CGPoint(x: 216, y: 183))
    p.addCurve(to: CGPoint(x: 240, y: 181), control1: CGPoint(x: 232, y: 188), control2: CGPoint(x: 234, y: 181))
  }
  static let collectingBranches = Path { p in
    p.move(to: CGPoint(x: 102, y: 105))
    p.addCurve(to: CGPoint(x: 126, y: 182), control1: CGPoint(x: 127, y: 107), control2: CGPoint(x: 101, y: 153))
    p.move(to: CGPoint(x: 97, y: 252))
    p.addCurve(to: CGPoint(x: 135, y: 182), control1: CGPoint(x: 127, y: 247), control2: CGPoint(x: 107, y: 211))
  }
  static let collectingDuct = Path { p in
    p.move(to: CGPoint(x: 94, y: 181))
    p.addQuadCurve(to: CGPoint(x: 130, y: 182), control: CGPoint(x: 108, y: 182))
    p.addLine(to: CGPoint(x: 330, y: 182))
  }
  static let pancreas = Path { p in
    p.move(to: CGPoint(x: 28, y: 146))
    p.addCurve(to: CGPoint(x: 69, y: 131), control1: CGPoint(x: 35, y: 131), control2: CGPoint(x: 57, y: 138))
    p.addCurve(to: CGPoint(x: 121, y: 129), control1: CGPoint(x: 87, y: 120), control2: CGPoint(x: 104, y: 134))
    p.addCurve(to: CGPoint(x: 165, y: 135), control1: CGPoint(x: 140, y: 121), control2: CGPoint(x: 149, y: 137))
    p.addCurve(to: CGPoint(x: 204, y: 139), control1: CGPoint(x: 182, y: 128), control2: CGPoint(x: 193, y: 143))
    p.addCurve(to: CGPoint(x: 237, y: 134), control1: CGPoint(x: 218, y: 139), control2: CGPoint(x: 221, y: 129))
    p.addCurve(to: CGPoint(x: 273, y: 170), control1: CGPoint(x: 256, y: 132), control2: CGPoint(x: 273, y: 151))
    p.addCurve(to: CGPoint(x: 248, y: 230), control1: CGPoint(x: 283, y: 190), control2: CGPoint(x: 265, y: 224))
    p.addCurve(to: CGPoint(x: 211, y: 216), control1: CGPoint(x: 231, y: 242), control2: CGPoint(x: 211, y: 232))
    p.addCurve(to: CGPoint(x: 187, y: 199), control1: CGPoint(x: 209, y: 204), control2: CGPoint(x: 196, y: 212))
    p.addCurve(to: CGPoint(x: 151, y: 187), control1: CGPoint(x: 174, y: 201), control2: CGPoint(x: 165, y: 184))
    p.addCurve(to: CGPoint(x: 114, y: 178), control1: CGPoint(x: 138, y: 190), control2: CGPoint(x: 131, y: 176))
    p.addCurve(to: CGPoint(x: 68, y: 170), control1: CGPoint(x: 93, y: 180), control2: CGPoint(x: 87, y: 168))
    p.addCurve(to: CGPoint(x: 28, y: 146), control1: CGPoint(x: 53, y: 171), control2: CGPoint(x: 20, y: 162))
    p.closeSubpath()
  }
  static let lobularScallops = Path { p in
    p.move(to: CGPoint(x: 62, y: 136))
    p.addQuadCurve(to: CGPoint(x: 59, y: 148), control: CGPoint(x: 54, y: 141))
    p.move(to: CGPoint(x: 94, y: 132))
    p.addQuadCurve(to: CGPoint(x: 91, y: 148), control: CGPoint(x: 85, y: 139))
    p.move(to: CGPoint(x: 128, y: 134))
    p.addQuadCurve(to: CGPoint(x: 124, y: 151), control: CGPoint(x: 118, y: 141))
    p.move(to: CGPoint(x: 164, y: 139))
    p.addQuadCurve(to: CGPoint(x: 156, y: 159), control: CGPoint(x: 148, y: 147))
    p.move(to: CGPoint(x: 194, y: 140))
    p.addQuadCurve(to: CGPoint(x: 191, y: 170), control: CGPoint(x: 181, y: 151))
    p.move(to: CGPoint(x: 239, y: 137))
    p.addQuadCurve(to: CGPoint(x: 224, y: 165), control: CGPoint(x: 219, y: 145))
    p.move(to: CGPoint(x: 82, y: 170))
    p.addQuadCurve(to: CGPoint(x: 72, y: 157), control: CGPoint(x: 83, y: 159))
    p.move(to: CGPoint(x: 121, y: 177))
    p.addQuadCurve(to: CGPoint(x: 103, y: 169), control: CGPoint(x: 116, y: 166))
    p.move(to: CGPoint(x: 153, y: 185))
    p.addQuadCurve(to: CGPoint(x: 141, y: 173), control: CGPoint(x: 156, y: 175))
    p.move(to: CGPoint(x: 182, y: 196))
    p.addQuadCurve(to: CGPoint(x: 169, y: 182), control: CGPoint(x: 182, y: 181))
    p.move(to: CGPoint(x: 202, y: 206))
    p.addQuadCurve(to: CGPoint(x: 195, y: 191), control: CGPoint(x: 206, y: 195))
    p.move(to: CGPoint(x: 234, y: 232))
    p.addQuadCurve(to: CGPoint(x: 233, y: 197), control: CGPoint(x: 246, y: 216))
    p.move(to: CGPoint(x: 261, y: 216))
    p.addQuadCurve(to: CGPoint(x: 259, y: 194), control: CGPoint(x: 248, y: 206))
  }
  static let duodenum = Path { p in
    p.move(to: CGPoint(x: 227, y: 101))
    p.addCurve(to: CGPoint(x: 298, y: 162), control1: CGPoint(x: 272, y: 93), control2: CGPoint(x: 299, y: 111))
    p.addCurve(to: CGPoint(x: 269, y: 247), control1: CGPoint(x: 297, y: 202), control2: CGPoint(x: 296, y: 226))
    p.addCurve(to: CGPoint(x: 157, y: 264), control1: CGPoint(x: 238, y: 271), control2: CGPoint(x: 197, y: 258))
  }
  static let pancreaticDuct = Path { p in
    p.move(to: CGPoint(x: 47, y: 151))
    p.addCurve(to: CGPoint(x: 168, y: 167), control1: CGPoint(x: 94, y: 153), control2: CGPoint(x: 131, y: 158))
    p.addCurve(to: CGPoint(x: 297, y: 184), control1: CGPoint(x: 214, y: 178), control2: CGPoint(x: 251, y: 201))
  }
  static let duodenalFolds = Path { p in
    p.move(to: CGPoint(x: 252, y: 90))
    p.addQuadCurve(to: CGPoint(x: 251, y: 104), control: CGPoint(x: 249, y: 96))
    p.move(to: CGPoint(x: 277, y: 98))
    p.addQuadCurve(to: CGPoint(x: 273, y: 111), control: CGPoint(x: 270, y: 102))
    p.move(to: CGPoint(x: 303, y: 125))
    p.addQuadCurve(to: CGPoint(x: 290, y: 135), control: CGPoint(x: 296, y: 127))
    p.move(to: CGPoint(x: 308, y: 150))
    p.addQuadCurve(to: CGPoint(x: 296, y: 156), control: CGPoint(x: 301, y: 149))
    p.move(to: CGPoint(x: 308, y: 171))
    p.addQuadCurve(to: CGPoint(x: 298, y: 175), control: CGPoint(x: 302, y: 168))
    p.move(to: CGPoint(x: 305, y: 203))
    p.addQuadCurve(to: CGPoint(x: 292, y: 204), control: CGPoint(x: 298, y: 199))
    p.move(to: CGPoint(x: 298, y: 224))
    p.addQuadCurve(to: CGPoint(x: 284, y: 225), control: CGPoint(x: 289, y: 218))
    p.move(to: CGPoint(x: 281, y: 247))
    p.addQuadCurve(to: CGPoint(x: 270, y: 239), control: CGPoint(x: 278, y: 239))
    p.move(to: CGPoint(x: 251, y: 267))
    p.addQuadCurve(to: CGPoint(x: 247, y: 253), control: CGPoint(x: 253, y: 260))
    p.move(to: CGPoint(x: 225, y: 271))
    p.addQuadCurve(to: CGPoint(x: 223, y: 255), control: CGPoint(x: 228, y: 262))
    p.move(to: CGPoint(x: 190, y: 250))
    p.addQuadCurve(to: CGPoint(x: 190, y: 264), control: CGPoint(x: 186, y: 256))
    p.move(to: CGPoint(x: 170, y: 252))
    p.addQuadCurve(to: CGPoint(x: 171, y: 264), control: CGPoint(x: 166, y: 259))
  }
  static let erFolds: [Path] = (0..<5).map { index in
    let row = Double(index), y = 120 + row * 8
    return Path { p in
      p.move(to: CGPoint(x: 61 - row * 1.2, y: y + 1))
      p.addCurve(to: CGPoint(x: 111 + row * 1.4, y: y + 1), control1: CGPoint(x: 78, y: y - 10), control2: CGPoint(x: 89, y: y + 7))
    }
  }
  static let golgiStacks: [Path] = (0..<5).map { index in
    let row = Double(index), x = 127 + row * 6
    return Path { p in
      p.move(to: CGPoint(x: x + 5, y: 159 + row))
      p.addQuadCurve(to: CGPoint(x: x + 10, y: 196 - row * 0.8), control: CGPoint(x: x - 10, y: 179))
    }
  }
  static func diamond(_ x: Double, _ y: Double, _ r: Double) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: x, y: y - r - 0.8))
    p.addLine(to: CGPoint(x: x + r, y: y))
    p.addLine(to: CGPoint(x: x, y: y + r + 0.8))
    p.addLine(to: CGPoint(x: x - r, y: y))
    p.closeSubpath()
    return p
  }
}
