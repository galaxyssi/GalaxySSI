import SwiftUI

enum GalaxySSIHealthAtlasIntercalatedGeometry {
  static let lumen = Path { p in
    p.move(to: CGPoint(x: 23, y: 73))
    p.addCurve(to: CGPoint(x: 337, y: 72), control1: CGPoint(x: 104, y: 72), control2: CGPoint(x: 254, y: 66))
    p.addLine(to: CGPoint(x: 337, y: 157))
    p.addLine(to: CGPoint(x: 23, y: 157))
    p.closeSubpath()
  }
  static let oppositeWall = Path { p in
    p.move(to: CGPoint(x: 23, y: 51))
    p.addCurve(to: CGPoint(x: 337, y: 49), control1: CGPoint(x: 112, y: 48), control2: CGPoint(x: 255, y: 42))
    p.addLine(to: CGPoint(x: 337, y: 72))
    p.addCurve(to: CGPoint(x: 23, y: 73), control1: CGPoint(x: 254, y: 66), control2: CGPoint(x: 104, y: 72))
    p.closeSubpath()
  }
  static let nearWall = Path { p in
    p.move(to: CGPoint(x: 23, y: 154))
    p.addQuadCurve(to: CGPoint(x: 129, y: 149), control: CGPoint(x: 76, y: 145))
    p.addQuadCurve(to: CGPoint(x: 218, y: 149), control: CGPoint(x: 172, y: 151))
    p.addQuadCurve(to: CGPoint(x: 337, y: 153), control: CGPoint(x: 268, y: 146))
    p.addLine(to: CGPoint(x: 337, y: 229))
    p.addQuadCurve(to: CGPoint(x: 23, y: 227), control: CGPoint(x: 179, y: 235))
    p.closeSubpath()
  }
  static let typeA = Path { p in
    p.move(to: CGPoint(x: 129, y: 149))
    p.addCurve(to: CGPoint(x: 179, y: 131), control1: CGPoint(x: 139, y: 133), control2: CGPoint(x: 157, y: 128))
    p.addQuadCurve(to: CGPoint(x: 220, y: 149), control: CGPoint(x: 204, y: 133))
    p.addCurve(to: CGPoint(x: 211, y: 224), control1: CGPoint(x: 218, y: 173), control2: CGPoint(x: 229, y: 197))
    p.addQuadCurve(to: CGPoint(x: 168, y: 231), control: CGPoint(x: 200, y: 237))
    p.addCurve(to: CGPoint(x: 125, y: 189), control1: CGPoint(x: 137, y: 232), control2: CGPoint(x: 123, y: 217))
    p.addQuadCurve(to: CGPoint(x: 129, y: 149), control: CGPoint(x: 123, y: 166))
    p.closeSubpath()
  }
  static let capillary = Path { p in
    p.move(to: CGPoint(x: 25, y: 273))
    p.addCurve(to: CGPoint(x: 216, y: 269), control1: CGPoint(x: 101, y: 259), control2: CGPoint(x: 148, y: 272))
    p.addQuadCurve(to: CGPoint(x: 335, y: 271), control: CGPoint(x: 287, y: 264))
    p.addLine(to: CGPoint(x: 335, y: 301))
    p.addQuadCurve(to: CGPoint(x: 218, y: 301), control: CGPoint(x: 284, y: 294))
    p.addCurve(to: CGPoint(x: 25, y: 306), control1: CGPoint(x: 143, y: 308), control2: CGPoint(x: 92, y: 290))
    p.closeSubpath()
  }
}
