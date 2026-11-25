import SwiftUI

enum GalaxySSIHealthAtlasDuctBufferGeometry {
  static let acinarWedge = Path { p in
    p.move(to: CGPoint(x: 5, y: -3))
    p.addQuadCurve(to: CGPoint(x: 29, y: -16), control: CGPoint(x: 17, y: -8))
    p.addCurve(to: CGPoint(x: 40, y: 0), control1: CGPoint(x: 38, y: -19), control2: CGPoint(x: 40, y: -10))
    p.addCurve(to: CGPoint(x: 29, y: 16), control1: CGPoint(x: 40, y: 11), control2: CGPoint(x: 37, y: 18))
    p.addQuadCurve(to: CGPoint(x: 5, y: 3), control: CGPoint(x: 17, y: 7))
    p.closeSubpath()
  }
  static let lobule = Path { p in
    p.move(to: CGPoint(x: 48, y: 73))
    p.addCurve(to: CGPoint(x: 154, y: 94), control1: CGPoint(x: 88, y: 49), control2: CGPoint(x: 135, y: 62))
    p.addCurve(to: CGPoint(x: 248, y: 120), control1: CGPoint(x: 184, y: 83), control2: CGPoint(x: 219, y: 89))
    p.addCurve(to: CGPoint(x: 269, y: 213), control1: CGPoint(x: 265, y: 149), control2: CGPoint(x: 249, y: 182))
    p.addCurve(to: CGPoint(x: 296, y: 290), control1: CGPoint(x: 306, y: 233), control2: CGPoint(x: 327, y: 271))
    p.addCurve(to: CGPoint(x: 193, y: 288), control1: CGPoint(x: 267, y: 308), control2: CGPoint(x: 229, y: 270))
    p.addCurve(to: CGPoint(x: 109, y: 297), control1: CGPoint(x: 156, y: 304), control2: CGPoint(x: 131, y: 280))
    p.addCurve(to: CGPoint(x: 54, y: 259), control1: CGPoint(x: 78, y: 311), control2: CGPoint(x: 50, y: 284))
    p.addCurve(to: CGPoint(x: 46, y: 184), control1: CGPoint(x: 26, y: 234), control2: CGPoint(x: 36, y: 201))
    p.addCurve(to: CGPoint(x: 48, y: 73), control1: CGPoint(x: 22, y: 149), control2: CGPoint(x: 20, y: 103))
    p.closeSubpath()
  }
  static let collecting = Path { p in
    p.move(to: CGPoint(x: 223, y: 119))
    p.addCurve(to: CGPoint(x: 242, y: 223), control1: CGPoint(x: 226, y: 157), control2: CGPoint(x: 226, y: 196))
    p.addQuadCurve(to: CGPoint(x: 301, y: 265), control: CGPoint(x: 260, y: 250))
  }
  static let mucosa = Path { p in
    p.move(to: CGPoint(x: 31, y: 145))
    p.addCurve(to: CGPoint(x: 217, y: 145), control1: CGPoint(x: 111, y: 147), control2: CGPoint(x: 153, y: 143))
    p.addQuadCurve(to: CGPoint(x: 327, y: 143), control: CGPoint(x: 272, y: 148))
    p.addLine(to: CGPoint(x: 327, y: 185))
    p.addCurve(to: CGPoint(x: 31, y: 196), control1: CGPoint(x: 264, y: 211), control2: CGPoint(x: 107, y: 182))
    p.closeSubpath()
  }
  static let sCell = Path { p in
    p.move(to: CGPoint(x: 214, y: 147))
    p.addLine(to: CGPoint(x: 223, y: 147))
    p.addCurve(to: CGPoint(x: 228, y: 178), control1: CGPoint(x: 222, y: 159), control2: CGPoint(x: 233, y: 170))
    p.addQuadCurve(to: CGPoint(x: 208, y: 178), control: CGPoint(x: 219, y: 185))
    p.addCurve(to: CGPoint(x: 214, y: 147), control1: CGPoint(x: 204, y: 167), control2: CGPoint(x: 215, y: 160))
    p.closeSubpath()
  }
  static let bloodCourse = Path { p in
    p.move(to: CGPoint(x: 219, y: 190))
    p.addCurve(to: CGPoint(x: 146, y: 225), control1: CGPoint(x: 220, y: 221), control2: CGPoint(x: 185, y: 229))
    p.addCurve(to: CGPoint(x: 85, y: 256), control1: CGPoint(x: 103, y: 222), control2: CGPoint(x: 78, y: 229))
    p.addQuadCurve(to: CGPoint(x: 130, y: 266), control: CGPoint(x: 92, y: 269))
  }
  static let pancreas = Path { p in
    p.move(to: CGPoint(x: 27, y: 142))
    p.addCurve(to: CGPoint(x: 62, y: 125), control1: CGPoint(x: 24, y: 130), control2: CGPoint(x: 46, y: 121))
    p.addCurve(to: CGPoint(x: 117, y: 122), control1: CGPoint(x: 77, y: 124), control2: CGPoint(x: 103, y: 112))
    p.addCurve(to: CGPoint(x: 156, y: 125), control1: CGPoint(x: 132, y: 126), control2: CGPoint(x: 140, y: 116))
    p.addCurve(to: CGPoint(x: 200, y: 130), control1: CGPoint(x: 171, y: 136), control2: CGPoint(x: 186, y: 133))
    p.addCurve(to: CGPoint(x: 250, y: 144), control1: CGPoint(x: 220, y: 123), control2: CGPoint(x: 239, y: 130))
    p.addCurve(to: CGPoint(x: 264, y: 166), control1: CGPoint(x: 267, y: 139), control2: CGPoint(x: 267, y: 154))
    p.addCurve(to: CGPoint(x: 256, y: 207), control1: CGPoint(x: 278, y: 180), control2: CGPoint(x: 263, y: 199))
    p.addCurve(to: CGPoint(x: 218, y: 226), control1: CGPoint(x: 255, y: 224), control2: CGPoint(x: 235, y: 233))
    p.addCurve(to: CGPoint(x: 189, y: 207), control1: CGPoint(x: 206, y: 228), control2: CGPoint(x: 206, y: 208))
    p.addCurve(to: CGPoint(x: 157, y: 192), control1: CGPoint(x: 172, y: 202), control2: CGPoint(x: 175, y: 191))
    p.addCurve(to: CGPoint(x: 116, y: 182), control1: CGPoint(x: 140, y: 191), control2: CGPoint(x: 130, y: 180))
    p.addCurve(to: CGPoint(x: 66, y: 168), control1: CGPoint(x: 94, y: 182), control2: CGPoint(x: 84, y: 165))
    p.addQuadCurve(to: CGPoint(x: 27, y: 142), control: CGPoint(x: 37, y: 161))
    p.closeSubpath()
  }
  static let organDetails = Path { p in
    p.move(to: CGPoint(x: 61, y: 127))
    p.addQuadCurve(to: CGPoint(x: 63, y: 146), control: CGPoint(x: 53, y: 139))
    p.move(to: CGPoint(x: 95, y: 122))
    p.addQuadCurve(to: CGPoint(x: 92, y: 142), control: CGPoint(x: 83, y: 137))
    p.move(to: CGPoint(x: 127, y: 125))
    p.addQuadCurve(to: CGPoint(x: 128, y: 148), control: CGPoint(x: 116, y: 139))
    p.move(to: CGPoint(x: 159, y: 128))
    p.addQuadCurve(to: CGPoint(x: 152, y: 154), control: CGPoint(x: 148, y: 140))
    p.move(to: CGPoint(x: 191, y: 132))
    p.addQuadCurve(to: CGPoint(x: 183, y: 150), control: CGPoint(x: 176, y: 142))
    p.move(to: CGPoint(x: 223, y: 129))
    p.addQuadCurve(to: CGPoint(x: 218, y: 156), control: CGPoint(x: 211, y: 142))
    p.move(to: CGPoint(x: 74, y: 167))
    p.addQuadCurve(to: CGPoint(x: 86, y: 156), control: CGPoint(x: 77, y: 156))
    p.move(to: CGPoint(x: 107, y: 178))
    p.addQuadCurve(to: CGPoint(x: 120, y: 163), control: CGPoint(x: 103, y: 166))
    p.move(to: CGPoint(x: 145, y: 188))
    p.addQuadCurve(to: CGPoint(x: 155, y: 175), control: CGPoint(x: 138, y: 175))
    p.move(to: CGPoint(x: 177, y: 197))
    p.addQuadCurve(to: CGPoint(x: 177, y: 179), control: CGPoint(x: 186, y: 187))
    p.move(to: CGPoint(x: 210, y: 215))
    p.addQuadCurve(to: CGPoint(x: 211, y: 195), control: CGPoint(x: 220, y: 205))
    p.move(to: CGPoint(x: 245, y: 220))
    p.addQuadCurve(to: CGPoint(x: 243, y: 198), control: CGPoint(x: 234, y: 210))
  }
  static let duodenum = Path { p in
    p.move(to: CGPoint(x: 204, y: 100))
    p.addCurve(to: CGPoint(x: 305, y: 167), control1: CGPoint(x: 265, y: 81), control2: CGPoint(x: 307, y: 110))
    p.addCurve(to: CGPoint(x: 221, y: 261), control1: CGPoint(x: 304, y: 235), control2: CGPoint(x: 275, y: 264))
    p.addQuadCurve(to: CGPoint(x: 160, y: 268), control: CGPoint(x: 187, y: 260))
  }
  static let organBranches = Path { p in
    p.move(to: CGPoint(x: 82, y: 133))
    p.addQuadCurve(to: CGPoint(x: 107, y: 152), control: CGPoint(x: 91, y: 145))
    p.move(to: CGPoint(x: 131, y: 172))
    p.addQuadCurve(to: CGPoint(x: 149, y: 160), control: CGPoint(x: 136, y: 163))
    p.move(to: CGPoint(x: 177, y: 143))
    p.addQuadCurve(to: CGPoint(x: 195, y: 174), control: CGPoint(x: 182, y: 158))
    p.move(to: CGPoint(x: 227, y: 211))
    p.addQuadCurve(to: CGPoint(x: 240, y: 187), control: CGPoint(x: 228, y: 194))
  }
  static let mainDuct = Path { p in
    p.move(to: CGPoint(x: 45, y: 142))
    p.addCurve(to: CGPoint(x: 191, y: 173), control1: CGPoint(x: 93, y: 154), control2: CGPoint(x: 147, y: 153))
    p.addCurve(to: CGPoint(x: 298, y: 185), control1: CGPoint(x: 222, y: 188), control2: CGPoint(x: 261, y: 189))
  }
  static let bufferBowel = Path { p in
    p.move(to: CGPoint(x: 53, y: 182))
    p.addCurve(to: CGPoint(x: 190, y: 185), control1: CGPoint(x: 112, y: 165), control2: CGPoint(x: 151, y: 172))
    p.addQuadCurve(to: CGPoint(x: 310, y: 188), control: CGPoint(x: 253, y: 209))
  }
  static let bufferInlet = Path { p in
    p.move(to: CGPoint(x: 215, y: 97))
    p.addCurve(to: CGPoint(x: 192, y: 165), control1: CGPoint(x: 215, y: 121), control2: CGPoint(x: 188, y: 131))
  }
  static let lobuleBranches: [Path] = [
    Path { p in
    p.move(to: CGPoint(x: 85, y: 107))
    p.addCurve(to: CGPoint(x: 225, y: 139), control1: CGPoint(x: 144, y: 106), control2: CGPoint(x: 175, y: 141))
    },
    Path { p in
    p.move(to: CGPoint(x: 86, y: 180))
    p.addCurve(to: CGPoint(x: 230, y: 183), control1: CGPoint(x: 146, y: 173), control2: CGPoint(x: 168, y: 188))
    },
    Path { p in
    p.move(to: CGPoint(x: 93, y: 254))
    p.addCurve(to: CGPoint(x: 244, y: 225), control1: CGPoint(x: 164, y: 255), control2: CGPoint(x: 196, y: 233))
    },
  ]
}
