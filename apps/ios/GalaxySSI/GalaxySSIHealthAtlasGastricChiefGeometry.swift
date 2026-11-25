import SwiftUI

enum GalaxySSIHealthAtlasGastricChiefGeometry {
  static let stomach = Path { p in
    p.move(to: CGPoint(x: 54, y: 92))
    p.addQuadCurve(to: CGPoint(x: 72, y: 91), control: CGPoint(x: 62, y: 87))
    p.addCurve(to: CGPoint(x: 81, y: 126), control1: CGPoint(x: 71, y: 111), control2: CGPoint(x: 75, y: 127))
    p.addCurve(to: CGPoint(x: 134, y: 125), control1: CGPoint(x: 96, y: 108), control2: CGPoint(x: 120, y: 110))
    p.addCurve(to: CGPoint(x: 120, y: 232), control1: CGPoint(x: 159, y: 154), control2: CGPoint(x: 145, y: 209))
    p.addCurve(to: CGPoint(x: 43, y: 227), control1: CGPoint(x: 89, y: 259), control2: CGPoint(x: 58, y: 243))
    p.addQuadCurve(to: CGPoint(x: 16, y: 222), control: CGPoint(x: 29, y: 211))
    p.addLine(to: CGPoint(x: 17, y: 204))
    p.addQuadCurve(to: CGPoint(x: 37, y: 196), control: CGPoint(x: 29, y: 207))
    p.addCurve(to: CGPoint(x: 54, y: 148), control1: CGPoint(x: 46, y: 181), control2: CGPoint(x: 46, y: 166))
    p.addCurve(to: CGPoint(x: 54, y: 92), control1: CGPoint(x: 61, y: 132), control2: CGPoint(x: 57, y: 111))
    p.closeSubpath()
  }
  static let stomachFolds = Path { p in
    p.move(to: CGPoint(x: 93, y: 138))
    p.addCurve(to: CGPoint(x: 132, y: 170), control1: CGPoint(x: 117, y: 123), control2: CGPoint(x: 136, y: 148))
    p.move(to: CGPoint(x: 74, y: 153))
    p.addCurve(to: CGPoint(x: 113, y: 205), control1: CGPoint(x: 104, y: 123), control2: CGPoint(x: 134, y: 174))
    p.move(to: CGPoint(x: 65, y: 173))
    p.addCurve(to: CGPoint(x: 91, y: 221), control1: CGPoint(x: 94, y: 153), control2: CGPoint(x: 117, y: 194))
    p.move(to: CGPoint(x: 54, y: 193))
    p.addCurve(to: CGPoint(x: 73, y: 223), control1: CGPoint(x: 76, y: 178), control2: CGPoint(x: 92, y: 207))
  }
  static let glandWall = Path { p in
    p.move(to: CGPoint(x: 169, y: 90))
    p.addQuadCurve(to: CGPoint(x: 223, y: 86), control: CGPoint(x: 199, y: 77))
    p.addCurve(to: CGPoint(x: 251, y: 110), control1: CGPoint(x: 235, y: 89), control2: CGPoint(x: 231, y: 110))
    p.addCurve(to: CGPoint(x: 278, y: 83), control1: CGPoint(x: 268, y: 110), control2: CGPoint(x: 261, y: 86))
    p.addQuadCurve(to: CGPoint(x: 335, y: 89), control: CGPoint(x: 305, y: 78))
    p.addLine(to: CGPoint(x: 335, y: 243))
    p.addCurve(to: CGPoint(x: 249, y: 301), control1: CGPoint(x: 328, y: 284), control2: CGPoint(x: 289, y: 307))
    p.addCurve(to: CGPoint(x: 169, y: 215), control1: CGPoint(x: 193, y: 300), control2: CGPoint(x: 169, y: 257))
    p.closeSubpath()
  }
  static let glandLumen = Path { p in
    p.move(to: CGPoint(x: 221, y: 85))
    p.addCurve(to: CGPoint(x: 245, y: 123), control1: CGPoint(x: 232, y: 84), control2: CGPoint(x: 232, y: 113))
    p.addCurve(to: CGPoint(x: 243, y: 169), control1: CGPoint(x: 252, y: 135), control2: CGPoint(x: 241, y: 148))
    p.addCurve(to: CGPoint(x: 235, y: 245), control1: CGPoint(x: 245, y: 192), control2: CGPoint(x: 234, y: 218))
    p.addCurve(to: CGPoint(x: 249, y: 279), control1: CGPoint(x: 233, y: 264), control2: CGPoint(x: 240, y: 280))
    p.addCurve(to: CGPoint(x: 255, y: 240), control1: CGPoint(x: 261, y: 278), control2: CGPoint(x: 263, y: 262))
    p.addCurve(to: CGPoint(x: 259, y: 169), control1: CGPoint(x: 251, y: 213), control2: CGPoint(x: 261, y: 193))
    p.addCurve(to: CGPoint(x: 263, y: 126), control1: CGPoint(x: 257, y: 150), control2: CGPoint(x: 259, y: 140))
    p.addCurve(to: CGPoint(x: 280, y: 83), control1: CGPoint(x: 274, y: 113), control2: CGPoint(x: 263, y: 89))
  }
  static let glandEpithelialCell = Path { p in
    p.move(to: CGPoint(x: -23, y: -10))
    p.addQuadCurve(to: CGPoint(x: 20, y: -10), control: CGPoint(x: -8, y: -17))
    p.addQuadCurve(to: CGPoint(x: 18, y: 11), control: CGPoint(x: 25, y: 0))
    p.addQuadCurve(to: CGPoint(x: -24, y: 9), control: CGPoint(x: -8, y: 16))
    p.addQuadCurve(to: CGPoint(x: -23, y: -10), control: CGPoint(x: -28, y: 0))
    p.closeSubpath()
  }
  static let closeLumen = Path { p in
    p.move(to: CGPoint(x: 216, y: 69))
    p.addQuadCurve(to: CGPoint(x: 301, y: 68), control: CGPoint(x: 258, y: 77))
    p.addCurve(to: CGPoint(x: 297, y: 279), control1: CGPoint(x: 325, y: 102), control2: CGPoint(x: 327, y: 243))
    p.addQuadCurve(to: CGPoint(x: 215, y: 279), control: CGPoint(x: 256, y: 290))
    p.closeSubpath()
  }
  static let chief = Path { p in
    p.move(to: CGPoint(x: 43, y: 136))
    p.addCurve(to: CGPoint(x: 139, y: 100), control1: CGPoint(x: 51, y: 105), control2: CGPoint(x: 94, y: 100))
    p.addQuadCurve(to: CGPoint(x: 214, y: 117), control: CGPoint(x: 192, y: 101))
    p.addCurve(to: CGPoint(x: 226, y: 177), control1: CGPoint(x: 228, y: 128), control2: CGPoint(x: 227, y: 150))
    p.addLine(to: CGPoint(x: 226, y: 210))
    p.addQuadCurve(to: CGPoint(x: 211, y: 250), control: CGPoint(x: 229, y: 239))
    p.addCurve(to: CGPoint(x: 55, y: 241), control1: CGPoint(x: 175, y: 272), control2: CGPoint(x: 81, y: 266))
    p.addCurve(to: CGPoint(x: 43, y: 136), control1: CGPoint(x: 34, y: 222), control2: CGPoint(x: 34, y: 163))
    p.closeSubpath()
  }
  static let lumenWall = Path { p in
    p.move(to: CGPoint(x: 301, y: 70))
    p.addCurve(to: CGPoint(x: 289, y: 146), control1: CGPoint(x: 285, y: 96), control2: CGPoint(x: 296, y: 118))
    p.addCurve(to: CGPoint(x: 290, y: 253), control1: CGPoint(x: 282, y: 179), control2: CGPoint(x: 300, y: 218))
    p.addQuadCurve(to: CGPoint(x: 297, y: 279), control: CGPoint(x: 286, y: 270))
    p.addCurve(to: CGPoint(x: 337, y: 189), control1: CGPoint(x: 330, y: 265), control2: CGPoint(x: 344, y: 232))
    p.addCurve(to: CGPoint(x: 326, y: 79), control1: CGPoint(x: 331, y: 143), control2: CGPoint(x: 345, y: 103))
    p.closeSubpath()
  }
  static let rER = Path { p in
    p.move(to: CGPoint(x: 80, y: 143))
    p.addCurve(to: CGPoint(x: 141, y: 146), control1: CGPoint(x: 94, y: 129), control2: CGPoint(x: 127, y: 130))
    p.move(to: CGPoint(x: 88, y: 154))
    p.addCurve(to: CGPoint(x: 147, y: 159), control1: CGPoint(x: 107, y: 140), control2: CGPoint(x: 133, y: 144))
    p.move(to: CGPoint(x: 121, y: 159))
    p.addCurve(to: CGPoint(x: 147, y: 199), control1: CGPoint(x: 138, y: 162), control2: CGPoint(x: 155, y: 177))
    p.move(to: CGPoint(x: 137, y: 162))
    p.addCurve(to: CGPoint(x: 155, y: 210), control1: CGPoint(x: 165, y: 172), control2: CGPoint(x: 163, y: 196))
    p.move(to: CGPoint(x: 139, y: 210))
    p.addCurve(to: CGPoint(x: 79, y: 228), control1: CGPoint(x: 133, y: 228), control2: CGPoint(x: 100, y: 241))
    p.move(to: CGPoint(x: 144, y: 224))
    p.addCurve(to: CGPoint(x: 82, y: 241), control1: CGPoint(x: 125, y: 244), control2: CGPoint(x: 96, y: 250))
  }
  static let fusionPore = Path { p in
    p.move(to: CGPoint(x: 226, y: 184))
    p.addCurve(to: CGPoint(x: 215, y: 195), control1: CGPoint(x: 225, y: 189), control2: CGPoint(x: 215, y: 186))
    p.addCurve(to: CGPoint(x: 226, y: 206), control1: CGPoint(x: 215, y: 204), control2: CGPoint(x: 225, y: 201))
  }
  static let glandSection = Path { p in
    p.move(to: CGPoint(x: 35, y: 78))
    p.addQuadCurve(to: CGPoint(x: 125, y: 81), control: CGPoint(x: 104, y: 66))
    p.addQuadCurve(to: CGPoint(x: 233, y: 81), control: CGPoint(x: 174, y: 94))
    p.addQuadCurve(to: CGPoint(x: 325, y: 80), control: CGPoint(x: 284, y: 66))
    p.addCurve(to: CGPoint(x: 328, y: 220), control1: CGPoint(x: 340, y: 120), control2: CGPoint(x: 319, y: 171))
    p.addQuadCurve(to: CGPoint(x: 295, y: 281), control: CGPoint(x: 338, y: 270))
    p.addQuadCurve(to: CGPoint(x: 229, y: 276), control: CGPoint(x: 253, y: 288))
    p.addQuadCurve(to: CGPoint(x: 127, y: 279), control: CGPoint(x: 174, y: 265))
    p.addQuadCurve(to: CGPoint(x: 37, y: 275), control: CGPoint(x: 69, y: 292))
    p.addCurve(to: CGPoint(x: 27, y: 157), control1: CGPoint(x: 22, y: 240), control2: CGPoint(x: 37, y: 198))
    p.addQuadCurve(to: CGPoint(x: 35, y: 78), control: CGPoint(x: 18, y: 99))
    p.closeSubpath()
  }
  static let sharedLumen = Path { p in
    p.move(to: CGPoint(x: 120, y: 80))
    p.addQuadCurve(to: CGPoint(x: 233, y: 81), control: CGPoint(x: 174, y: 94))
    p.addCurve(to: CGPoint(x: 241, y: 185), control1: CGPoint(x: 247, y: 112), control2: CGPoint(x: 222, y: 151))
    p.addCurve(to: CGPoint(x: 231, y: 277), control1: CGPoint(x: 248, y: 210), control2: CGPoint(x: 220, y: 250))
    p.addQuadCurve(to: CGPoint(x: 126, y: 279), control: CGPoint(x: 174, y: 265))
    p.addCurve(to: CGPoint(x: 121, y: 188), control1: CGPoint(x: 113, y: 246), control2: CGPoint(x: 135, y: 219))
    p.addCurve(to: CGPoint(x: 120, y: 80), control1: CGPoint(x: 109, y: 164), control2: CGPoint(x: 131, y: 110))
    p.closeSubpath()
  }
  static let parietal = Path { p in
    p.move(to: CGPoint(x: 43, y: 131))
    p.addCurve(to: CGPoint(x: 96, y: 111), control1: CGPoint(x: 49, y: 104), control2: CGPoint(x: 78, y: 98))
    p.addQuadCurve(to: CGPoint(x: 123, y: 152), control: CGPoint(x: 127, y: 128))
    p.addCurve(to: CGPoint(x: 110, y: 214), control1: CGPoint(x: 123, y: 178), control2: CGPoint(x: 133, y: 199))
    p.addCurve(to: CGPoint(x: 43, y: 131), control1: CGPoint(x: 67, y: 236), control2: CGPoint(x: 30, y: 185))
    p.closeSubpath()
  }
  static let canaliculus = Path { p in
    p.move(to: CGPoint(x: 121, y: 144))
    p.addQuadCurve(to: CGPoint(x: 108, y: 141), control: CGPoint(x: 114, y: 149))
    p.addQuadCurve(to: CGPoint(x: 92, y: 132), control: CGPoint(x: 99, y: 129))
    p.addQuadCurve(to: CGPoint(x: 97, y: 144), control: CGPoint(x: 85, y: 135))
    p.addQuadCurve(to: CGPoint(x: 99, y: 157), control: CGPoint(x: 106, y: 151))
    p.addQuadCurve(to: CGPoint(x: 94, y: 166), control: CGPoint(x: 87, y: 161))
    p.addQuadCurve(to: CGPoint(x: 112, y: 159), control: CGPoint(x: 105, y: 170))
    p.addQuadCurve(to: CGPoint(x: 121, y: 159), control: CGPoint(x: 117, y: 155))
  }
  static let sectionChief = Path { p in
    p.move(to: CGPoint(x: 233, y: 155))
    p.addCurve(to: CGPoint(x: 310, y: 153), control1: CGPoint(x: 253, y: 136), control2: CGPoint(x: 286, y: 140))
    p.addQuadCurve(to: CGPoint(x: 314, y: 231), control: CGPoint(x: 328, y: 191))
    p.addCurve(to: CGPoint(x: 235, y: 251), control1: CGPoint(x: 308, y: 254), control2: CGPoint(x: 259, y: 268))
    p.addQuadCurve(to: CGPoint(x: 231, y: 228), control: CGPoint(x: 227, y: 245))
    p.addCurve(to: CGPoint(x: 233, y: 155), control1: CGPoint(x: 242, y: 193), control2: CGPoint(x: 232, y: 186))
    p.closeSubpath()
  }
  static let stomachCavity = Path { p in
    p.move(to: CGPoint(x: 28, y: 130))
    p.addCurve(to: CGPoint(x: 323, y: 118), control1: CGPoint(x: 69, y: 65), control2: CGPoint(x: 279, y: 61))
    p.addCurve(to: CGPoint(x: 278, y: 268), control1: CGPoint(x: 352, y: 152), control2: CGPoint(x: 319, y: 247))
    p.addCurve(to: CGPoint(x: 53, y: 251), control1: CGPoint(x: 211, y: 306), control2: CGPoint(x: 104, y: 286))
    p.addCurve(to: CGPoint(x: 28, y: 130), control1: CGPoint(x: 22, y: 230), control2: CGPoint(x: 10, y: 171))
    p.closeSubpath()
  }
  static let cavityFolds = Path { p in
    p.move(to: CGPoint(x: 35, y: 142))
    p.addCurve(to: CGPoint(x: 94, y: 107), control1: CGPoint(x: 59, y: 140), control2: CGPoint(x: 58, y: 111))
    p.move(to: CGPoint(x: 82, y: 98))
    p.addCurve(to: CGPoint(x: 156, y: 89), control1: CGPoint(x: 114, y: 113), control2: CGPoint(x: 131, y: 94))
    p.move(to: CGPoint(x: 173, y: 95))
    p.addCurve(to: CGPoint(x: 281, y: 103), control1: CGPoint(x: 216, y: 109), control2: CGPoint(x: 239, y: 80))
    p.move(to: CGPoint(x: 303, y: 115))
    p.addCurve(to: CGPoint(x: 314, y: 180), control1: CGPoint(x: 295, y: 139), control2: CGPoint(x: 318, y: 154))
    p.move(to: CGPoint(x: 42, y: 221))
    p.addCurve(to: CGPoint(x: 105, y: 254), control1: CGPoint(x: 74, y: 225), control2: CGPoint(x: 59, y: 241))
    p.move(to: CGPoint(x: 123, y: 266))
    p.addCurve(to: CGPoint(x: 208, y: 267), control1: CGPoint(x: 153, y: 266), control2: CGPoint(x: 180, y: 274))
    p.move(to: CGPoint(x: 235, y: 265))
    p.addCurve(to: CGPoint(x: 300, y: 224), control1: CGPoint(x: 261, y: 250), control2: CGPoint(x: 285, y: 256))
  }
  static let pepsinGlyph = Path { p in
    p.move(to: CGPoint(x: -0.94, y: 0.15))
    p.addCurve(to: CGPoint(x: 0.04, y: -0.91), control1: CGPoint(x: -1, y: -0.43), control2: CGPoint(x: -0.48, y: -1))
    p.addQuadCurve(to: CGPoint(x: 0.92, y: -0.55), control: CGPoint(x: 0.56, y: -1))
    p.addQuadCurve(to: CGPoint(x: 0.55, y: -0.13), control: CGPoint(x: 1.08, y: -0.20))
    p.addQuadCurve(to: CGPoint(x: 0.59, y: 0.19), control: CGPoint(x: 0.20, y: 0.02))
    p.addQuadCurve(to: CGPoint(x: 0.83, y: 0.58), control: CGPoint(x: 1.03, y: 0.25))
    p.addCurve(to: CGPoint(x: -0.94, y: 0.15), control1: CGPoint(x: 0.51, y: 1), control2: CGPoint(x: -0.81, y: 1.14))
    p.closeSubpath()
  }
  static let proteinY = [188.0, 172, 166, 175, 192, 199, 187, 169, 163, 172, 188, 193]
}
