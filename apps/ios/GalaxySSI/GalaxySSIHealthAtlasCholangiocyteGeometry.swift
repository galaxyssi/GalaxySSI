import SwiftUI

enum GalaxySSIHealthAtlasCholangiocyteGeometry {
  static let hepaticTissue = Path { p in
    p.move(to: CGPoint(x: 44, y: 111))
    p.addCurve(to: CGPoint(x: 150, y: 77), control1: CGPoint(x: 72, y: 82), control2: CGPoint(x: 111, y: 76))
    p.addCurve(to: CGPoint(x: 216, y: 94), control1: CGPoint(x: 178, y: 76), control2: CGPoint(x: 192, y: 96))
    p.addCurve(to: CGPoint(x: 315, y: 120), control1: CGPoint(x: 250, y: 88), control2: CGPoint(x: 302, y: 91))
    p.addCurve(to: CGPoint(x: 253, y: 184), control1: CGPoint(x: 330, y: 155), control2: CGPoint(x: 288, y: 178))
    p.addCurve(to: CGPoint(x: 180, y: 217), control1: CGPoint(x: 223, y: 189), control2: CGPoint(x: 209, y: 207))
    p.addCurve(to: CGPoint(x: 87, y: 244), control1: CGPoint(x: 143, y: 225), control2: CGPoint(x: 131, y: 247))
    p.addCurve(to: CGPoint(x: 32, y: 191), control1: CGPoint(x: 49, y: 242), control2: CGPoint(x: 31, y: 223))
    p.addCurve(to: CGPoint(x: 44, y: 111), control1: CGPoint(x: 27, y: 160), control2: CGPoint(x: 28, y: 129))
    p.closeSubpath()
  }
  static let hepaticVeils = Path { p in
    p.move(to: CGPoint(x: 46, y: 129))
    p.addCurve(to: CGPoint(x: 141, y: 91), control1: CGPoint(x: 73, y: 98), control2: CGPoint(x: 107, y: 95))
    p.move(to: CGPoint(x: 44, y: 144))
    p.addCurve(to: CGPoint(x: 124, y: 111), control1: CGPoint(x: 69, y: 117), control2: CGPoint(x: 104, y: 110))
    p.move(to: CGPoint(x: 46, y: 210))
    p.addCurve(to: CGPoint(x: 127, y: 215), control1: CGPoint(x: 66, y: 228), control2: CGPoint(x: 103, y: 226))
    p.move(to: CGPoint(x: 50, y: 221))
    p.addCurve(to: CGPoint(x: 141, y: 218), control1: CGPoint(x: 74, y: 238), control2: CGPoint(x: 111, y: 235))
    p.move(to: CGPoint(x: 149, y: 96))
    p.addCurve(to: CGPoint(x: 196, y: 107), control1: CGPoint(x: 174, y: 101), control2: CGPoint(x: 185, y: 114))
    p.move(to: CGPoint(x: 264, y: 101))
    p.addCurve(to: CGPoint(x: 306, y: 121), control1: CGPoint(x: 286, y: 101), control2: CGPoint(x: 303, y: 108))
    p.move(to: CGPoint(x: 296, y: 149))
    p.addCurve(to: CGPoint(x: 210, y: 191), control1: CGPoint(x: 278, y: 176), control2: CGPoint(x: 232, y: 171))
    p.move(to: CGPoint(x: 272, y: 163))
    p.addCurve(to: CGPoint(x: 219, y: 179), control1: CGPoint(x: 246, y: 168), control2: CGPoint(x: 233, y: 168))
  }
  static let ductTwigs = Path { p in
    p.move(to: CGPoint(x: 63, y: 130))
    p.addQuadCurve(to: CGPoint(x: 91, y: 145), control: CGPoint(x: 79, y: 139))
    p.move(to: CGPoint(x: 89, y: 112))
    p.addQuadCurve(to: CGPoint(x: 105, y: 150), control: CGPoint(x: 100, y: 129))
    p.move(to: CGPoint(x: 125, y: 116))
    p.addQuadCurve(to: CGPoint(x: 121, y: 155), control: CGPoint(x: 128, y: 138))
    p.move(to: CGPoint(x: 64, y: 184))
    p.addQuadCurve(to: CGPoint(x: 116, y: 180), control: CGPoint(x: 91, y: 192))
    p.move(to: CGPoint(x: 78, y: 206))
    p.addQuadCurve(to: CGPoint(x: 105, y: 185), control: CGPoint(x: 92, y: 192))
    p.move(to: CGPoint(x: 134, y: 201))
    p.addQuadCurve(to: CGPoint(x: 144, y: 167), control: CGPoint(x: 137, y: 182))
    p.move(to: CGPoint(x: 225, y: 115))
    p.addQuadCurve(to: CGPoint(x: 215, y: 140), control: CGPoint(x: 222, y: 127))
    p.move(to: CGPoint(x: 264, y: 145))
    p.addQuadCurve(to: CGPoint(x: 229, y: 134), control: CGPoint(x: 243, y: 134))
    p.move(to: CGPoint(x: 208, y: 167))
    p.addQuadCurve(to: CGPoint(x: 188, y: 155), control: CGPoint(x: 202, y: 156))
  }
  static let smallDucts = Path { p in
    p.move(to: CGPoint(x: 83, y: 141))
    p.addCurve(to: CGPoint(x: 157, y: 174), control1: CGPoint(x: 114, y: 152), control2: CGPoint(x: 147, y: 159))
    p.move(to: CGPoint(x: 107, y: 183))
    p.addQuadCurve(to: CGPoint(x: 145, y: 168), control: CGPoint(x: 126, y: 174))
    p.move(to: CGPoint(x: 278, y: 121))
    p.addCurve(to: CGPoint(x: 229, y: 134), control1: CGPoint(x: 257, y: 124), control2: CGPoint(x: 241, y: 129))
    p.addCurve(to: CGPoint(x: 157, y: 174), control1: CGPoint(x: 201, y: 144), control2: CGPoint(x: 173, y: 157))
  }
  static let trunk = Path { p in
    p.move(to: CGPoint(x: 157, y: 174))
    p.addCurve(to: CGPoint(x: 198, y: 252), control1: CGPoint(x: 170, y: 193), control2: CGPoint(x: 172, y: 220))
    p.addQuadCurve(to: CGPoint(x: 220, y: 283), control: CGPoint(x: 205, y: 267))
  }
  static let openLumen = Path { p in
    p.move(to: CGPoint(x: 55, y: 130))
    p.addCurve(to: CGPoint(x: 302, y: 132), control1: CGPoint(x: 112, y: 127), control2: CGPoint(x: 243, y: 128))
    p.addCurve(to: CGPoint(x: 306, y: 210), control1: CGPoint(x: 331, y: 143), control2: CGPoint(x: 333, y: 192))
    p.addCurve(to: CGPoint(x: 55, y: 211), control1: CGPoint(x: 252, y: 221), control2: CGPoint(x: 124, y: 217))
    p.addCurve(to: CGPoint(x: 55, y: 130), control1: CGPoint(x: 28, y: 202), control2: CGPoint(x: 28, y: 147))
    p.closeSubpath()
  }
  static let wallFloor = Path { p in
    p.move(to: CGPoint(x: 48, y: 243))
    p.addCurve(to: CGPoint(x: 311, y: 240), control1: CGPoint(x: 127, y: 239), control2: CGPoint(x: 215, y: 248))
    p.addLine(to: CGPoint(x: 314, y: 273))
    p.addCurve(to: CGPoint(x: 49, y: 278), control1: CGPoint(x: 227, y: 284), control2: CGPoint(x: 148, y: 264))
    p.addQuadCurve(to: CGPoint(x: 48, y: 243), control: CGPoint(x: 29, y: 268))
    p.closeSubpath()
  }
  static let cellShape = Path { p in
    p.move(to: CGPoint(x: 1, y: 5))
    p.addCurve(to: CGPoint(x: 59, y: 5), control1: CGPoint(x: 13, y: -1), control2: CGPoint(x: 48, y: -1))
    p.addCurve(to: CGPoint(x: 59, y: 49), control1: CGPoint(x: 62, y: 23), control2: CGPoint(x: 57, y: 31))
    p.addCurve(to: CGPoint(x: 52, y: 93), control1: CGPoint(x: 58, y: 69), control2: CGPoint(x: 63, y: 92))
    p.addCurve(to: CGPoint(x: 7, y: 91), control1: CGPoint(x: 43, y: 95), control2: CGPoint(x: 14, y: 96))
    p.addCurve(to: CGPoint(x: 0, y: 52), control1: CGPoint(x: -1, y: 85), control2: CGPoint(x: 1, y: 69))
    p.addCurve(to: CGPoint(x: 1, y: 5), control1: CGPoint(x: 2, y: 33), control2: CGPoint(x: -2, y: 18))
    p.closeSubpath()
  }
  static let cellRelief = Path { p in
    p.move(to: CGPoint(x: 5, y: 19))
    p.addCurve(to: CGPoint(x: 54, y: 17), control1: CGPoint(x: 13, y: 13), control2: CGPoint(x: 42, y: 13))
    p.move(to: CGPoint(x: 7, y: 25))
    p.addQuadCurve(to: CGPoint(x: 28, y: 21), control: CGPoint(x: 16, y: 19))
    p.move(to: CGPoint(x: 13, y: 42))
    p.addQuadCurve(to: CGPoint(x: 29, y: 37), control: CGPoint(x: 17, y: 35))
    p.move(to: CGPoint(x: 40, y: 35))
    p.addQuadCurve(to: CGPoint(x: 50, y: 43), control: CGPoint(x: 50, y: 35))
    p.move(to: CGPoint(x: 9, y: 76))
    p.addQuadCurve(to: CGPoint(x: 24, y: 82), control: CGPoint(x: 17, y: 82))
  }
  static let closeField = Path { p in
    p.move(to: CGPoint(x: 44, y: 97))
    p.addCurve(to: CGPoint(x: 307, y: 99), control1: CGPoint(x: 130, y: 85), control2: CGPoint(x: 224, y: 93))
    p.addQuadCurve(to: CGPoint(x: 313, y: 148), control: CGPoint(x: 323, y: 106))
    p.addCurve(to: CGPoint(x: 45, y: 155), control1: CGPoint(x: 218, y: 161), control2: CGPoint(x: 123, y: 147))
    p.addQuadCurve(to: CGPoint(x: 44, y: 97), control: CGPoint(x: 33, y: 131))
    p.closeSubpath()
  }
  static let tissueField = Path { p in
    p.move(to: CGPoint(x: 44, y: 242))
    p.addCurve(to: CGPoint(x: 312, y: 238), control1: CGPoint(x: 106, y: 244), control2: CGPoint(x: 222, y: 247))
    p.addQuadCurve(to: CGPoint(x: 308, y: 282), control: CGPoint(x: 321, y: 259))
    p.addCurve(to: CGPoint(x: 54, y: 287), control1: CGPoint(x: 233, y: 299), control2: CGPoint(x: 145, y: 272))
    p.addQuadCurve(to: CGPoint(x: 44, y: 242), control: CGPoint(x: 34, y: 279))
    p.closeSubpath()
  }
  static let fibers = Path { p in
    p.move(to: CGPoint(x: 52, y: 270))
    p.addCurve(to: CGPoint(x: 168, y: 269), control1: CGPoint(x: 106, y: 258), control2: CGPoint(x: 141, y: 269))
    p.move(to: CGPoint(x: 59, y: 277))
    p.addQuadCurve(to: CGPoint(x: 144, y: 274), control: CGPoint(x: 100, y: 268))
    p.move(to: CGPoint(x: 237, y: 268))
    p.addQuadCurve(to: CGPoint(x: 309, y: 260), control: CGPoint(x: 275, y: 272))
    p.move(to: CGPoint(x: 242, y: 275))
    p.addQuadCurve(to: CGPoint(x: 303, y: 269), control: CGPoint(x: 273, y: 284))
  }
  static let bicarbonateCourse = Path { p in
    p.move(to: CGPoint(x: 151, y: 197))
    p.addCurve(to: CGPoint(x: 171, y: 154), control1: CGPoint(x: 156, y: 183), control2: CGPoint(x: 171, y: 172))
    p.addCurve(to: CGPoint(x: 116, y: 108), control1: CGPoint(x: 169, y: 134), control2: CGPoint(x: 145, y: 122))
  }
  static let chlorideCourse = Path { p in
    p.move(to: CGPoint(x: 245, y: 108))
    p.addCurve(to: CGPoint(x: 187, y: 154), control1: CGPoint(x: 214, y: 119), control2: CGPoint(x: 187, y: 134))
    p.addCurve(to: CGPoint(x: 211, y: 205), control1: CGPoint(x: 186, y: 173), control2: CGPoint(x: 205, y: 182))
  }
  static let exchangerLeft = Path { p in
    p.move(to: CGPoint(x: 161, y: 147))
    p.addCurve(to: CGPoint(x: 161, y: 161), control1: CGPoint(x: 167, y: 150), control2: CGPoint(x: 165, y: 157))
  }
  static let exchangerMiddle = Path { p in
    p.move(to: CGPoint(x: 179, y: 146))
    p.addCurve(to: CGPoint(x: 179, y: 162), control1: CGPoint(x: 175, y: 150), control2: CGPoint(x: 182, y: 156))
  }
  static let exchangerRight = Path { p in
    p.move(to: CGPoint(x: 196, y: 147))
    p.addCurve(to: CGPoint(x: 198, y: 161), control1: CGPoint(x: 191, y: 151), control2: CGPoint(x: 194, y: 158))
  }
  static let waterCourse = Path { p in
    p.move(to: CGPoint(x: 173, y: 280))
    p.addCurve(to: CGPoint(x: 199, y: 246), control1: CGPoint(x: 185, y: 264), control2: CGPoint(x: 198, y: 261))
    p.addCurve(to: CGPoint(x: 215, y: 190), control1: CGPoint(x: 199, y: 222), control2: CGPoint(x: 219, y: 212))
    p.addCurve(to: CGPoint(x: 214, y: 153), control1: CGPoint(x: 212, y: 174), control2: CGPoint(x: 214, y: 165))
    p.addCurve(to: CGPoint(x: 278, y: 111), control1: CGPoint(x: 213, y: 127), control2: CGPoint(x: 239, y: 108))
  }
  static let bowel = Path { p in
    p.move(to: CGPoint(x: 242, y: 98))
    p.addCurve(to: CGPoint(x: 284, y: 209), control1: CGPoint(x: 284, y: 121), control2: CGPoint(x: 299, y: 157))
    p.addCurve(to: CGPoint(x: 192, y: 265), control1: CGPoint(x: 272, y: 250), control2: CGPoint(x: 237, y: 269))
  }
  static let folds = Path { p in
    p.move(to: CGPoint(x: 269, y: 98))
    p.addQuadCurve(to: CGPoint(x: 256, y: 113), control: CGPoint(x: 266, y: 109))
    p.move(to: CGPoint(x: 280, y: 108))
    p.addQuadCurve(to: CGPoint(x: 266, y: 123), control: CGPoint(x: 275, y: 120))
    p.move(to: CGPoint(x: 289, y: 120))
    p.addQuadCurve(to: CGPoint(x: 275, y: 134), control: CGPoint(x: 287, y: 131))
    p.move(to: CGPoint(x: 298, y: 135))
    p.addQuadCurve(to: CGPoint(x: 282, y: 147), control: CGPoint(x: 294, y: 146))
    p.move(to: CGPoint(x: 304, y: 151))
    p.addQuadCurve(to: CGPoint(x: 287, y: 161), control: CGPoint(x: 298, y: 159))
    p.move(to: CGPoint(x: 306, y: 169))
    p.addQuadCurve(to: CGPoint(x: 290, y: 173), control: CGPoint(x: 299, y: 177))
    p.move(to: CGPoint(x: 304, y: 187))
    p.addQuadCurve(to: CGPoint(x: 289, y: 187), control: CGPoint(x: 298, y: 190))
    p.move(to: CGPoint(x: 300, y: 204))
    p.addQuadCurve(to: CGPoint(x: 284, y: 201), control: CGPoint(x: 295, y: 205))
    p.move(to: CGPoint(x: 296, y: 219))
    p.addQuadCurve(to: CGPoint(x: 280, y: 213), control: CGPoint(x: 285, y: 220))
    p.move(to: CGPoint(x: 287, y: 237))
    p.addQuadCurve(to: CGPoint(x: 273, y: 225), control: CGPoint(x: 276, y: 232))
    p.move(to: CGPoint(x: 277, y: 250))
    p.addQuadCurve(to: CGPoint(x: 264, y: 236), control: CGPoint(x: 267, y: 247))
    p.move(to: CGPoint(x: 263, y: 262))
    p.addQuadCurve(to: CGPoint(x: 253, y: 246), control: CGPoint(x: 254, y: 256))
    p.move(to: CGPoint(x: 245, y: 271))
    p.addQuadCurve(to: CGPoint(x: 239, y: 254), control: CGPoint(x: 237, y: 265))
    p.move(to: CGPoint(x: 226, y: 278))
    p.addQuadCurve(to: CGPoint(x: 223, y: 260), control: CGPoint(x: 219, y: 270))
    p.move(to: CGPoint(x: 209, y: 282))
    p.addQuadCurve(to: CGPoint(x: 207, y: 264), control: CGPoint(x: 204, y: 274))
  }
  static let outlet = Path { p in
    p.move(to: CGPoint(x: 57, y: 129))
    p.addCurve(to: CGPoint(x: 152, y: 140), control1: CGPoint(x: 106, y: 117), control2: CGPoint(x: 125, y: 132))
    p.addCurve(to: CGPoint(x: 267, y: 182), control1: CGPoint(x: 197, y: 155), control2: CGPoint(x: 227, y: 158))
  }
}
