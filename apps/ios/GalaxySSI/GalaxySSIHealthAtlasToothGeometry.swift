import SwiftUI

enum GalaxySSIHealthAtlasToothGeometry {
  static let palate = Path { p in
    p.move(to: CGPoint(x: 87, y: 252))
    p.addCurve(to: CGPoint(x: 97, y: 117), control1: CGPoint(x: 79, y: 224), control2: CGPoint(x: 82, y: 156))
    p.addCurve(to: CGPoint(x: 180, y: 62), control1: CGPoint(x: 113, y: 77), control2: CGPoint(x: 141, y: 62))
    p.addCurve(to: CGPoint(x: 263, y: 117), control1: CGPoint(x: 219, y: 62), control2: CGPoint(x: 247, y: 77))
    p.addCurve(to: CGPoint(x: 273, y: 252), control1: CGPoint(x: 278, y: 156), control2: CGPoint(x: 281, y: 224))
    p.addCurve(to: CGPoint(x: 87, y: 252), control1: CGPoint(x: 268, y: 290), control2: CGPoint(x: 92, y: 290))
    p.closeSubpath()
  }
  static let palatalVault = Path { p in
    p.move(to: CGPoint(x: 125, y: 250))
    p.addCurve(to: CGPoint(x: 141, y: 129), control1: CGPoint(x: 119, y: 215), control2: CGPoint(x: 122, y: 162))
    p.addCurve(to: CGPoint(x: 219, y: 129), control1: CGPoint(x: 158, y: 99), control2: CGPoint(x: 202, y: 99))
    p.addCurve(to: CGPoint(x: 235, y: 250), control1: CGPoint(x: 238, y: 162), control2: CGPoint(x: 241, y: 215))
    p.addCurve(to: CGPoint(x: 125, y: 250), control1: CGPoint(x: 219, y: 269), control2: CGPoint(x: 141, y: 269))
    p.closeSubpath()
  }
  static let archIncisor = Path { p in
    p.move(to: CGPoint(x: -0.9, y: -0.71))
    p.addQuadCurve(to: CGPoint(x: 0.91, y: -0.71), control: CGPoint(x: 0, y: -0.94))
    p.addCurve(to: CGPoint(x: 0.55, y: 0.76), control1: CGPoint(x: 1.05, y: -0.17), control2: CGPoint(x: 0.84, y: 0.62))
    p.addQuadCurve(to: CGPoint(x: -0.63, y: 0.76), control: CGPoint(x: 0, y: 1.04))
    p.addQuadCurve(to: CGPoint(x: -0.9, y: -0.71), control: CGPoint(x: -0.97, y: 0.34))
    p.closeSubpath()
  }
  static let archCanine = Path { p in
    p.move(to: CGPoint(x: -0.9, y: -0.05))
    p.addQuadCurve(to: CGPoint(x: -0.05, y: -0.99), control: CGPoint(x: -0.63, y: -0.57))
    p.addQuadCurve(to: CGPoint(x: 0.94, y: -0.11), control: CGPoint(x: 0.51, y: -0.82))
    p.addQuadCurve(to: CGPoint(x: 0.21, y: 0.9), control: CGPoint(x: 0.85, y: 0.68))
    p.addQuadCurve(to: CGPoint(x: -0.9, y: -0.05), control: CGPoint(x: -0.67, y: 1.07))
    p.closeSubpath()
  }
  static let archPremolar = Path { p in
    p.move(to: CGPoint(x: -0.8, y: -0.54))
    p.addCurve(to: CGPoint(x: 0.87, y: -0.5), control1: CGPoint(x: -0.4, y: -1.13), control2: CGPoint(x: 0.49, y: -1.15))
    p.addCurve(to: CGPoint(x: 0.02, y: 0.98), control1: CGPoint(x: 1.16, y: 0.19), control2: CGPoint(x: 0.64, y: 0.99))
    p.addCurve(to: CGPoint(x: -0.8, y: -0.54), control1: CGPoint(x: -0.61, y: 1), control2: CGPoint(x: -1.15, y: 0.27))
    p.closeSubpath()
  }
  static let archMolar = Path { p in
    p.move(to: CGPoint(x: -0.92, y: -0.51))
    p.addQuadCurve(to: CGPoint(x: -0.31, y: -0.93), control: CGPoint(x: -0.88, y: -1.05))
    p.addQuadCurve(to: CGPoint(x: 0.39, y: -0.96), control: CGPoint(x: 0.1, y: -0.78))
    p.addQuadCurve(to: CGPoint(x: 0.95, y: -0.44), control: CGPoint(x: 0.96, y: -0.98))
    p.addQuadCurve(to: CGPoint(x: 0.95, y: 0.37), control: CGPoint(x: 0.79, y: -0.05))
    p.addQuadCurve(to: CGPoint(x: 0.4, y: 0.94), control: CGPoint(x: 0.91, y: 0.98))
    p.addQuadCurve(to: CGPoint(x: -0.31, y: 0.98), control: CGPoint(x: 0.03, y: 0.81))
    p.addQuadCurve(to: CGPoint(x: -0.92, y: 0.49), control: CGPoint(x: -0.92, y: 1))
    p.addQuadCurve(to: CGPoint(x: -0.92, y: -0.51), control: CGPoint(x: -0.79, y: 0.09))
    p.closeSubpath()
  }
  static let archFissure = Path { p in
    p.move(to: CGPoint(x: -0.58, y: -0.08))
    p.addQuadCurve(to: CGPoint(x: 0, y: -0.09), control: CGPoint(x: -0.21, y: 0.12))
    p.addQuadCurve(to: CGPoint(x: 0.63, y: -0.05), control: CGPoint(x: 0.29, y: -0.24))
  }
  static let cuttingEdge = Path { p in
    p.move(to: CGPoint(x: -0.89, y: 0.07))
    p.addQuadCurve(to: CGPoint(x: 0.62, y: 0.02), control: CGPoint(x: -0.23, y: -0.15))
    p.addCurve(to: CGPoint(x: 0.15, y: 0.96), control1: CGPoint(x: 0.96, y: 0.28), control2: CGPoint(x: 0.68, y: 0.76))
    p.addLine(to: CGPoint(x: -0.82, y: 1))
    p.addQuadCurve(to: CGPoint(x: -0.89, y: 0.07), control: CGPoint(x: -1.09, y: 0.58))
    p.closeSubpath()
  }
  static let pointedCusp = Path { p in
    p.move(to: CGPoint(x: -0.92, y: 0.04))
    p.addQuadCurve(to: CGPoint(x: 0.8, y: 0.06), control: CGPoint(x: -0.13, y: -0.18))
    p.addQuadCurve(to: CGPoint(x: 0.65, y: 0.69), control: CGPoint(x: 1.04, y: 0.45))
    p.addLine(to: CGPoint(x: 0.05, y: 0.99))
    p.addQuadCurve(to: CGPoint(x: -0.27, y: 0.9), control: CGPoint(x: -0.15, y: 1.04))
    p.addQuadCurve(to: CGPoint(x: -0.92, y: 0.04), control: CGPoint(x: -1.08, y: 0.55))
    p.closeSubpath()
  }
  static let grindingCusps = Path { p in
    p.move(to: CGPoint(x: -0.92, y: 0.07))
    p.addQuadCurve(to: CGPoint(x: 0, y: 0.02), control: CGPoint(x: -0.46, y: -0.15))
    p.addQuadCurve(to: CGPoint(x: 0.94, y: 0.09), control: CGPoint(x: 0.58, y: -0.14))
    p.addQuadCurve(to: CGPoint(x: 0.93, y: 0.74), control: CGPoint(x: 1.03, y: 0.45))
    p.addQuadCurve(to: CGPoint(x: 0.42, y: 0.94), control: CGPoint(x: 0.69, y: 1.05))
    p.addQuadCurve(to: CGPoint(x: -0.06, y: 0.91), control: CGPoint(x: 0.16, y: 0.8))
    p.addQuadCurve(to: CGPoint(x: -0.77, y: 0.92), control: CGPoint(x: -0.52, y: 1.07))
    p.addQuadCurve(to: CGPoint(x: -0.92, y: 0.07), control: CGPoint(x: -1.06, y: 0.73))
    p.closeSubpath()
  }
  static let profileVault = Path { p in
    p.move(to: CGPoint(x: 45, y: 130))
    p.addCurve(to: CGPoint(x: 131, y: 99), control1: CGPoint(x: 74, y: 113), control2: CGPoint(x: 92, y: 97))
    p.addCurve(to: CGPoint(x: 256, y: 98), control1: CGPoint(x: 176, y: 104), control2: CGPoint(x: 213, y: 91))
    p.addQuadCurve(to: CGPoint(x: 306, y: 122), control: CGPoint(x: 289, y: 103))
    p.addLine(to: CGPoint(x: 293, y: 149))
    p.addQuadCurve(to: CGPoint(x: 68, y: 151), control: CGPoint(x: 181, y: 139))
    p.addQuadCurve(to: CGPoint(x: 45, y: 130), control: CGPoint(x: 48, y: 152))
    p.closeSubpath()
  }
  static let profileUpperGum = Path { p in
    p.move(to: CGPoint(x: 56, y: 141))
    p.addCurve(to: CGPoint(x: 294, y: 138), control1: CGPoint(x: 101, y: 126), control2: CGPoint(x: 236, y: 131))
    p.addQuadCurve(to: CGPoint(x: 293, y: 154), control: CGPoint(x: 303, y: 144))
    p.addCurve(to: CGPoint(x: 67, y: 154), control1: CGPoint(x: 258, y: 161), control2: CGPoint(x: 109, y: 158))
    p.addQuadCurve(to: CGPoint(x: 56, y: 141), control: CGPoint(x: 55, y: 153))
    p.closeSubpath()
  }
  static let profileJaw = Path { p in
    p.move(to: CGPoint(x: 295, y: 135))
    p.addQuadCurve(to: CGPoint(x: 307, y: 130), control: CGPoint(x: 295, y: 126))
    p.addQuadCurve(to: CGPoint(x: 313, y: 145), control: CGPoint(x: 316, y: 133))
    p.addLine(to: CGPoint(x: 305, y: 222))
    p.addQuadCurve(to: CGPoint(x: 270, y: 252), control: CGPoint(x: 301, y: 247))
    p.addCurve(to: CGPoint(x: 79, y: 246), control1: CGPoint(x: 215, y: 261), control2: CGPoint(x: 140, y: 261))
    p.addQuadCurve(to: CGPoint(x: 60, y: 217), control: CGPoint(x: 57, y: 239))
    p.addLine(to: CGPoint(x: 74, y: 205))
    p.addQuadCurve(to: CGPoint(x: 268, y: 209), control: CGPoint(x: 184, y: 219))
    p.addQuadCurve(to: CGPoint(x: 285, y: 179), control: CGPoint(x: 284, y: 201))
    p.closeSubpath()
  }
  static let profileLowerGum = Path { p in
    p.move(to: CGPoint(x: 61, y: 213))
    p.addCurve(to: CGPoint(x: 137, y: 205), control1: CGPoint(x: 73, y: 199), control2: CGPoint(x: 109, y: 202))
    p.addCurve(to: CGPoint(x: 287, y: 198), control1: CGPoint(x: 192, y: 206), control2: CGPoint(x: 261, y: 200))
    p.addLine(to: CGPoint(x: 284, y: 214))
    p.addCurve(to: CGPoint(x: 67, y: 220), control1: CGPoint(x: 243, y: 228), control2: CGPoint(x: 122, y: 229))
    p.addQuadCurve(to: CGPoint(x: 61, y: 213), control: CGPoint(x: 60, y: 218))
    p.closeSubpath()
  }
  static let profileJawContour = Path { p in
    p.move(to: CGPoint(x: 75, y: 232))
    p.addCurve(to: CGPoint(x: 280, y: 235), control1: CGPoint(x: 123, y: 249), control2: CGPoint(x: 236, y: 252))
    p.addQuadCurve(to: CGPoint(x: 296, y: 201), control: CGPoint(x: 295, y: 225))
  }
  static let frontVault = Path { p in
    p.move(to: CGPoint(x: 51, y: 130))
    p.addCurve(to: CGPoint(x: 180, y: 109), control1: CGPoint(x: 78, y: 107), control2: CGPoint(x: 132, y: 108))
    p.addCurve(to: CGPoint(x: 309, y: 130), control1: CGPoint(x: 228, y: 108), control2: CGPoint(x: 282, y: 107))
    p.addLine(to: CGPoint(x: 307, y: 157))
    p.addQuadCurve(to: CGPoint(x: 251, y: 157), control: CGPoint(x: 280, y: 169))
    p.addCurve(to: CGPoint(x: 180, y: 130), control1: CGPoint(x: 227, y: 147), control2: CGPoint(x: 221, y: 131))
    p.addCurve(to: CGPoint(x: 109, y: 157), control1: CGPoint(x: 139, y: 131), control2: CGPoint(x: 133, y: 147))
    p.addQuadCurve(to: CGPoint(x: 53, y: 157), control: CGPoint(x: 80, y: 169))
    p.closeSubpath()
  }
  static let palateEdge = Path { p in
    p.move(to: CGPoint(x: 56, y: 156))
    p.addQuadCurve(to: CGPoint(x: 110, y: 155), control: CGPoint(x: 83, y: 167))
    p.addCurve(to: CGPoint(x: 180, y: 130), control1: CGPoint(x: 133, y: 147), control2: CGPoint(x: 140, y: 130))
    p.addCurve(to: CGPoint(x: 250, y: 155), control1: CGPoint(x: 220, y: 130), control2: CGPoint(x: 227, y: 147))
    p.addQuadCurve(to: CGPoint(x: 304, y: 156), control: CGPoint(x: 277, y: 167))
  }
  static let frontJaw = Path { p in
    p.move(to: CGPoint(x: 51, y: 210))
    p.addQuadCurve(to: CGPoint(x: 110, y: 213), control: CGPoint(x: 74, y: 201))
    p.addCurve(to: CGPoint(x: 180, y: 243), control1: CGPoint(x: 129, y: 220), control2: CGPoint(x: 126, y: 242))
    p.addCurve(to: CGPoint(x: 250, y: 213), control1: CGPoint(x: 234, y: 242), control2: CGPoint(x: 231, y: 220))
    p.addQuadCurve(to: CGPoint(x: 309, y: 210), control: CGPoint(x: 286, y: 201))
    p.addLine(to: CGPoint(x: 303, y: 230))
    p.addCurve(to: CGPoint(x: 180, y: 285), control1: CGPoint(x: 282, y: 277), control2: CGPoint(x: 229, y: 285))
    p.addCurve(to: CGPoint(x: 57, y: 230), control1: CGPoint(x: 131, y: 285), control2: CGPoint(x: 78, y: 277))
    p.closeSubpath()
  }
  static let frontGum = Path { p in
    p.move(to: CGPoint(x: 53, y: 211))
    p.addQuadCurve(to: CGPoint(x: 111, y: 212), control: CGPoint(x: 80, y: 200))
    p.addCurve(to: CGPoint(x: 180, y: 242), control1: CGPoint(x: 133, y: 222), control2: CGPoint(x: 126, y: 240))
    p.addCurve(to: CGPoint(x: 249, y: 212), control1: CGPoint(x: 234, y: 240), control2: CGPoint(x: 227, y: 222))
    p.addQuadCurve(to: CGPoint(x: 307, y: 211), control: CGPoint(x: 280, y: 200))
  }
  static let bite = Path { p in
    p.move(to: CGPoint(x: -33, y: -4))
    p.addQuadCurve(to: CGPoint(x: -5, y: -8), control: CGPoint(x: -22, y: -10))
    p.addQuadCurve(to: CGPoint(x: 35, y: -3), control: CGPoint(x: 17, y: -11))
    p.addLine(to: CGPoint(x: 31, y: 6))
    p.addQuadCurve(to: CGPoint(x: -9, y: 7), control: CGPoint(x: 9, y: 10))
    p.addQuadCurve(to: CGPoint(x: -35, y: 3), control: CGPoint(x: -23, y: 10))
    p.closeSubpath()
  }
  static let outerBite = Path { p in
    p.move(to: CGPoint(x: -33, y: -4))
    p.addQuadCurve(to: CGPoint(x: -2, y: -8), control: CGPoint(x: -22, y: -10))
    p.addLine(to: CGPoint(x: 1, y: 6))
    p.addQuadCurve(to: CGPoint(x: -35, y: 3), control: CGPoint(x: -18, y: 10))
    p.closeSubpath()
  }
  static let innerBite = Path { p in
    p.move(to: CGPoint(x: 0, y: -8))
    p.addQuadCurve(to: CGPoint(x: 35, y: -3), control: CGPoint(x: 17, y: -11))
    p.addLine(to: CGPoint(x: 31, y: 6))
    p.addQuadCurve(to: CGPoint(x: 3, y: 7), control: CGPoint(x: 13, y: 10))
    p.closeSubpath()
  }
  static let crumb = Path { p in
    p.move(to: CGPoint(x: -0.96, y: -0.09))
    p.addLine(to: CGPoint(x: -0.58, y: -0.79))
    p.addQuadCurve(to: CGPoint(x: 0.52, y: -0.69), control: CGPoint(x: -0.03, y: -1.12))
    p.addLine(to: CGPoint(x: 0.96, y: -0.24))
    p.addLine(to: CGPoint(x: 0.74, y: 0.56))
    p.addQuadCurve(to: CGPoint(x: -0.49, y: 0.71), control: CGPoint(x: 0.21, y: 0.98))
    p.addLine(to: CGPoint(x: -0.88, y: 0.48))
    p.closeSubpath()
  }
  static func tongue(_ tip: Double, _ lift: Double) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 119, y: 237))
    p.addCurve(to: CGPoint(x: 151, y: 208), control1: CGPoint(x: 108, y: 217), control2: CGPoint(x: 126, y: 208))
    p.addCurve(to: CGPoint(x: tip, y: 208 - lift), control1: CGPoint(x: 181, y: 205), control2: CGPoint(x: tip - 24, y: 212 - lift))
    p.addCurve(to: CGPoint(x: 171, y: 248), control1: CGPoint(x: tip + 4, y: 229 - lift), control2: CGPoint(x: 210, y: 248))
    p.addQuadCurve(to: CGPoint(x: 119, y: 237), control: CGPoint(x: 136, y: 249))
    p.closeSubpath()
    return p
  }
  static func tongueMidline(_ tip: Double, _ lift: Double) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 151, y: 224))
    p.addQuadCurve(to: CGPoint(x: tip - 16, y: 218 - lift), control: CGPoint(x: 182, y: 215))
    return p
  }
}
