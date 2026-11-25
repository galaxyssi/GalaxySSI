import SwiftUI

enum GalaxySSIHealthAtlasNailGeometry {
  private typealias Motion = GalaxySSIHealthAtlasNailMotion
  static func arc(_ path: inout Path, _ from: Double, _ to: Double, _ offset: Double) {
    let half = (to - from) / 2, middle = from + half
    path.addQuadCurve(to: CGPoint(x: to, y: Motion.y(to) + offset),
      control: CGPoint(x: middle, y: Motion.y(middle) - Motion.curve * half * half + offset))
  }
  static let finger = Path { p in
    p.move(to: CGPoint(x: 22, y: 149))
    p.addCurve(to: CGPoint(x: Motion.rootX, y: Motion.y(Motion.rootX) + Motion.thickness), control1: CGPoint(x: 55, y: 152), control2: CGPoint(x: 84, y: 177))
    arc(&p, Motion.rootX, Motion.bedEnd, Motion.thickness)
    p.addCurve(to: CGPoint(x: 295, y: 202), control1: CGPoint(x: 278, y: 178), control2: CGPoint(x: 289, y: 185))
    p.addCurve(to: CGPoint(x: 280, y: 259), control1: CGPoint(x: 301, y: 220), control2: CGPoint(x: 295, y: 245))
    p.addCurve(to: CGPoint(x: 212, y: 285), control1: CGPoint(x: 264, y: 275), control2: CGPoint(x: 243, y: 283))
    p.addCurve(to: CGPoint(x: 22, y: 278), control1: CGPoint(x: 153, y: 289), control2: CGPoint(x: 113, y: 271))
    p.closeSubpath()
  }
  static let outerSkin = Path { p in
    p.move(to: CGPoint(x: Motion.bedEnd, y: Motion.y(Motion.bedEnd) + Motion.thickness))
    p.addCurve(to: CGPoint(x: 295, y: 202), control1: CGPoint(x: 278, y: 178), control2: CGPoint(x: 289, y: 185))
    p.addCurve(to: CGPoint(x: 280, y: 259), control1: CGPoint(x: 301, y: 220), control2: CGPoint(x: 295, y: 245))
    p.addCurve(to: CGPoint(x: 212, y: 285), control1: CGPoint(x: 264, y: 275), control2: CGPoint(x: 243, y: 283))
    p.addCurve(to: CGPoint(x: 22, y: 278), control1: CGPoint(x: 153, y: 289), control2: CGPoint(x: 113, y: 271))
  }
  static let fold = Path { p in
    p.move(to: CGPoint(x: 22, y: 149))
    p.addCurve(to: CGPoint(x: 96, y: 140), control1: CGPoint(x: 50, y: 151), control2: CGPoint(x: 75, y: 143))
    p.addCurve(to: CGPoint(x: 150, y: 155), control1: CGPoint(x: 121, y: 136), control2: CGPoint(x: 139, y: 142))
    p.addQuadCurve(to: CGPoint(x: 129, y: 162), control: CGPoint(x: 143, y: 160))
    p.addCurve(to: CGPoint(x: 94, y: 179), control1: CGPoint(x: 113, y: 166), control2: CGPoint(x: 101, y: 173))
    p.addCurve(to: CGPoint(x: 22, y: 181), control1: CGPoint(x: 61, y: 172), control2: CGPoint(x: 42, y: 177))
    p.closeSubpath()
  }
  static let dorsalSkin = Path { p in
    p.move(to: CGPoint(x: 22, y: 149))
    p.addCurve(to: CGPoint(x: 96, y: 140), control1: CGPoint(x: 50, y: 151), control2: CGPoint(x: 75, y: 143))
    p.addCurve(to: CGPoint(x: 150, y: 155), control1: CGPoint(x: 121, y: 136), control2: CGPoint(x: 139, y: 142))
    p.addQuadCurve(to: CGPoint(x: 137, y: 160), control: CGPoint(x: 145, y: 159))
  }
  static let phalanx = Path { p in
    p.move(to: CGPoint(x: 63, y: 236))
    p.addCurve(to: CGPoint(x: 143, y: 219), control1: CGPoint(x: 74, y: 222), control2: CGPoint(x: 112, y: 224))
    p.addCurve(to: CGPoint(x: 246, y: 195), control1: CGPoint(x: 178, y: 213), control2: CGPoint(x: 212, y: 193))
    p.addCurve(to: CGPoint(x: 264, y: 217), control1: CGPoint(x: 260, y: 193), control2: CGPoint(x: 270, y: 203))
    p.addCurve(to: CGPoint(x: 211, y: 240), control1: CGPoint(x: 257, y: 231), control2: CGPoint(x: 234, y: 235))
    p.addCurve(to: CGPoint(x: 93, y: 254), control1: CGPoint(x: 167, y: 250), control2: CGPoint(x: 119, y: 251))
    p.addCurve(to: CGPoint(x: 63, y: 236), control1: CGPoint(x: 75, y: 256), control2: CGPoint(x: 60, y: 249))
    p.closeSubpath()
  }
  static let matrix = Path { p in
    p.move(to: CGPoint(x: 94, y: 182))
    p.addCurve(to: CGPoint(x: Motion.rootX, y: Motion.y(Motion.rootX) + Motion.thickness - 2), control1: CGPoint(x: 100, y: 173), control2: CGPoint(x: 113, y: 169))
    arc(&p, Motion.rootX, Motion.matrixEnd, Motion.thickness - 2)
    p.addLine(to: CGPoint(x: Motion.matrixEnd, y: Motion.y(Motion.matrixEnd) + Motion.thickness + 6))
    p.addCurve(to: CGPoint(x: 143, y: 186), control1: CGPoint(x: 151, y: 177), control2: CGPoint(x: 152, y: 185))
    p.addCurve(to: CGPoint(x: 126, y: 195), control1: CGPoint(x: 134, y: 187), control2: CGPoint(x: 137, y: 195))
    p.addCurve(to: CGPoint(x: 104, y: 202), control1: CGPoint(x: 117, y: 194), control2: CGPoint(x: 114, y: 204))
    p.addQuadCurve(to: CGPoint(x: 94, y: 182), control: CGPoint(x: 91, y: 201))
    p.closeSubpath()
  }
  static let bed = Path { p in
    p.move(to: CGPoint(x: Motion.matrixEnd, y: Motion.y(Motion.matrixEnd) + Motion.thickness - 1))
    arc(&p, Motion.matrixEnd, Motion.bedEnd, Motion.thickness - 1)
    p.addLine(to: CGPoint(x: Motion.bedEnd, y: Motion.y(Motion.bedEnd) + Motion.thickness + 6))
    arc(&p, Motion.bedEnd, Motion.matrixEnd, Motion.thickness + 6)
    p.closeSubpath()
  }
  static func plate(_ tip: Double) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: Motion.rootX, y: Motion.y(Motion.rootX)))
    arc(&p, Motion.rootX, tip - 3, 0)
    p.addQuadCurve(to: CGPoint(x: tip, y: Motion.y(tip) + 3), control: CGPoint(x: tip, y: Motion.y(tip)))
    p.addLine(to: CGPoint(x: tip, y: Motion.y(tip) + 7))
    p.addQuadCurve(to: CGPoint(x: tip - 3, y: Motion.y(tip - 3) + Motion.thickness), control: CGPoint(x: tip, y: Motion.y(tip) + 10))
    arc(&p, tip - 3, Motion.rootX, Motion.thickness)
    p.addCurve(to: CGPoint(x: 96, y: 186), control1: CGPoint(x: 113, y: 176), control2: CGPoint(x: 105, y: 187))
    p.addCurve(to: CGPoint(x: 97, y: 175), control1: CGPoint(x: 89, y: 184), control2: CGPoint(x: 92, y: 177))
    p.addCurve(to: CGPoint(x: Motion.rootX, y: Motion.y(Motion.rootX)), control1: CGPoint(x: 106, y: 169), control2: CGPoint(x: 116, y: 166))
    p.closeSubpath()
    return p
  }
  static func band(_ from: Double, _ to: Double, _ offset: Double) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: from, y: Motion.y(from) + offset))
    arc(&p, from, to, offset)
    return p
  }
}
