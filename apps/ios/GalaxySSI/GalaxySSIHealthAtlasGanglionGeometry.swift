import SwiftUI

enum GalaxySSIHealthAtlasGanglionGeometry {
  static let sensoryCapsule = Path { p in
    p.move(to: CGPoint(x: 66, y: 162))
    p.addCurve(to: CGPoint(x: 133, y: 94), control1: CGPoint(x: 103, y: 168), control2: CGPoint(x: 101, y: 118))
    p.addCurve(to: CGPoint(x: 242, y: 120), control1: CGPoint(x: 167, y: 70), control2: CGPoint(x: 224, y: 82))
    p.addCurve(to: CGPoint(x: 291, y: 172), control1: CGPoint(x: 253, y: 141), control2: CGPoint(x: 259, y: 162))
    p.addLine(to: CGPoint(x: 291, y: 197))
    p.addCurve(to: CGPoint(x: 220, y: 240), control1: CGPoint(x: 263, y: 199), control2: CGPoint(x: 259, y: 223))
    p.addCurve(to: CGPoint(x: 108, y: 210), control1: CGPoint(x: 178, y: 258), control2: CGPoint(x: 125, y: 238))
    p.addQuadCurve(to: CGPoint(x: 66, y: 191), control: CGPoint(x: 96, y: 189))
    p.closeSubpath()
  }
  static let cord = Path { p in
    p.move(to: CGPoint(x: 31, y: 110))
    p.addCurve(to: CGPoint(x: 20, y: 168), control1: CGPoint(x: 14, y: 119), control2: CGPoint(x: 16, y: 150))
    p.addCurve(to: CGPoint(x: 22, y: 222), control1: CGPoint(x: 24, y: 182), control2: CGPoint(x: 13, y: 205))
    p.addCurve(to: CGPoint(x: 78, y: 215), control1: CGPoint(x: 37, y: 250), control2: CGPoint(x: 71, y: 238))
    p.addCurve(to: CGPoint(x: 78, y: 174), control1: CGPoint(x: 82, y: 200), control2: CGPoint(x: 79, y: 187))
    p.addCurve(to: CGPoint(x: 67, y: 118), control1: CGPoint(x: 74, y: 157), control2: CGPoint(x: 82, y: 135))
    p.addQuadCurve(to: CGPoint(x: 31, y: 110), control: CGPoint(x: 50, y: 101))
    p.closeSubpath()
  }
  static let dorsalHorn = Path { p in
    p.move(to: CGPoint(x: 36, y: 133))
    p.addCurve(to: CGPoint(x: 49, y: 173), control1: CGPoint(x: 44, y: 145), control2: CGPoint(x: 46, y: 166))
    p.addCurve(to: CGPoint(x: 62, y: 145), control1: CGPoint(x: 54, y: 169), control2: CGPoint(x: 54, y: 150))
    p.addCurve(to: CGPoint(x: 61, y: 185), control1: CGPoint(x: 65, y: 158), control2: CGPoint(x: 60, y: 175))
    p.addCurve(to: CGPoint(x: 65, y: 215), control1: CGPoint(x: 61, y: 195), control2: CGPoint(x: 69, y: 204))
    p.addCurve(to: CGPoint(x: 50, y: 196), control1: CGPoint(x: 59, y: 221), control2: CGPoint(x: 56, y: 211))
    p.addCurve(to: CGPoint(x: 36, y: 217), control1: CGPoint(x: 45, y: 191), control2: CGPoint(x: 45, y: 208))
    p.addCurve(to: CGPoint(x: 36, y: 191), control1: CGPoint(x: 29, y: 216), control2: CGPoint(x: 30, y: 203))
    p.addCurve(to: CGPoint(x: 36, y: 133), control1: CGPoint(x: 40, y: 180), control2: CGPoint(x: 30, y: 151))
    p.closeSubpath()
  }
  static let sensoryFibers = Path { p in
    p.move(to: CGPoint(x: 70, y: 172))
    p.addCurve(to: CGPoint(x: 164, y: 156), control1: CGPoint(x: 127, y: 177), control2: CGPoint(x: 131, y: 153))
    p.addCurve(to: CGPoint(x: 286, y: 179), control1: CGPoint(x: 210, y: 159), control2: CGPoint(x: 231, y: 181))
    p.move(to: CGPoint(x: 70, y: 186))
    p.addCurve(to: CGPoint(x: 180, y: 211), control1: CGPoint(x: 114, y: 185), control2: CGPoint(x: 132, y: 211))
    p.addCurve(to: CGPoint(x: 286, y: 191), control1: CGPoint(x: 227, y: 211), control2: CGPoint(x: 243, y: 190))
    p.move(to: CGPoint(x: 94, y: 186))
    p.addCurve(to: CGPoint(x: 191, y: 204), control1: CGPoint(x: 147, y: 181), control2: CGPoint(x: 125, y: 204))
    p.addQuadCurve(to: CGPoint(x: 241, y: 195), control: CGPoint(x: 221, y: 203))
  }
  static let sensoryAxon = Path { p in
    p.move(to: CGPoint(x: 334, y: 187))
    p.addCurve(to: CGPoint(x: 192, y: 183), control1: CGPoint(x: 279, y: 187), control2: CGPoint(x: 239, y: 185))
    p.addCurve(to: CGPoint(x: 76, y: 176), control1: CGPoint(x: 152, y: 181), control2: CGPoint(x: 107, y: 182))
    p.addQuadCurve(to: CGPoint(x: 60, y: 162), control: CGPoint(x: 65, y: 174))
  }
  static let sensoryStem = Path { p in
    p.move(to: CGPoint(x: 192, y: 183))
    p.addCurve(to: CGPoint(x: 179, y: 162), control1: CGPoint(x: 180, y: 182), control2: CGPoint(x: 179, y: 170))
    p.addQuadCurve(to: CGPoint(x: 176, y: 143), control: CGPoint(x: 180, y: 151))
  }
  static let autonomicCapsule = Path { p in
    p.move(to: CGPoint(x: 72, y: 144))
    p.addCurve(to: CGPoint(x: 162, y: 96), control1: CGPoint(x: 112, y: 133), control2: CGPoint(x: 118, y: 98))
    p.addCurve(to: CGPoint(x: 267, y: 144), control1: CGPoint(x: 214, y: 87), control2: CGPoint(x: 244, y: 104))
    p.addQuadCurve(to: CGPoint(x: 302, y: 172), control: CGPoint(x: 283, y: 167))
    p.addLine(to: CGPoint(x: 302, y: 197))
    p.addQuadCurve(to: CGPoint(x: 259, y: 220), control: CGPoint(x: 282, y: 195))
    p.addCurve(to: CGPoint(x: 107, y: 211), control1: CGPoint(x: 220, y: 264), control2: CGPoint(x: 140, y: 269))
    p.addQuadCurve(to: CGPoint(x: 72, y: 172), control: CGPoint(x: 93, y: 173))
    p.closeSubpath()
  }
  static let dendrites = Path { p in
    p.move(to: CGPoint(x: 214, y: 184))
    p.addCurve(to: CGPoint(x: 179, y: 132), control1: CGPoint(x: 195, y: 172), control2: CGPoint(x: 189, y: 147))
    p.addQuadCurve(to: CGPoint(x: 165, y: 120), control: CGPoint(x: 174, y: 124))
    p.move(to: CGPoint(x: 190, y: 152))
    p.addQuadCurve(to: CGPoint(x: 188, y: 124), control: CGPoint(x: 196, y: 135))
    p.move(to: CGPoint(x: 209, y: 198))
    p.addCurve(to: CGPoint(x: 157, y: 222), control1: CGPoint(x: 188, y: 198), control2: CGPoint(x: 180, y: 216))
    p.move(to: CGPoint(x: 186, y: 209))
    p.addQuadCurve(to: CGPoint(x: 168, y: 204), control: CGPoint(x: 178, y: 203))
    p.move(to: CGPoint(x: 220, y: 165))
    p.addCurve(to: CGPoint(x: 225, y: 127), control1: CGPoint(x: 215, y: 151), control2: CGPoint(x: 227, y: 139))
    p.move(to: CGPoint(x: 225, y: 137))
    p.addQuadCurve(to: CGPoint(x: 238, y: 124), control: CGPoint(x: 235, y: 132))
    p.move(to: CGPoint(x: 226, y: 207))
    p.addQuadCurve(to: CGPoint(x: 245, y: 227), control: CGPoint(x: 229, y: 223))
  }
  static let input = Path { p in
    p.move(to: CGPoint(x: 26, y: 153))
    p.addCurve(to: CGPoint(x: 112, y: 148), control1: CGPoint(x: 67, y: 153), control2: CGPoint(x: 89, y: 144))
    p.addCurve(to: CGPoint(x: 143, y: 160), control1: CGPoint(x: 128, y: 151), control2: CGPoint(x: 134, y: 155))
  }
  static let terminal = Path { p in
    p.move(to: CGPoint(x: 135, y: 153))
    p.addCurve(to: CGPoint(x: 154, y: 160), control1: CGPoint(x: 143, y: 146), control2: CGPoint(x: 154, y: 151))
    p.addCurve(to: CGPoint(x: 147, y: 171), control1: CGPoint(x: 154, y: 168), control2: CGPoint(x: 151, y: 171))
    p.addQuadCurve(to: CGPoint(x: 135, y: 164), control: CGPoint(x: 138, y: 172))
    p.closeSubpath()
  }
  static let receivingDendrite = Path { p in
    p.move(to: CGPoint(x: 166, y: 163))
    p.addCurve(to: CGPoint(x: 207, y: 189), control1: CGPoint(x: 189, y: 164), control2: CGPoint(x: 187, y: 181))
  }
  static let output = Path { p in
    p.move(to: CGPoint(x: 231, y: 187))
    p.addCurve(to: CGPoint(x: 302, y: 187), control1: CGPoint(x: 255, y: 177), control2: CGPoint(x: 279, y: 179))
    p.addQuadCurve(to: CGPoint(x: 334, y: 190), control: CGPoint(x: 319, y: 192))
  }
  static let sheathContour = Path { p in
    p.move(to: CGPoint(x: 166, y: 91))
    p.addCurve(to: CGPoint(x: 236, y: 163), control1: CGPoint(x: 205, y: 91), control2: CGPoint(x: 235, y: 122))
    p.addCurve(to: CGPoint(x: 165, y: 245), control1: CGPoint(x: 238, y: 208), control2: CGPoint(x: 207, y: 244))
    p.addCurve(to: CGPoint(x: 92, y: 172), control1: CGPoint(x: 123, y: 245), control2: CGPoint(x: 92, y: 214))
    p.addCurve(to: CGPoint(x: 166, y: 91), control1: CGPoint(x: 90, y: 128), control2: CGPoint(x: 122, y: 93))
    p.closeSubpath()
  }
  static let gliaBorders = Path { p in
    p.move(to: CGPoint(x: 135, y: 97))
    p.addQuadCurve(to: CGPoint(x: 141, y: 111), control: CGPoint(x: 135, y: 106))
    p.move(to: CGPoint(x: 214, y: 112))
    p.addQuadCurve(to: CGPoint(x: 206, y: 125), control: CGPoint(x: 211, y: 121))
    p.move(to: CGPoint(x: 235, y: 183))
    p.addQuadCurve(to: CGPoint(x: 222, y: 183), control: CGPoint(x: 228, y: 181))
    p.move(to: CGPoint(x: 189, y: 241))
    p.addQuadCurve(to: CGPoint(x: 183, y: 227), control: CGPoint(x: 188, y: 232))
    p.move(to: CGPoint(x: 111, y: 223))
    p.addQuadCurve(to: CGPoint(x: 124, y: 213), control: CGPoint(x: 119, y: 221))
    p.move(to: CGPoint(x: 94, y: 153))
    p.addQuadCurve(to: CGPoint(x: 108, y: 155), control: CGPoint(x: 103, y: 153))
  }
  static let matrix = Path { p in
    p.move(to: CGPoint(x: 218, y: 114))
    p.addQuadCurve(to: CGPoint(x: 249, y: 152), control: CGPoint(x: 237, y: 124))
    p.move(to: CGPoint(x: 229, y: 218))
    p.addQuadCurve(to: CGPoint(x: 262, y: 215), control: CGPoint(x: 253, y: 208))
    p.move(to: CGPoint(x: 239, y: 227))
    p.addQuadCurve(to: CGPoint(x: 273, y: 225), control: CGPoint(x: 258, y: 221))
    p.move(to: CGPoint(x: 245, y: 155))
    p.addQuadCurve(to: CGPoint(x: 278, y: 142), control: CGPoint(x: 259, y: 143))
  }
}
