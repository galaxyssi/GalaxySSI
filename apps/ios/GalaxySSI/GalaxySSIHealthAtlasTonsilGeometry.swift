import SwiftUI

enum GalaxySSIHealthAtlasTonsilGeometry {
  static let head = Path { p in
    p.move(to: CGPoint(x: 101, y: 315))
    p.addCurve(to: CGPoint(x: 89, y: 254), control1: CGPoint(x: 103, y: 278), control2: CGPoint(x: 109, y: 267))
    p.addCurve(to: CGPoint(x: 56, y: 232), control1: CGPoint(x: 73, y: 249), control2: CGPoint(x: 58, y: 246))
    p.addQuadCurve(to: CGPoint(x: 58, y: 215), control: CGPoint(x: 54, y: 223))
    p.addQuadCurve(to: CGPoint(x: 54, y: 203), control: CGPoint(x: 45, y: 210))
    p.addQuadCurve(to: CGPoint(x: 51, y: 191), control: CGPoint(x: 44, y: 197))
    p.addQuadCurve(to: CGPoint(x: 56, y: 173), control: CGPoint(x: 58, y: 184))
    p.addCurve(to: CGPoint(x: 37, y: 159), control1: CGPoint(x: 38, y: 174), control2: CGPoint(x: 31, y: 168))
    p.addCurve(to: CGPoint(x: 58, y: 125), control1: CGPoint(x: 44, y: 149), control2: CGPoint(x: 55, y: 137))
    p.addCurve(to: CGPoint(x: 119, y: 47), control1: CGPoint(x: 57, y: 87), control2: CGPoint(x: 82, y: 53))
    p.addCurve(to: CGPoint(x: 229, y: 123), control1: CGPoint(x: 184, y: 31), control2: CGPoint(x: 226, y: 69))
    p.addCurve(to: CGPoint(x: 199, y: 228), control1: CGPoint(x: 233, y: 170), control2: CGPoint(x: 212, y: 199))
    p.addCurve(to: CGPoint(x: 205, y: 315), control1: CGPoint(x: 187, y: 257), control2: CGPoint(x: 185, y: 283))
    p.addQuadCurve(to: CGPoint(x: 101, y: 315), control: CGPoint(x: 153, y: 328))
    p.closeSubpath()
  }
  static let airway = Path { p in
    p.move(to: CGPoint(x: 48, y: 164))
    p.addCurve(to: CGPoint(x: 79, y: 121), control1: CGPoint(x: 63, y: 148), control2: CGPoint(x: 62, y: 131))
    p.addCurve(to: CGPoint(x: 153, y: 111), control1: CGPoint(x: 96, y: 109), control2: CGPoint(x: 129, y: 104))
    p.addCurve(to: CGPoint(x: 176, y: 180), control1: CGPoint(x: 184, y: 121), control2: CGPoint(x: 182, y: 154))
    p.addCurve(to: CGPoint(x: 170, y: 251), control1: CGPoint(x: 171, y: 204), control2: CGPoint(x: 172, y: 230))
    p.addQuadCurve(to: CGPoint(x: 169, y: 292), control: CGPoint(x: 168, y: 271))
    p.addLine(to: CGPoint(x: 151, y: 293))
    p.addCurve(to: CGPoint(x: 137, y: 226), control1: CGPoint(x: 151, y: 263), control2: CGPoint(x: 149, y: 246))
    p.addCurve(to: CGPoint(x: 76, y: 212), control1: CGPoint(x: 125, y: 217), control2: CGPoint(x: 99, y: 221))
    p.addQuadCurve(to: CGPoint(x: 53, y: 202), control: CGPoint(x: 65, y: 206))
    p.addCurve(to: CGPoint(x: 130, y: 183), control1: CGPoint(x: 74, y: 192), control2: CGPoint(x: 101, y: 183))
    p.addQuadCurve(to: CGPoint(x: 151, y: 176), control: CGPoint(x: 145, y: 187))
    p.addQuadCurve(to: CGPoint(x: 83, y: 166), control: CGPoint(x: 123, y: 158))
    p.addQuadCurve(to: CGPoint(x: 48, y: 164), control: CGPoint(x: 66, y: 171))
    p.closeSubpath()
  }
  static let palate = Path { p in
    p.move(to: CGPoint(x: 64, y: 177))
    p.addCurve(to: CGPoint(x: 148, y: 169), control1: CGPoint(x: 93, y: 166), control2: CGPoint(x: 127, y: 160))
    p.addQuadCurve(to: CGPoint(x: 153, y: 184), control: CGPoint(x: 158, y: 174))
    p.addQuadCurve(to: CGPoint(x: 143, y: 180), control: CGPoint(x: 148, y: 185))
    p.addCurve(to: CGPoint(x: 64, y: 181), control1: CGPoint(x: 126, y: 169), control2: CGPoint(x: 87, y: 174))
    p.closeSubpath()
  }
  static let tongue = Path { p in
    p.move(to: CGPoint(x: 70, y: 207))
    p.addCurve(to: CGPoint(x: 137, y: 206), control1: CGPoint(x: 94, y: 201), control2: CGPoint(x: 120, y: 188))
    p.addQuadCurve(to: CGPoint(x: 149, y: 235), control: CGPoint(x: 145, y: 214))
    p.addCurve(to: CGPoint(x: 70, y: 207), control1: CGPoint(x: 133, y: 221), control2: CGPoint(x: 92, y: 234))
    p.closeSubpath()
  }
  static let nasalRidges = Path { p in
    p.move(to: CGPoint(x: 74, y: 146))
    p.addCurve(to: CGPoint(x: 136, y: 130), control1: CGPoint(x: 86, y: 133), control2: CGPoint(x: 110, y: 128))
    p.move(to: CGPoint(x: 63, y: 156))
    p.addCurve(to: CGPoint(x: 141, y: 143), control1: CGPoint(x: 85, y: 145), control2: CGPoint(x: 111, y: 145))
    p.move(to: CGPoint(x: 78, y: 159))
    p.addQuadCurve(to: CGPoint(x: 128, y: 153), control: CGPoint(x: 107, y: 152))
  }
  static let adenoidPatch = Path { p in
    p.move(to: CGPoint(x: 145, y: 110))
    p.addQuadCurve(to: CGPoint(x: 177, y: 121), control: CGPoint(x: 165, y: 105))
    p.addQuadCurve(to: CGPoint(x: 178, y: 147), control: CGPoint(x: 184, y: 133))
    p.addQuadCurve(to: CGPoint(x: 170, y: 140), control: CGPoint(x: 170, y: 149))
    p.addQuadCurve(to: CGPoint(x: 164, y: 133), control: CGPoint(x: 162, y: 141))
    p.addQuadCurve(to: CGPoint(x: 157, y: 125), control: CGPoint(x: 155, y: 134))
    p.addQuadCurve(to: CGPoint(x: 145, y: 110), control: CGPoint(x: 145, y: 125))
    p.closeSubpath()
  }
  static let smallCrypt = Path { p in
    p.move(to: CGPoint(x: 84, y: 134))
    p.addCurve(to: CGPoint(x: 83, y: 178), control1: CGPoint(x: 89, y: 156), control2: CGPoint(x: 92, y: 165))
    p.addQuadCurve(to: CGPoint(x: 94, y: 182), control: CGPoint(x: 81, y: 186))
    p.addCurve(to: CGPoint(x: 106, y: 207), control1: CGPoint(x: 95, y: 195), control2: CGPoint(x: 101, y: 208))
    p.addCurve(to: CGPoint(x: 106, y: 167), control1: CGPoint(x: 113, y: 203), control2: CGPoint(x: 105, y: 182))
    p.addQuadCurve(to: CGPoint(x: 114, y: 133), control: CGPoint(x: 106, y: 145))
  }
  static let palatineCut = Path { p in
    p.move(to: CGPoint(x: 36, y: 135))
    p.addQuadCurve(to: CGPoint(x: 84, y: 134), control: CGPoint(x: 62, y: 125))
    p.addCurve(to: CGPoint(x: 83, y: 178), control1: CGPoint(x: 89, y: 156), control2: CGPoint(x: 92, y: 165))
    p.addQuadCurve(to: CGPoint(x: 94, y: 182), control: CGPoint(x: 81, y: 186))
    p.addCurve(to: CGPoint(x: 106, y: 207), control1: CGPoint(x: 95, y: 195), control2: CGPoint(x: 101, y: 208))
    p.addCurve(to: CGPoint(x: 106, y: 167), control1: CGPoint(x: 113, y: 203), control2: CGPoint(x: 105, y: 182))
    p.addQuadCurve(to: CGPoint(x: 114, y: 133), control: CGPoint(x: 106, y: 145))
    p.addQuadCurve(to: CGPoint(x: 154, y: 136), control: CGPoint(x: 134, y: 124))
    p.addCurve(to: CGPoint(x: 102, y: 248), control1: CGPoint(x: 173, y: 191), control2: CGPoint(x: 150, y: 244))
    p.addCurve(to: CGPoint(x: 36, y: 135), control1: CGPoint(x: 57, y: 252), control2: CGPoint(x: 22, y: 207))
    p.closeSubpath()
  }
  static let folds = Path { p in
    p.move(to: CGPoint(x: 199, y: 135))
    p.addQuadCurve(to: CGPoint(x: 230, y: 131), control: CGPoint(x: 216, y: 110))
    p.addQuadCurve(to: CGPoint(x: 243, y: 137), control: CGPoint(x: 236, y: 146))
    p.addQuadCurve(to: CGPoint(x: 269, y: 128), control: CGPoint(x: 255, y: 109))
    p.addQuadCurve(to: CGPoint(x: 283, y: 138), control: CGPoint(x: 273, y: 142))
    p.addQuadCurve(to: CGPoint(x: 314, y: 133), control: CGPoint(x: 301, y: 114))
    p.addQuadCurve(to: CGPoint(x: 325, y: 141), control: CGPoint(x: 319, y: 141))
  }
  static let adenoidCut = Path { p in
    p.move(to: CGPoint(x: 199, y: 135))
    p.addQuadCurve(to: CGPoint(x: 230, y: 131), control: CGPoint(x: 216, y: 110))
    p.addQuadCurve(to: CGPoint(x: 243, y: 137), control: CGPoint(x: 236, y: 146))
    p.addQuadCurve(to: CGPoint(x: 269, y: 128), control: CGPoint(x: 255, y: 109))
    p.addQuadCurve(to: CGPoint(x: 283, y: 138), control: CGPoint(x: 273, y: 142))
    p.addQuadCurve(to: CGPoint(x: 314, y: 133), control: CGPoint(x: 301, y: 114))
    p.addQuadCurve(to: CGPoint(x: 325, y: 141), control: CGPoint(x: 319, y: 141))
    p.addCurve(to: CGPoint(x: 298, y: 244), control1: CGPoint(x: 335, y: 186), control2: CGPoint(x: 346, y: 230))
    p.addCurve(to: CGPoint(x: 199, y: 135), control1: CGPoint(x: 242, y: 262), control2: CGPoint(x: 190, y: 229))
    p.closeSubpath()
  }
  static let cryptSurface = Path { p in
    p.move(to: CGPoint(x: 34, y: 116))
    p.addCurve(to: CGPoint(x: 143, y: 118), control1: CGPoint(x: 74, y: 98), control2: CGPoint(x: 127, y: 102))
    p.addCurve(to: CGPoint(x: 164, y: 201), control1: CGPoint(x: 157, y: 134), control2: CGPoint(x: 151, y: 177))
    p.addCurve(to: CGPoint(x: 202, y: 194), control1: CGPoint(x: 172, y: 221), control2: CGPoint(x: 192, y: 222))
    p.addCurve(to: CGPoint(x: 225, y: 115), control1: CGPoint(x: 213, y: 164), control2: CGPoint(x: 207, y: 124))
    p.addQuadCurve(to: CGPoint(x: 326, y: 111), control: CGPoint(x: 267, y: 93))
  }
  static let cryptSection = Path { p in
    p.move(to: CGPoint(x: 34, y: 116))
    p.addCurve(to: CGPoint(x: 143, y: 118), control1: CGPoint(x: 74, y: 98), control2: CGPoint(x: 127, y: 102))
    p.addCurve(to: CGPoint(x: 164, y: 201), control1: CGPoint(x: 157, y: 134), control2: CGPoint(x: 151, y: 177))
    p.addCurve(to: CGPoint(x: 202, y: 194), control1: CGPoint(x: 172, y: 221), control2: CGPoint(x: 192, y: 222))
    p.addCurve(to: CGPoint(x: 225, y: 115), control1: CGPoint(x: 213, y: 164), control2: CGPoint(x: 207, y: 124))
    p.addQuadCurve(to: CGPoint(x: 326, y: 111), control: CGPoint(x: 267, y: 93))
    p.addCurve(to: CGPoint(x: 299, y: 279), control1: CGPoint(x: 338, y: 182), control2: CGPoint(x: 331, y: 256))
    p.addCurve(to: CGPoint(x: 175, y: 296), control1: CGPoint(x: 272, y: 303), control2: CGPoint(x: 217, y: 303))
    p.addCurve(to: CGPoint(x: 52, y: 277), control1: CGPoint(x: 132, y: 300), control2: CGPoint(x: 83, y: 301))
    p.addCurve(to: CGPoint(x: 34, y: 116), control1: CGPoint(x: 26, y: 255), control2: CGPoint(x: 24, y: 170))
    p.closeSubpath()
  }
  static let epithelialSurface = Path { p in
    p.move(to: CGPoint(x: 29, y: 132))
    p.addCurve(to: CGPoint(x: 176, y: 151), control1: CGPoint(x: 84, y: 118), control2: CGPoint(x: 126, y: 147))
    p.addCurve(to: CGPoint(x: 330, y: 134), control1: CGPoint(x: 229, y: 156), control2: CGPoint(x: 259, y: 126))
  }
  static let localTissue = Path { p in
    p.move(to: CGPoint(x: 29, y: 132))
    p.addCurve(to: CGPoint(x: 176, y: 151), control1: CGPoint(x: 84, y: 118), control2: CGPoint(x: 126, y: 147))
    p.addCurve(to: CGPoint(x: 330, y: 134), control1: CGPoint(x: 229, y: 156), control2: CGPoint(x: 259, y: 126))
    p.addCurve(to: CGPoint(x: 308, y: 290), control1: CGPoint(x: 332, y: 212), control2: CGPoint(x: 338, y: 261))
    p.addCurve(to: CGPoint(x: 178, y: 303), control1: CGPoint(x: 274, y: 308), control2: CGPoint(x: 209, y: 299))
    p.addCurve(to: CGPoint(x: 49, y: 289), control1: CGPoint(x: 133, y: 298), control2: CGPoint(x: 83, y: 307))
    p.addCurve(to: CGPoint(x: 29, y: 132), control1: CGPoint(x: 24, y: 270), control2: CGPoint(x: 21, y: 208))
    p.closeSubpath()
  }
  static func presenter(_ tip: Double) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 105, y: 223))
    p.addQuadCurve(to: CGPoint(x: 90, y: 205), control: CGPoint(x: 95, y: 216))
    p.move(to: CGPoint(x: 115, y: 213))
    p.addQuadCurve(to: CGPoint(x: 114, y: 187), control: CGPoint(x: 111, y: 201))
    p.move(to: CGPoint(x: 132, y: 215))
    p.addQuadCurve(to: CGPoint(x: 151, y: 198), control: CGPoint(x: 145, y: 208))
    p.move(to: CGPoint(x: 108, y: 234))
    p.addQuadCurve(to: CGPoint(x: 92, y: 243), control: CGPoint(x: 98, y: 243))
    p.move(to: CGPoint(x: 124, y: 238))
    p.addQuadCurve(to: CGPoint(x: 136, y: 259), control: CGPoint(x: 126, y: 253))
    p.move(to: CGPoint(x: 145, y: 231))
    p.addQuadCurve(to: CGPoint(x: 162, y: 244), control: CGPoint(x: 155, y: 234))
    p.move(to: CGPoint(x: 142, y: 222))
    p.addQuadCurve(to: CGPoint(x: tip, y: 225), control: CGPoint(x: 158, y: 215))
    return p
  }
}
