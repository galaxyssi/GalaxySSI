import SwiftUI

enum GalaxySSIHealthAtlasDeltoidGeometry {
  static let torso = Path { p in
    p.move(to: CGPoint(x: 55, y: 306))
    p.addCurve(to: CGPoint(x: 64, y: 177), control1: CGPoint(x: 63, y: 268), control2: CGPoint(x: 66, y: 214))
    p.addCurve(to: CGPoint(x: 103, y: 101), control1: CGPoint(x: 61, y: 141), control2: CGPoint(x: 66, y: 112))
    p.addCurve(to: CGPoint(x: 131, y: 71), control1: CGPoint(x: 125, y: 94), control2: CGPoint(x: 129, y: 85))
    p.addQuadCurve(to: CGPoint(x: 157, y: 77), control: CGPoint(x: 145, y: 66))
    p.addCurve(to: CGPoint(x: 207, y: 104), control1: CGPoint(x: 158, y: 93), control2: CGPoint(x: 177, y: 101))
    p.addCurve(to: CGPoint(x: 185, y: 176), control1: CGPoint(x: 220, y: 114), control2: CGPoint(x: 211, y: 150))
    p.addCurve(to: CGPoint(x: 185, y: 306), control1: CGPoint(x: 164, y: 222), control2: CGPoint(x: 181, y: 268))
    p.addQuadCurve(to: CGPoint(x: 55, y: 306), control: CGPoint(x: 118, y: 322))
    p.closeSubpath()
  }
  static let blade = Path { p in
    p.move(to: CGPoint(x: 111, y: 124))
    p.addCurve(to: CGPoint(x: 180, y: 118), control1: CGPoint(x: 124, y: 113), control2: CGPoint(x: 151, y: 129))
    p.addQuadCurve(to: CGPoint(x: 208, y: 105), control: CGPoint(x: 188, y: 106))
    p.addQuadCurve(to: CGPoint(x: 223, y: 113), control: CGPoint(x: 224, y: 104))
    p.addQuadCurve(to: CGPoint(x: 201, y: 121), control: CGPoint(x: 218, y: 118))
    p.addCurve(to: CGPoint(x: 204, y: 134), control1: CGPoint(x: 195, y: 129), control2: CGPoint(x: 197, y: 131))
    p.addCurve(to: CGPoint(x: 200, y: 158), control1: CGPoint(x: 208, y: 138), control2: CGPoint(x: 208, y: 151))
    p.addCurve(to: CGPoint(x: 169, y: 192), control1: CGPoint(x: 188, y: 164), control2: CGPoint(x: 181, y: 174))
    p.addQuadCurve(to: CGPoint(x: 126, y: 240), control: CGPoint(x: 145, y: 219))
    p.addCurve(to: CGPoint(x: 107, y: 146), control1: CGPoint(x: 113, y: 242), control2: CGPoint(x: 106, y: 174))
    p.addQuadCurve(to: CGPoint(x: 111, y: 124), control: CGPoint(x: 106, y: 132))
    p.closeSubpath()
  }
  static let ridge = Path { p in
    p.move(to: CGPoint(x: 113, y: 150))
    p.addCurve(to: CGPoint(x: 190, y: 115), control1: CGPoint(x: 141, y: 139), control2: CGPoint(x: 172, y: 132))
    p.addQuadCurve(to: CGPoint(x: 218, y: 109), control: CGPoint(x: 203, y: 106))
    p.move(to: CGPoint(x: 120, y: 158))
    p.addQuadCurve(to: CGPoint(x: 175, y: 134), control: CGPoint(x: 148, y: 153))
  }
  static let bladeContour = Path { p in
    p.move(to: CGPoint(x: 116, y: 160))
    p.addCurve(to: CGPoint(x: 166, y: 143), control1: CGPoint(x: 125, y: 160), control2: CGPoint(x: 149, y: 153))
    p.move(to: CGPoint(x: 119, y: 169))
    p.addQuadCurve(to: CGPoint(x: 126, y: 222), control: CGPoint(x: 118, y: 198))
  }
  static let arm = Path { p in
    p.move(to: CGPoint(x: 185, y: 142))
    p.addCurve(to: CGPoint(x: 212, y: 121), control1: CGPoint(x: 184, y: 127), control2: CGPoint(x: 199, y: 119))
    p.addCurve(to: CGPoint(x: 238, y: 158), control1: CGPoint(x: 234, y: 123), control2: CGPoint(x: 242, y: 142))
    p.addCurve(to: CGPoint(x: 227, y: 267), control1: CGPoint(x: 230, y: 189), control2: CGPoint(x: 235, y: 224))
    p.addQuadCurve(to: CGPoint(x: 185, y: 270), control: CGPoint(x: 207, y: 277))
    p.addCurve(to: CGPoint(x: 186, y: 172), control1: CGPoint(x: 183, y: 230), control2: CGPoint(x: 190, y: 194))
    p.addQuadCurve(to: CGPoint(x: 185, y: 142), control: CGPoint(x: 182, y: 157))
    p.closeSubpath()
  }
  static let humerus = Path { p in
    p.move(to: CGPoint(x: 188, y: 139))
    p.addCurve(to: CGPoint(x: 212, y: 130), control1: CGPoint(x: 191, y: 125), control2: CGPoint(x: 204, y: 124))
    p.addQuadCurve(to: CGPoint(x: 225, y: 151), control: CGPoint(x: 228, y: 130))
    p.addCurve(to: CGPoint(x: 219, y: 226), control1: CGPoint(x: 214, y: 174), control2: CGPoint(x: 224, y: 202))
    p.addQuadCurve(to: CGPoint(x: 218, y: 261), control: CGPoint(x: 216, y: 239))
    p.addQuadCurve(to: CGPoint(x: 199, y: 261), control: CGPoint(x: 209, y: 265))
    p.addCurve(to: CGPoint(x: 193, y: 159), control1: CGPoint(x: 201, y: 221), control2: CGPoint(x: 201, y: 177))
    p.addQuadCurve(to: CGPoint(x: 188, y: 139), control: CGPoint(x: 185, y: 149))
    p.closeSubpath()
  }
  static let armContour = Path { p in
    p.move(to: CGPoint(x: 212, y: 166))
    p.addCurve(to: CGPoint(x: 210, y: 250), control1: CGPoint(x: 208, y: 191), control2: CGPoint(x: 215, y: 211))
  }
}
