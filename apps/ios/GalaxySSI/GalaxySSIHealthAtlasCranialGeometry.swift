import SwiftUI

enum GalaxySSIHealthAtlasCranialGeometry {
  static let eye = Path { p in
    p.move(to: CGPoint(x: -47, y: 74))
    p.addCurve(to: CGPoint(x: 0, y: 53), control1: CGPoint(x: -33, y: 55), control2: CGPoint(x: -15, y: 52))
    p.addCurve(to: CGPoint(x: 47, y: 78), control1: CGPoint(x: 22, y: 54), control2: CGPoint(x: 37, y: 64))
    p.addCurve(to: CGPoint(x: -4, y: 96), control1: CGPoint(x: 32, y: 89), control2: CGPoint(x: 17, y: 98))
    p.addCurve(to: CGPoint(x: -47, y: 74), control1: CGPoint(x: -24, y: 94), control2: CGPoint(x: -40, y: 84))
    p.closeSubpath()
  }
  static let lid = Path { p in
    p.move(to: CGPoint(x: -51, y: 72))
    p.addCurve(to: CGPoint(x: 40, y: 63), control1: CGPoint(x: -28, y: 45), control2: CGPoint(x: 10, y: 40))
    p.move(to: CGPoint(x: -47, y: 74))
    p.addCurve(to: CGPoint(x: 47, y: 78), control1: CGPoint(x: -26, y: 49), control2: CGPoint(x: 15, y: 42))
    p.move(to: CGPoint(x: -35, y: 87))
    p.addQuadCurve(to: CGPoint(x: 15, y: 100), control: CGPoint(x: -15, y: 105))
  }
  static let globeSection = Path { p in
    p.move(to: CGPoint(x: -35, y: 83))
    p.addCurve(to: CGPoint(x: 0, y: 124), control1: CGPoint(x: -32, y: 106), control2: CGPoint(x: -20, y: 122))
    p.addCurve(to: CGPoint(x: 35, y: 84), control1: CGPoint(x: 20, y: 122), control2: CGPoint(x: 33, y: 105))
    p.addQuadCurve(to: CGPoint(x: -35, y: 83), control: CGPoint(x: 0, y: 93))
    p.closeSubpath()
  }
  static let retina = Path { p in
    p.move(to: CGPoint(x: -24, y: 103))
    p.addQuadCurve(to: CGPoint(x: 0, y: 120), control: CGPoint(x: -14, y: 120))
    p.addQuadCurve(to: CGPoint(x: 24, y: 103), control: CGPoint(x: 14, y: 120))
  }
  static let lightGuide = Path { p in
    p.move(to: CGPoint(x: 56, y: 44))
    p.addQuadCurve(to: CGPoint(x: 82, y: 64), control: CGPoint(x: 71, y: 51))
  }
  static let lightIn = Path { p in
    p.move(to: CGPoint(x: 56, y: 44))
    p.addQuadCurve(to: CGPoint(x: 90, y: 75), control: CGPoint(x: 77, y: 54))
  }
  static let lightThrough = Path { p in
    p.move(to: CGPoint(x: 90, y: 91))
    p.addLine(to: CGPoint(x: 90, y: 117))
  }
  static let midbrain = Path { p in
    p.move(to: CGPoint(x: 180, y: 222))
    p.addCurve(to: CGPoint(x: 140, y: 231), control1: CGPoint(x: 163, y: 211), control2: CGPoint(x: 146, y: 220))
    p.addCurve(to: CGPoint(x: 117, y: 269), control1: CGPoint(x: 120, y: 236), control2: CGPoint(x: 111, y: 250))
    p.addCurve(to: CGPoint(x: 153, y: 312), control1: CGPoint(x: 120, y: 289), control2: CGPoint(x: 136, y: 307))
    p.addCurve(to: CGPoint(x: 180, y: 306), control1: CGPoint(x: 166, y: 317), control2: CGPoint(x: 174, y: 312))
    p.addCurve(to: CGPoint(x: 207, y: 312), control1: CGPoint(x: 186, y: 312), control2: CGPoint(x: 194, y: 317))
    p.addCurve(to: CGPoint(x: 243, y: 269), control1: CGPoint(x: 224, y: 307), control2: CGPoint(x: 240, y: 289))
    p.addCurve(to: CGPoint(x: 220, y: 231), control1: CGPoint(x: 249, y: 250), control2: CGPoint(x: 240, y: 236))
    p.addCurve(to: CGPoint(x: 180, y: 222), control1: CGPoint(x: 214, y: 220), control2: CGPoint(x: 197, y: 211))
    p.closeSubpath()
  }
  static let midbrainFolds = Path { p in
    p.move(to: CGPoint(x: 143, y: 233))
    p.addQuadCurve(to: CGPoint(x: 172, y: 228), control: CGPoint(x: 156, y: 221))
    p.move(to: CGPoint(x: 188, y: 228))
    p.addQuadCurve(to: CGPoint(x: 217, y: 233), control: CGPoint(x: 204, y: 221))
    p.move(to: CGPoint(x: 123, y: 256))
    p.addQuadCurve(to: CGPoint(x: 151, y: 252), control: CGPoint(x: 136, y: 246))
    p.move(to: CGPoint(x: 209, y: 252))
    p.addQuadCurve(to: CGPoint(x: 237, y: 256), control: CGPoint(x: 224, y: 246))
    p.move(to: CGPoint(x: 130, y: 271))
    p.addCurve(to: CGPoint(x: 164, y: 304), control1: CGPoint(x: 132, y: 288), control2: CGPoint(x: 150, y: 301))
    p.move(to: CGPoint(x: 230, y: 271))
    p.addCurve(to: CGPoint(x: 196, y: 304), control1: CGPoint(x: 228, y: 288), control2: CGPoint(x: 210, y: 301))
  }
}
