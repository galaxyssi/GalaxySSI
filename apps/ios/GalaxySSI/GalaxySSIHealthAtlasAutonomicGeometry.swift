import SwiftUI

enum GalaxySSIHealthAtlasAutonomicGeometry {
  static let torso = Path { p in
    p.move(to: CGPoint(x: 146, y: 81))
    p.addCurve(to: CGPoint(x: 89, y: 119), control1: CGPoint(x: 149, y: 110), control2: CGPoint(x: 117, y: 104))
    p.addCurve(to: CGPoint(x: 64, y: 188), control1: CGPoint(x: 65, y: 132), control2: CGPoint(x: 59, y: 161))
    p.addCurve(to: CGPoint(x: 77, y: 309), control1: CGPoint(x: 72, y: 237), control2: CGPoint(x: 70, y: 277))
    p.addQuadCurve(to: CGPoint(x: 282, y: 309), control: CGPoint(x: 175, y: 337))
    p.addCurve(to: CGPoint(x: 294, y: 188), control1: CGPoint(x: 290, y: 272), control2: CGPoint(x: 286, y: 229))
    p.addCurve(to: CGPoint(x: 273, y: 121), control1: CGPoint(x: 300, y: 160), control2: CGPoint(x: 296, y: 135))
    p.addCurve(to: CGPoint(x: 210, y: 81), control1: CGPoint(x: 247, y: 108), control2: CGPoint(x: 210, y: 110))
    p.closeSubpath()
  }
  static let lung = Path { p in
    p.move(to: CGPoint(x: 151, y: 124))
    p.addCurve(to: CGPoint(x: 95, y: 169), control1: CGPoint(x: 132, y: 111), control2: CGPoint(x: 104, y: 134))
    p.addCurve(to: CGPoint(x: 91, y: 249), control1: CGPoint(x: 85, y: 196), control2: CGPoint(x: 86, y: 233))
    p.addCurve(to: CGPoint(x: 153, y: 246), control1: CGPoint(x: 100, y: 271), control2: CGPoint(x: 139, y: 270))
    p.addCurve(to: CGPoint(x: 154, y: 183), control1: CGPoint(x: 160, y: 221), control2: CGPoint(x: 147, y: 202))
    p.addCurve(to: CGPoint(x: 151, y: 124), control1: CGPoint(x: 160, y: 165), control2: CGPoint(x: 165, y: 136))
    p.closeSubpath()
  }
  static let brain = Path { p in
    p.move(to: CGPoint(x: 145, y: 75))
    p.addCurve(to: CGPoint(x: 142, y: 49), control1: CGPoint(x: 131, y: 68), control2: CGPoint(x: 130, y: 55))
    p.addCurve(to: CGPoint(x: 167, y: 40), control1: CGPoint(x: 143, y: 40), control2: CGPoint(x: 158, y: 36))
    p.addCurve(to: CGPoint(x: 191, y: 43), control1: CGPoint(x: 176, y: 33), control2: CGPoint(x: 188, y: 38))
    p.addCurve(to: CGPoint(x: 214, y: 62), control1: CGPoint(x: 207, y: 41), control2: CGPoint(x: 216, y: 50))
    p.addCurve(to: CGPoint(x: 195, y: 79), control1: CGPoint(x: 225, y: 76), control2: CGPoint(x: 208, y: 83))
    p.addCurve(to: CGPoint(x: 159, y: 77), control1: CGPoint(x: 179, y: 86), control2: CGPoint(x: 167, y: 83))
    p.addQuadCurve(to: CGPoint(x: 145, y: 75), control: CGPoint(x: 151, y: 80))
    p.closeSubpath()
  }
  static let folds = Path { p in
    p.move(to: CGPoint(x: 142, y: 59))
    p.addQuadCurve(to: CGPoint(x: 161, y: 56), control: CGPoint(x: 151, y: 51))
    p.addQuadCurve(to: CGPoint(x: 175, y: 49), control: CGPoint(x: 169, y: 61))
    p.move(to: CGPoint(x: 151, y: 69))
    p.addCurve(to: CGPoint(x: 174, y: 68), control1: CGPoint(x: 158, y: 63), control2: CGPoint(x: 165, y: 71))
    p.addQuadCurve(to: CGPoint(x: 185, y: 55), control: CGPoint(x: 186, y: 66))
    p.move(to: CGPoint(x: 187, y: 74))
    p.addQuadCurve(to: CGPoint(x: 208, y: 64), control: CGPoint(x: 196, y: 62))
    p.move(to: CGPoint(x: 194, y: 54))
    p.addQuadCurve(to: CGPoint(x: 208, y: 55), control: CGPoint(x: 202, y: 51))
  }
  static let cord = Path { p in
    p.move(to: CGPoint(x: 178, y: 71))
    p.addCurve(to: CGPoint(x: 174, y: 132), control1: CGPoint(x: 173, y: 90), control2: CGPoint(x: 175, y: 111))
    p.addCurve(to: CGPoint(x: 170, y: 224), control1: CGPoint(x: 173, y: 158), control2: CGPoint(x: 171, y: 193))
  }
  static let sympatheticTrunk = Path { p in
    p.move(to: CGPoint(x: 128, y: 116))
    p.addCurve(to: CGPoint(x: 120, y: 151), control1: CGPoint(x: 122, y: 130), control2: CGPoint(x: 119, y: 145))
    p.addQuadCurve(to: CGPoint(x: 115, y: 203), control: CGPoint(x: 115, y: 174))
  }
  static let heart = Path { p in
    p.move(to: CGPoint(x: 176, y: 218))
    p.addCurve(to: CGPoint(x: 142, y: 233), control1: CGPoint(x: 162, y: 208), control2: CGPoint(x: 143, y: 214))
    p.addCurve(to: CGPoint(x: 181, y: 276), control1: CGPoint(x: 139, y: 255), control2: CGPoint(x: 164, y: 266))
    p.addCurve(to: CGPoint(x: 225, y: 302), control1: CGPoint(x: 198, y: 286), control2: CGPoint(x: 213, y: 301))
    p.addCurve(to: CGPoint(x: 243, y: 242), control1: CGPoint(x: 239, y: 296), control2: CGPoint(x: 247, y: 264))
    p.addCurve(to: CGPoint(x: 211, y: 213), control1: CGPoint(x: 241, y: 217), control2: CGPoint(x: 224, y: 211))
    p.addCurve(to: CGPoint(x: 176, y: 218), control1: CGPoint(x: 196, y: 209), control2: CGPoint(x: 191, y: 222))
    p.closeSubpath()
  }
  static let venaCava = Path { p in
    p.move(to: CGPoint(x: 150, y: 188))
    p.addCurve(to: CGPoint(x: 160, y: 224), control1: CGPoint(x: 150, y: 204), control2: CGPoint(x: 155, y: 216))
  }
  static let aorta = Path { p in
    p.move(to: CGPoint(x: 188, y: 226))
    p.addCurve(to: CGPoint(x: 185, y: 184), control1: CGPoint(x: 185, y: 210), control2: CGPoint(x: 176, y: 194))
    p.addCurve(to: CGPoint(x: 216, y: 182), control1: CGPoint(x: 194, y: 173), control2: CGPoint(x: 209, y: 175))
  }
  static let pulmonaryTrunk = Path { p in
    p.move(to: CGPoint(x: 188, y: 227))
    p.addCurve(to: CGPoint(x: 224, y: 202), control1: CGPoint(x: 195, y: 218), control2: CGPoint(x: 204, y: 206))
  }
  static let heartDetail = Path { p in
    p.move(to: CGPoint(x: 145, y: 238))
    p.addCurve(to: CGPoint(x: 187, y: 230), control1: CGPoint(x: 161, y: 240), control2: CGPoint(x: 173, y: 229))
    p.addCurve(to: CGPoint(x: 225, y: 220), control1: CGPoint(x: 201, y: 229), control2: CGPoint(x: 212, y: 222))
    p.move(to: CGPoint(x: 188, y: 232))
    p.addCurve(to: CGPoint(x: 225, y: 295), control1: CGPoint(x: 192, y: 252), control2: CGPoint(x: 203, y: 275))
    p.move(to: CGPoint(x: 196, y: 251))
    p.addQuadCurve(to: CGPoint(x: 213, y: 260), control: CGPoint(x: 206, y: 253))
    p.move(to: CGPoint(x: 205, y: 270))
    p.addQuadCurve(to: CGPoint(x: 218, y: 277), control: CGPoint(x: 214, y: 271))
  }
}
