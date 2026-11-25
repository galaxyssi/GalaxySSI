import SwiftUI

enum GalaxySSIHealthAtlasMesangialGeometry {
  static let capsule = Path { p in
    p.move(to: CGPoint(x: 35, y: 34))
    p.addCurve(to: CGPoint(x: 126, y: 27), control1: CGPoint(x: 52, y: 9), control2: CGPoint(x: 102, y: 9))
    p.addCurve(to: CGPoint(x: 137, y: 80), control1: CGPoint(x: 145, y: 41), control2: CGPoint(x: 149, y: 67))
    p.addQuadCurve(to: CGPoint(x: 152, y: 91), control: CGPoint(x: 135, y: 84))
    p.addLine(to: CGPoint(x: 146, y: 101))
    p.addQuadCurve(to: CGPoint(x: 121, y: 96), control: CGPoint(x: 128, y: 91))
    p.addCurve(to: CGPoint(x: 35, y: 76), control1: CGPoint(x: 89, y: 112), control2: CGPoint(x: 44, y: 101))
    p.addCurve(to: CGPoint(x: 35, y: 34), control1: CGPoint(x: 30, y: 64), control2: CGPoint(x: 30, y: 48))
    p.closeSubpath()
  }
  static let tuft = Path { p in
    p.move(to: CGPoint(x: 18, y: 49))
    p.addCurve(to: CGPoint(x: 54, y: 34), control1: CGPoint(x: 41, y: 55), control2: CGPoint(x: 48, y: 50))
    p.addCurve(to: CGPoint(x: 84, y: 40), control1: CGPoint(x: 61, y: 17), control2: CGPoint(x: 89, y: 23))
    p.addCurve(to: CGPoint(x: 62, y: 68), control1: CGPoint(x: 80, y: 54), control2: CGPoint(x: 53, y: 52))
    p.addCurve(to: CGPoint(x: 97, y: 48), control1: CGPoint(x: 70, y: 82), control2: CGPoint(x: 88, y: 57))
    p.addCurve(to: CGPoint(x: 122, y: 72), control1: CGPoint(x: 116, y: 26), control2: CGPoint(x: 138, y: 55))
    p.addCurve(to: CGPoint(x: 81, y: 84), control1: CGPoint(x: 106, y: 88), control2: CGPoint(x: 91, y: 73))
    p.addCurve(to: CGPoint(x: 48, y: 71), control1: CGPoint(x: 65, y: 96), control2: CGPoint(x: 56, y: 77))
    p.addQuadCurve(to: CGPoint(x: 18, y: 69), control: CGPoint(x: 36, y: 65))
  }
  static let tuftBranches = Path { p in
    p.move(to: CGPoint(x: 50, y: 43))
    p.addCurve(to: CGPoint(x: 74, y: 87), control1: CGPoint(x: 39, y: 72), control2: CGPoint(x: 61, y: 88))
    p.move(to: CGPoint(x: 81, y: 33))
    p.addCurve(to: CGPoint(x: 120, y: 48), control1: CGPoint(x: 100, y: 20), control2: CGPoint(x: 119, y: 31))
    p.move(to: CGPoint(x: 87, y: 59))
    p.addCurve(to: CGPoint(x: 120, y: 56), control1: CGPoint(x: 98, y: 69), control2: CGPoint(x: 105, y: 58))
  }
  static let leftLumen = Path { p in
    p.move(to: CGPoint(x: 82, y: 140))
    p.addCurve(to: CGPoint(x: 34, y: 208), control1: CGPoint(x: 49, y: 139), control2: CGPoint(x: 33, y: 175))
    p.addCurve(to: CGPoint(x: 87, y: 277), control1: CGPoint(x: 34, y: 241), control2: CGPoint(x: 56, y: 276))
    p.addCurve(to: CGPoint(x: 112, y: 238), control1: CGPoint(x: 113, y: 278), control2: CGPoint(x: 122, y: 259))
    p.addCurve(to: CGPoint(x: 112, y: 184), control1: CGPoint(x: 102, y: 218), control2: CGPoint(x: 105, y: 205))
    p.addCurve(to: CGPoint(x: 82, y: 140), control1: CGPoint(x: 121, y: 160), control2: CGPoint(x: 106, y: 141))
    p.closeSubpath()
  }
  static let rightLumen = Path { p in
    p.move(to: CGPoint(x: 192, y: 140))
    p.addCurve(to: CGPoint(x: 238, y: 207), control1: CGPoint(x: 220, y: 139), control2: CGPoint(x: 239, y: 171))
    p.addCurve(to: CGPoint(x: 196, y: 273), control1: CGPoint(x: 239, y: 240), control2: CGPoint(x: 226, y: 269))
    p.addCurve(to: CGPoint(x: 163, y: 239), control1: CGPoint(x: 169, y: 278), control2: CGPoint(x: 155, y: 257))
    p.addCurve(to: CGPoint(x: 162, y: 180), control1: CGPoint(x: 171, y: 218), control2: CGPoint(x: 170, y: 198))
    p.addCurve(to: CGPoint(x: 192, y: 140), control1: CGPoint(x: 153, y: 159), control2: CGPoint(x: 168, y: 140))
    p.closeSubpath()
  }
  static let relaxedEdge = Path { p in
    p.move(to: CGPoint(x: 27, y: 207))
    p.addCurve(to: CGPoint(x: 89, y: 284), control1: CGPoint(x: 26, y: 247), control2: CGPoint(x: 51, y: 283))
  }
  static let cell = Path { p in
    p.move(to: CGPoint(x: 118, y: 174))
    p.addCurve(to: CGPoint(x: 138, y: 203), control1: CGPoint(x: 129, y: 180), control2: CGPoint(x: 126, y: 201))
    p.addCurve(to: CGPoint(x: 163, y: 178), control1: CGPoint(x: 149, y: 202), control2: CGPoint(x: 150, y: 182))
    p.addCurve(to: CGPoint(x: 153, y: 214), control1: CGPoint(x: 157, y: 188), control2: CGPoint(x: 158, y: 206))
    p.addCurve(to: CGPoint(x: 149, y: 239), control1: CGPoint(x: 158, y: 225), control2: CGPoint(x: 153, y: 234))
    p.addCurve(to: CGPoint(x: 160, y: 257), control1: CGPoint(x: 148, y: 246), control2: CGPoint(x: 158, y: 250))
    p.addCurve(to: CGPoint(x: 136, y: 244), control1: CGPoint(x: 148, y: 255), control2: CGPoint(x: 142, y: 247))
    p.addCurve(to: CGPoint(x: 115, y: 254), control1: CGPoint(x: 129, y: 243), control2: CGPoint(x: 124, y: 253))
    p.addCurve(to: CGPoint(x: 123, y: 230), control1: CGPoint(x: 120, y: 246), control2: CGPoint(x: 125, y: 238))
    p.addCurve(to: CGPoint(x: 126, y: 201), control1: CGPoint(x: 119, y: 219), control2: CGPoint(x: 130, y: 212))
    p.addQuadCurve(to: CGPoint(x: 118, y: 174), control: CGPoint(x: 122, y: 181))
    p.closeSubpath()
  }
  static let podocyte = Path { p in
    p.move(to: CGPoint(x: 149, y: 147))
    p.addCurve(to: CGPoint(x: 178, y: 118), control1: CGPoint(x: 159, y: 137), control2: CGPoint(x: 170, y: 126))
    p.addCurve(to: CGPoint(x: 220, y: 110), control1: CGPoint(x: 178, y: 96), control2: CGPoint(x: 212, y: 94))
    p.addCurve(to: CGPoint(x: 221, y: 127), control1: CGPoint(x: 224, y: 118), control2: CGPoint(x: 220, y: 121))
    p.addQuadCurve(to: CGPoint(x: 232, y: 147), control: CGPoint(x: 224, y: 136))
    p.addQuadCurve(to: CGPoint(x: 219, y: 139), control: CGPoint(x: 223, y: 148))
    p.addQuadCurve(to: CGPoint(x: 208, y: 124), control: CGPoint(x: 213, y: 129))
    p.addQuadCurve(to: CGPoint(x: 198, y: 132), control: CGPoint(x: 202, y: 126))
    p.addQuadCurve(to: CGPoint(x: 193, y: 131), control: CGPoint(x: 193, y: 135))
    p.addLine(to: CGPoint(x: 195, y: 122))
    p.addQuadCurve(to: CGPoint(x: 185, y: 129), control: CGPoint(x: 188, y: 125))
    p.addQuadCurve(to: CGPoint(x: 175, y: 138), control: CGPoint(x: 179, y: 137))
    p.addLine(to: CGPoint(x: 177, y: 128))
    p.addQuadCurve(to: CGPoint(x: 159, y: 145), control: CGPoint(x: 164, y: 136))
    p.addQuadCurve(to: CGPoint(x: 149, y: 147), control: CGPoint(x: 155, y: 151))
    p.closeSubpath()
  }
  static let relaxedOutline = sectionOutline(0)
  static func sectionOutline(_ tension: Double) -> Path {
    let hinge = GalaxySSIHealthAtlasMesangialMotion.loopHinge
    func x(_ value: Double) -> Double { hinge + (value - hinge) * GalaxySSIHealthAtlasMesangialMotion.loopScale(tension) }
    var p = Path()
    p.move(to: CGPoint(x: 137, y: 153))
    p.addCurve(to: CGPoint(x: 192, y: 133), control1: CGPoint(x: 158, y: 153), control2: CGPoint(x: 155, y: 132))
    p.addCurve(to: CGPoint(x: 245, y: 209), control1: CGPoint(x: 231, y: 134), control2: CGPoint(x: 249, y: 168))
    p.addCurve(to: CGPoint(x: 194, y: 280), control1: CGPoint(x: 247, y: 250), control2: CGPoint(x: 233, y: 277))
    p.addCurve(to: CGPoint(x: 142, y: 270), control1: CGPoint(x: 169, y: 283), control2: CGPoint(x: 159, y: 270))
    p.addCurve(to: CGPoint(x: x(89), y: 284), control1: CGPoint(x: x(123), y: 270), control2: CGPoint(x: x(117), y: 284))
    p.addCurve(to: CGPoint(x: x(27), y: 207), control1: CGPoint(x: x(51), y: 283), control2: CGPoint(x: x(26), y: 247))
    p.addCurve(to: CGPoint(x: x(81), y: 133), control1: CGPoint(x: x(26), y: 169), control2: CGPoint(x: x(42), y: 133))
    p.addCurve(to: CGPoint(x: 137, y: 153), control1: CGPoint(x: x(119), y: 133), control2: CGPoint(x: x(114), y: 155))
    p.closeSubpath()
    return p
  }
}
