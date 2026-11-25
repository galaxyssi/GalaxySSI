import SwiftUI

enum GalaxySSIHealthAtlasScapularGeometry {
  static let back = Path { p in
    p.move(to: CGPoint(x: 89, y: 294))
    p.addCurve(to: CGPoint(x: 72, y: 165), control1: CGPoint(x: 86, y: 251), control2: CGPoint(x: 75, y: 208))
    p.addCurve(to: CGPoint(x: 89, y: 103), control1: CGPoint(x: 69, y: 140), control2: CGPoint(x: 79, y: 118))
    p.addQuadCurve(to: CGPoint(x: 100, y: 54), control: CGPoint(x: 98, y: 89))
    p.addQuadCurve(to: CGPoint(x: 128, y: 54), control: CGPoint(x: 113, y: 46))
    p.addCurve(to: CGPoint(x: 209, y: 104), control1: CGPoint(x: 130, y: 91), control2: CGPoint(x: 168, y: 93))
    p.addCurve(to: CGPoint(x: 279, y: 153), control1: CGPoint(x: 239, y: 107), control2: CGPoint(x: 268, y: 125))
    p.addCurve(to: CGPoint(x: 270, y: 287), control1: CGPoint(x: 295, y: 190), control2: CGPoint(x: 284, y: 252))
    p.addQuadCurve(to: CGPoint(x: 89, y: 294), control: CGPoint(x: 213, y: 314))
    p.closeSubpath()
  }
  static let blade = Path { p in
    p.move(to: CGPoint(x: 188, y: 106))
    p.addQuadCurve(to: CGPoint(x: 230, y: 124), control: CGPoint(x: 211, y: 110))
    p.addQuadCurve(to: CGPoint(x: 242, y: 107), control: CGPoint(x: 237, y: 116))
    p.addQuadCurve(to: CGPoint(x: 260, y: 109), control: CGPoint(x: 251, y: 101))
    p.addQuadCurve(to: CGPoint(x: 250, y: 122), control: CGPoint(x: 263, y: 117))
    p.addQuadCurve(to: CGPoint(x: 253, y: 135), control: CGPoint(x: 246, y: 129))
    p.addQuadCurve(to: CGPoint(x: 250, y: 155), control: CGPoint(x: 257, y: 143))
    p.addCurve(to: CGPoint(x: 194, y: 247), control1: CGPoint(x: 229, y: 166), control2: CGPoint(x: 214, y: 216))
    p.addQuadCurve(to: CGPoint(x: 188, y: 243), control: CGPoint(x: 190, y: 252))
    p.addCurve(to: CGPoint(x: 180, y: 159), control1: CGPoint(x: 186, y: 216), control2: CGPoint(x: 179, y: 189))
    p.addQuadCurve(to: CGPoint(x: 188, y: 106), control: CGPoint(x: 179, y: 124))
    p.closeSubpath()
  }
  static let ridge = Path { p in
    p.move(to: CGPoint(x: 181, y: 149))
    p.addCurve(to: CGPoint(x: 246, y: 121), control1: CGPoint(x: 195, y: 140), control2: CGPoint(x: 225, y: 147))
    p.addQuadCurve(to: CGPoint(x: 256, y: 114), control: CGPoint(x: 251, y: 115))
    p.move(to: CGPoint(x: 201, y: 154))
    p.addQuadCurve(to: CGPoint(x: 238, y: 139), control: CGPoint(x: 221, y: 156))
  }
  static let arm = Path { p in
    p.move(to: CGPoint(x: 251, y: 131))
    p.addCurve(to: CGPoint(x: 273, y: 135), control1: CGPoint(x: 258, y: 124), control2: CGPoint(x: 269, y: 126))
    p.addCurve(to: CGPoint(x: 268, y: 161), control1: CGPoint(x: 277, y: 145), control2: CGPoint(x: 268, y: 151))
    p.addLine(to: CGPoint(x: 272, y: 193))
    p.addQuadCurve(to: CGPoint(x: 257, y: 195), control: CGPoint(x: 265, y: 199))
    p.addLine(to: CGPoint(x: 255, y: 164))
    p.addQuadCurve(to: CGPoint(x: 251, y: 131), control: CGPoint(x: 248, y: 148))
    p.closeSubpath()
  }
  static let ribs: [Path] = [
    Path { p in
      p.move(to: CGPoint(x: 118, y: 118))
      p.addCurve(to: CGPoint(x: 250, y: 145), control1: CGPoint(x: 170, y: 102), control2: CGPoint(x: 224, y: 119))
    },
    Path { p in
      p.move(to: CGPoint(x: 116, y: 143))
      p.addCurve(to: CGPoint(x: 270, y: 170), control1: CGPoint(x: 169, y: 116), control2: CGPoint(x: 240, y: 140))
    },
    Path { p in
      p.move(to: CGPoint(x: 116, y: 166))
      p.addCurve(to: CGPoint(x: 281, y: 192), control1: CGPoint(x: 174, y: 132), control2: CGPoint(x: 251, y: 161))
    },
    Path { p in
      p.move(to: CGPoint(x: 116, y: 190))
      p.addCurve(to: CGPoint(x: 280, y: 212), control1: CGPoint(x: 177, y: 150), control2: CGPoint(x: 254, y: 180))
    },
    Path { p in
      p.move(to: CGPoint(x: 116, y: 215))
      p.addCurve(to: CGPoint(x: 275, y: 234), control1: CGPoint(x: 177, y: 169), control2: CGPoint(x: 250, y: 205))
    },
    Path { p in
      p.move(to: CGPoint(x: 115, y: 240))
      p.addCurve(to: CGPoint(x: 269, y: 254), control1: CGPoint(x: 175, y: 195), control2: CGPoint(x: 242, y: 224))
    },
    Path { p in
      p.move(to: CGPoint(x: 116, y: 263))
      p.addCurve(to: CGPoint(x: 257, y: 272), control1: CGPoint(x: 166, y: 226), control2: CGPoint(x: 234, y: 244))
    },
  ]
}
