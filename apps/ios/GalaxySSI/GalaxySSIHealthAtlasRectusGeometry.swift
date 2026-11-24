import SwiftUI

enum GalaxySSIHealthAtlasRectusGeometry {
  static let wall = Path { p in
    p.move(to: CGPoint(x: 110, y: 73))
    p.addCurve(to: CGPoint(x: 200, y: 76), control1: CGPoint(x: 132, y: 55), control2: CGPoint(x: 177, y: 62))
    p.addCurve(to: CGPoint(x: 230, y: 144), control1: CGPoint(x: 224, y: 90), control2: CGPoint(x: 231, y: 116))
    p.addCurve(to: CGPoint(x: 224, y: 243), control1: CGPoint(x: 228, y: 175), control2: CGPoint(x: 237, y: 210))
    p.addQuadCurve(to: CGPoint(x: 215, y: 266), control: CGPoint(x: 222, y: 254))
    p.addQuadCurve(to: CGPoint(x: 111, y: 269), control: CGPoint(x: 155, y: 282))
    p.addCurve(to: CGPoint(x: 117, y: 174), control1: CGPoint(x: 105, y: 241), control2: CGPoint(x: 123, y: 206))
    p.addCurve(to: CGPoint(x: 98, y: 111), control1: CGPoint(x: 115, y: 153), control2: CGPoint(x: 100, y: 134))
    p.addQuadCurve(to: CGPoint(x: 110, y: 73), control: CGPoint(x: 95, y: 88))
    p.closeSubpath()
  }
  static let ribCage = Path { p in
    p.move(to: CGPoint(x: 111, y: 87))
    p.addCurve(to: CGPoint(x: 212, y: 100), control1: CGPoint(x: 139, y: 70), control2: CGPoint(x: 191, y: 78))
    p.addQuadCurve(to: CGPoint(x: 218, y: 141), control: CGPoint(x: 224, y: 114))
    p.addCurve(to: CGPoint(x: 163, y: 156), control1: CGPoint(x: 192, y: 151), control2: CGPoint(x: 180, y: 139))
    p.addQuadCurve(to: CGPoint(x: 119, y: 151), control: CGPoint(x: 130, y: 175))
    p.addCurve(to: CGPoint(x: 111, y: 87), control1: CGPoint(x: 106, y: 132), control2: CGPoint(x: 99, y: 103))
    p.closeSubpath()
  }
  static let ribLines = Path { p in
    p.move(to: CGPoint(x: 108, y: 97))
    p.addCurve(to: CGPoint(x: 215, y: 110), control1: CGPoint(x: 143, y: 89), control2: CGPoint(x: 185, y: 114))
    p.move(to: CGPoint(x: 106, y: 108))
    p.addCurve(to: CGPoint(x: 218, y: 121), control1: CGPoint(x: 145, y: 102), control2: CGPoint(x: 184, y: 125))
    p.move(to: CGPoint(x: 108, y: 119))
    p.addCurve(to: CGPoint(x: 219, y: 132), control1: CGPoint(x: 146, y: 115), control2: CGPoint(x: 184, y: 136))
    p.move(to: CGPoint(x: 112, y: 130))
    p.addCurve(to: CGPoint(x: 218, y: 141), control1: CGPoint(x: 148, y: 126), control2: CGPoint(x: 183, y: 146))
    p.move(to: CGPoint(x: 116, y: 142))
    p.addCurve(to: CGPoint(x: 194, y: 147), control1: CGPoint(x: 145, y: 139), control2: CGPoint(x: 173, y: 150))
    p.move(to: CGPoint(x: 121, y: 153))
    p.addQuadCurve(to: CGPoint(x: 174, y: 152), control: CGPoint(x: 150, y: 147))
  }
  static let cartilage = Path { p in
    p.move(to: CGPoint(x: 217, y: 116))
    p.addQuadCurve(to: CGPoint(x: 220, y: 138), control: CGPoint(x: 224, y: 128))
    p.addQuadCurve(to: CGPoint(x: 199, y: 152), control: CGPoint(x: 215, y: 147))
    p.addQuadCurve(to: CGPoint(x: 210, y: 136), control: CGPoint(x: 202, y: 144))
    p.addQuadCurve(to: CGPoint(x: 217, y: 116), control: CGPoint(x: 216, y: 130))
    p.closeSubpath()
  }
  static let spine = Path { p in
    p.move(to: CGPoint(x: 123, y: 148))
    p.addCurve(to: CGPoint(x: 139, y: 237), control1: CGPoint(x: 124, y: 180), control2: CGPoint(x: 145, y: 204))
    p.addQuadCurve(to: CGPoint(x: 128, y: 269), control: CGPoint(x: 136, y: 251))
    p.addLine(to: CGPoint(x: 140, y: 273))
    p.addCurve(to: CGPoint(x: 154, y: 206), control1: CGPoint(x: 153, y: 253), control2: CGPoint(x: 160, y: 232))
    p.addCurve(to: CGPoint(x: 140, y: 149), control1: CGPoint(x: 149, y: 183), control2: CGPoint(x: 141, y: 164))
    p.closeSubpath()
  }
  static let discs = Path { p in
    p.move(to: CGPoint(x: 126, y: 169))
    p.addLine(to: CGPoint(x: 143, y: 167))
    p.move(to: CGPoint(x: 133, y: 189))
    p.addLine(to: CGPoint(x: 148, y: 186))
    p.move(to: CGPoint(x: 139, y: 210))
    p.addLine(to: CGPoint(x: 155, y: 207))
    p.move(to: CGPoint(x: 139, y: 231))
    p.addLine(to: CGPoint(x: 155, y: 232))
    p.move(to: CGPoint(x: 135, y: 251))
    p.addLine(to: CGPoint(x: 150, y: 255))
  }
  static let pelvis = Path { p in
    p.move(to: CGPoint(x: 118, y: 245))
    p.addCurve(to: CGPoint(x: 184, y: 247), control1: CGPoint(x: 138, y: 233), control2: CGPoint(x: 166, y: 236))
    p.addCurve(to: CGPoint(x: 205, y: 258), control1: CGPoint(x: 193, y: 252), control2: CGPoint(x: 196, y: 260))
    p.addQuadCurve(to: CGPoint(x: 221, y: 265), control: CGPoint(x: 219, y: 253))
    p.addCurve(to: CGPoint(x: 190, y: 290), control1: CGPoint(x: 220, y: 276), control2: CGPoint(x: 201, y: 281))
    p.addQuadCurve(to: CGPoint(x: 140, y: 299), control: CGPoint(x: 169, y: 310))
    p.addCurve(to: CGPoint(x: 113, y: 265), control1: CGPoint(x: 124, y: 293), control2: CGPoint(x: 119, y: 277))
    p.addQuadCurve(to: CGPoint(x: 118, y: 245), control: CGPoint(x: 108, y: 251))
    p.closeSubpath()
  }
  static let pelvicDetail = Path { p in
    p.move(to: CGPoint(x: 121, y: 250))
    p.addCurve(to: CGPoint(x: 181, y: 252), control1: CGPoint(x: 141, y: 241), control2: CGPoint(x: 165, y: 243))
    p.move(to: CGPoint(x: 143, y: 280))
    p.addCurve(to: CGPoint(x: 181, y: 280), control1: CGPoint(x: 150, y: 289), control2: CGPoint(x: 168, y: 290))
    p.move(to: CGPoint(x: 207, y: 259))
    p.addQuadCurve(to: CGPoint(x: 211, y: 271), control: CGPoint(x: 212, y: 263))
  }
  static let rectus = Path { p in
    p.move(to: CGPoint(x: 211, y: 138))
    p.addQuadCurve(to: CGPoint(x: 224, y: 136), control: CGPoint(x: 216, y: 137))
    p.addCurve(to: CGPoint(x: 226, y: 201), control1: CGPoint(x: 226, y: 155), control2: CGPoint(x: 227, y: 184))
    p.addCurve(to: CGPoint(x: 214, y: 260), control1: CGPoint(x: 225, y: 227), control2: CGPoint(x: 219, y: 245))
    p.addLine(to: CGPoint(x: 205, y: 260))
    p.addCurve(to: CGPoint(x: 209, y: 201), control1: CGPoint(x: 206, y: 239), control2: CGPoint(x: 210, y: 221))
    p.addCurve(to: CGPoint(x: 211, y: 138), control1: CGPoint(x: 210, y: 176), control2: CGPoint(x: 208, y: 156))
    p.closeSubpath()
  }
  static let intersections = Path { p in
    p.move(to: CGPoint(x: 210, y: 166))
    p.addQuadCurve(to: CGPoint(x: 225, y: 165), control: CGPoint(x: 217, y: 169))
    p.move(to: CGPoint(x: 210, y: 198))
    p.addQuadCurve(to: CGPoint(x: 226, y: 196), control: CGPoint(x: 217, y: 201))
    p.move(to: CGPoint(x: 208, y: 228))
    p.addQuadCurve(to: CGPoint(x: 221, y: 225), control: CGPoint(x: 215, y: 230))
  }
  static let fascicles = Path { p in
    p.move(to: CGPoint(x: 215, y: 143))
    p.addQuadCurve(to: CGPoint(x: 215, y: 165), control: CGPoint(x: 213, y: 157))
    p.move(to: CGPoint(x: 220, y: 141))
    p.addQuadCurve(to: CGPoint(x: 222, y: 165), control: CGPoint(x: 220, y: 154))
    p.move(to: CGPoint(x: 215, y: 169))
    p.addQuadCurve(to: CGPoint(x: 215, y: 196), control: CGPoint(x: 214, y: 181))
    p.move(to: CGPoint(x: 221, y: 169))
    p.addQuadCurve(to: CGPoint(x: 221, y: 196), control: CGPoint(x: 223, y: 185))
    p.move(to: CGPoint(x: 214, y: 201))
    p.addQuadCurve(to: CGPoint(x: 212, y: 226), control: CGPoint(x: 214, y: 217))
    p.move(to: CGPoint(x: 221, y: 201))
    p.addQuadCurve(to: CGPoint(x: 217, y: 226), control: CGPoint(x: 220, y: 217))
    p.move(to: CGPoint(x: 215, y: 231))
    p.addQuadCurve(to: CGPoint(x: 210, y: 255), control: CGPoint(x: 212, y: 246))
  }
}
