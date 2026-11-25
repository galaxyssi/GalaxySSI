import SwiftUI

enum GalaxySSIHealthAtlasObliqueGeometry {
  static let pelvis = Path { p in
    p.move(to: CGPoint(x: 180, y: 98))
    p.addCurve(to: CGPoint(x: 132, y: 116), control1: CGPoint(x: 161, y: 96), control2: CGPoint(x: 145, y: 104))
    p.addCurve(to: CGPoint(x: 82, y: 177), control1: CGPoint(x: 105, y: 131), control2: CGPoint(x: 85, y: 150))
    p.addCurve(to: CGPoint(x: 136, y: 232), control1: CGPoint(x: 78, y: 207), control2: CGPoint(x: 104, y: 231))
    p.addQuadCurve(to: CGPoint(x: 165, y: 243), control: CGPoint(x: 154, y: 230))
    p.addQuadCurve(to: CGPoint(x: 195, y: 243), control: CGPoint(x: 180, y: 257))
    p.addQuadCurve(to: CGPoint(x: 224, y: 232), control: CGPoint(x: 206, y: 230))
    p.addCurve(to: CGPoint(x: 278, y: 177), control1: CGPoint(x: 256, y: 231), control2: CGPoint(x: 282, y: 207))
    p.addCurve(to: CGPoint(x: 228, y: 116), control1: CGPoint(x: 275, y: 150), control2: CGPoint(x: 255, y: 131))
    p.addCurve(to: CGPoint(x: 180, y: 98), control1: CGPoint(x: 215, y: 104), control2: CGPoint(x: 199, y: 96))
    p.closeSubpath()
    p.move(to: CGPoint(x: 180, y: 116))
    p.addCurve(to: CGPoint(x: 111, y: 158), control1: CGPoint(x: 152, y: 116), control2: CGPoint(x: 123, y: 137))
    p.addCurve(to: CGPoint(x: 144, y: 216), control1: CGPoint(x: 97, y: 184), control2: CGPoint(x: 110, y: 215))
    p.addQuadCurve(to: CGPoint(x: 168, y: 227), control: CGPoint(x: 160, y: 217))
    p.addQuadCurve(to: CGPoint(x: 192, y: 227), control: CGPoint(x: 180, y: 237))
    p.addQuadCurve(to: CGPoint(x: 216, y: 216), control: CGPoint(x: 200, y: 217))
    p.addCurve(to: CGPoint(x: 249, y: 158), control1: CGPoint(x: 250, y: 215), control2: CGPoint(x: 263, y: 184))
    p.addCurve(to: CGPoint(x: 180, y: 116), control1: CGPoint(x: 237, y: 137), control2: CGPoint(x: 208, y: 116))
    p.closeSubpath()
  }
  static let hipContours = Path { p in
    p.move(to: CGPoint(x: 180, y: 100))
    p.addLine(to: CGPoint(x: 180, y: 115))
    p.move(to: CGPoint(x: 89, y: 182))
    p.addCurve(to: CGPoint(x: 134, y: 225), control1: CGPoint(x: 88, y: 207), control2: CGPoint(x: 108, y: 223))
    p.move(to: CGPoint(x: 271, y: 182))
    p.addCurve(to: CGPoint(x: 226, y: 225), control1: CGPoint(x: 272, y: 207), control2: CGPoint(x: 252, y: 223))
    p.move(to: CGPoint(x: 162, y: 235))
    p.addQuadCurve(to: CGPoint(x: 198, y: 235), control: CGPoint(x: 180, y: 247))
  }
  static let ribs = Path { p in
    p.move(to: CGPoint(x: 180, y: 126))
    p.addCurve(to: CGPoint(x: 116, y: 151), control1: CGPoint(x: 161, y: 125), control2: CGPoint(x: 131, y: 135))
    p.addCurve(to: CGPoint(x: 127, y: 199), control1: CGPoint(x: 101, y: 167), control2: CGPoint(x: 111, y: 188))
    p.addCurve(to: CGPoint(x: 180, y: 215), control1: CGPoint(x: 144, y: 212), control2: CGPoint(x: 166, y: 214))
    p.addCurve(to: CGPoint(x: 233, y: 199), control1: CGPoint(x: 194, y: 214), control2: CGPoint(x: 216, y: 212))
    p.addCurve(to: CGPoint(x: 244, y: 151), control1: CGPoint(x: 249, y: 188), control2: CGPoint(x: 259, y: 167))
    p.addCurve(to: CGPoint(x: 180, y: 126), control1: CGPoint(x: 229, y: 135), control2: CGPoint(x: 199, y: 125))
    p.closeSubpath()
  }
  static let ribContours = Path { p in
    for side in [-1.0,1.0] {
      p.move(to: CGPoint(x: 180, y: 134))
      p.addCurve(to: CGPoint(x: 180 + side * 63, y: 174), control1: CGPoint(x: 180 + side * 28, y: 133), control2: CGPoint(x: 180 + side * 64, y: 152))
      p.addQuadCurve(to: CGPoint(x: 180 + side * 14, y: 205), control: CGPoint(x: 180 + side * 61, y: 195))
      p.move(to: CGPoint(x: 180, y: 145))
      p.addCurve(to: CGPoint(x: 180 + side * 51, y: 175), control1: CGPoint(x: 180 + side * 23, y: 143), control2: CGPoint(x: 180 + side * 48, y: 155))
      p.addQuadCurve(to: CGPoint(x: 180 + side * 14, y: 197), control: CGPoint(x: 180 + side * 48, y: 193))
    }
  }
}
