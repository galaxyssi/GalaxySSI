import SwiftUI

enum GalaxySSIHealthAtlasPlacentalGeometry {
  static let field = Path { p in
    p.move(to: CGPoint(x: 33, y: 106))
    p.addCurve(to: CGPoint(x: 206, y: 93), control1: CGPoint(x: 83, y: 89), control2: CGPoint(x: 156, y: 96))
    p.addLine(to: CGPoint(x: 300, y: 93))
    p.addCurve(to: CGPoint(x: 334, y: 197), control1: CGPoint(x: 335, y: 102), control2: CGPoint(x: 339, y: 149))
    p.addCurve(to: CGPoint(x: 280, y: 269), control1: CGPoint(x: 330, y: 232), control2: CGPoint(x: 316, y: 261))
    p.addCurve(to: CGPoint(x: 115, y: 271), control1: CGPoint(x: 223, y: 279), control2: CGPoint(x: 165, y: 269))
    p.addCurve(to: CGPoint(x: 31, y: 249), control1: CGPoint(x: 78, y: 273), control2: CGPoint(x: 39, y: 275))
    p.addCurve(to: CGPoint(x: 33, y: 106), control1: CGPoint(x: 24, y: 221), control2: CGPoint(x: 20, y: 131))
    p.closeSubpath()
  }
  static let maternalRoute = Path { p in
    p.move(to: CGPoint(x: 43, y: 257))
    p.addCurve(to: CGPoint(x: 61, y: 133), control1: CGPoint(x: 37, y: 222), control2: CGPoint(x: 40, y: 160))
    p.addCurve(to: CGPoint(x: 113, y: 143), control1: CGPoint(x: 78, y: 112), control2: CGPoint(x: 105, y: 113))
    p.addCurve(to: CGPoint(x: 108, y: 258), control1: CGPoint(x: 122, y: 171), control2: CGPoint(x: 104, y: 207))
  }
  static let surface = Path { p in
    p.move(to: CGPoint(x: 217, y: 93))
    p.addCurve(to: CGPoint(x: 176, y: 131), control1: CGPoint(x: 216, y: 115), control2: CGPoint(x: 197, y: 121))
    p.addCurve(to: CGPoint(x: 138, y: 177), control1: CGPoint(x: 151, y: 142), control2: CGPoint(x: 139, y: 154))
    p.addCurve(to: CGPoint(x: 160, y: 244), control1: CGPoint(x: 135, y: 207), control2: CGPoint(x: 143, y: 229))
    p.addCurve(to: CGPoint(x: 247, y: 244), control1: CGPoint(x: 180, y: 262), control2: CGPoint(x: 218, y: 257))
    p.addCurve(to: CGPoint(x: 295, y: 184), control1: CGPoint(x: 277, y: 232), control2: CGPoint(x: 294, y: 208))
    p.addCurve(to: CGPoint(x: 287, y: 122), control1: CGPoint(x: 297, y: 159), control2: CGPoint(x: 281, y: 144))
    p.addQuadCurve(to: CGPoint(x: 300, y: 93), control: CGPoint(x: 291, y: 107))
    p.closeSubpath()
  }
  static let core = Path { p in
    p.move(to: CGPoint(x: 225, y: 93))
    p.addCurve(to: CGPoint(x: 179, y: 137), control1: CGPoint(x: 223, y: 121), control2: CGPoint(x: 200, y: 127))
    p.addCurve(to: CGPoint(x: 146, y: 178), control1: CGPoint(x: 157, y: 147), control2: CGPoint(x: 147, y: 158))
    p.addCurve(to: CGPoint(x: 166, y: 238), control1: CGPoint(x: 143, y: 205), control2: CGPoint(x: 150, y: 224))
    p.addCurve(to: CGPoint(x: 244, y: 237), control1: CGPoint(x: 184, y: 252), control2: CGPoint(x: 216, y: 249))
    p.addCurve(to: CGPoint(x: 288, y: 183), control1: CGPoint(x: 272, y: 225), control2: CGPoint(x: 287, y: 205))
    p.addCurve(to: CGPoint(x: 280, y: 121), control1: CGPoint(x: 290, y: 160), control2: CGPoint(x: 274, y: 144))
    p.addQuadCurve(to: CGPoint(x: 293, y: 93), control: CGPoint(x: 284, y: 105))
    p.closeSubpath()
  }
  static let fetalRoute = Path { p in
    p.move(to: CGPoint(x: 233, y: 94))
    p.addCurve(to: CGPoint(x: 176, y: 141), control1: CGPoint(x: 226, y: 117), control2: CGPoint(x: 198, y: 127))
    p.addCurve(to: CGPoint(x: 158, y: 187), control1: CGPoint(x: 161, y: 151), control2: CGPoint(x: 158, y: 169))
    p.addCurve(to: CGPoint(x: 205, y: 232), control1: CGPoint(x: 158, y: 216), control2: CGPoint(x: 176, y: 237))
    p.addCurve(to: CGPoint(x: 269, y: 193), control1: CGPoint(x: 231, y: 228), control2: CGPoint(x: 258, y: 217))
    p.addCurve(to: CGPoint(x: 270, y: 122), control1: CGPoint(x: 282, y: 167), control2: CGPoint(x: 264, y: 147))
    p.addQuadCurve(to: CGPoint(x: 284, y: 94), control: CGPoint(x: 274, y: 105))
  }
  static let surfaceLight = Path { p in
    p.move(to: CGPoint(x: 213, y: 114))
    p.addQuadCurve(to: CGPoint(x: 189, y: 129), control: CGPoint(x: 204, y: 123))
    p.move(to: CGPoint(x: 174, y: 137))
    p.addQuadCurve(to: CGPoint(x: 150, y: 156), control: CGPoint(x: 157, y: 147))
    p.move(to: CGPoint(x: 141, y: 181))
    p.addQuadCurve(to: CGPoint(x: 140, y: 196), control: CGPoint(x: 139, y: 187))
    p.move(to: CGPoint(x: 155, y: 233))
    p.addQuadCurve(to: CGPoint(x: 176, y: 247), control: CGPoint(x: 165, y: 244))
    p.move(to: CGPoint(x: 227, y: 248))
    p.addQuadCurve(to: CGPoint(x: 253, y: 238), control: CGPoint(x: 243, y: 244))
    p.move(to: CGPoint(x: 278, y: 217))
    p.addQuadCurve(to: CGPoint(x: 290, y: 190), control: CGPoint(x: 286, y: 207))
  }
  static let stromalFibers = Path { p in
    p.move(to: CGPoint(x: 179, y: 165))
    p.addCurve(to: CGPoint(x: 230, y: 140), control1: CGPoint(x: 196, y: 152), control2: CGPoint(x: 220, y: 152))
    p.move(to: CGPoint(x: 193, y: 189))
    p.addCurve(to: CGPoint(x: 229, y: 185), control1: CGPoint(x: 205, y: 184), control2: CGPoint(x: 216, y: 193))
    p.move(to: CGPoint(x: 197, y: 219))
    p.addQuadCurve(to: CGPoint(x: 227, y: 209), control: CGPoint(x: 215, y: 217))
    p.move(to: CGPoint(x: 231, y: 177))
    p.addQuadCurve(to: CGPoint(x: 246, y: 147), control: CGPoint(x: 249, y: 163))
  }
  static let nuclei: [(Double,Double,Double)] = [
    (186, 130, -26),
    (158, 146, -42),
    (141, 168, -80),
    (142, 208, 74),
    (160, 239, 45),
    (188, 252, 8),
    (222, 249, -14),
    (252, 239, -25),
    (280, 218, -48),
    (291, 188, -83),
    (288, 158, 73),
    (283, 130, -84),
  ]
}
