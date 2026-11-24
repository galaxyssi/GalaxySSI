import SwiftUI

// Exact Android #4385 SVG coordinates, including relative and reflected quadratic controls.
enum GalaxySSIHealthAtlasVertebralGeometry {
  static let body = Path { p in
    p.move(to: CGPoint(x: 73, y: 63))
    p.addQuadCurve(to: CGPoint(x: 163, y: 62), control: CGPoint(x: 117, y: 56))
    p.addQuadCurve(to: CGPoint(x: 174, y: 70), control: CGPoint(x: 172, y: 63))
    p.addLine(to: CGPoint(x: 171, y: 122))
    p.addQuadCurve(to: CGPoint(x: 166, y: 139), control: CGPoint(x: 173, y: 134))
    p.addLine(to: CGPoint(x: 73, y: 139))
    p.addQuadCurve(to: CGPoint(x: 64, y: 126), control: CGPoint(x: 63, y: 136))
    p.addLine(to: CGPoint(x: 63, y: 79))
    p.addQuadCurve(to: CGPoint(x: 73, y: 63), control: CGPoint(x: 63, y: 67))
    p.closeSubpath()
  }
  static let arch = Path { p in
    p.move(to: CGPoint(x: 168, y: 84))
    p.addCurve(to: CGPoint(x: 207, y: 68), control1: CGPoint(x: 183, y: 81), control2: CGPoint(x: 197, y: 76))
    p.addLine(to: CGPoint(x: 213, y: 53))
    p.addQuadCurve(to: CGPoint(x: 220, y: 46), control: CGPoint(x: 215, y: 44))
    p.addLine(to: CGPoint(x: 246, y: 60))
    p.addQuadCurve(to: CGPoint(x: 247, y: 68), control: CGPoint(x: 251, y: 63))
    p.addLine(to: CGPoint(x: 240, y: 75))
    p.addQuadCurve(to: CGPoint(x: 257, y: 81), control: CGPoint(x: 246, y: 80))
    p.addLine(to: CGPoint(x: 289, y: 82))
    p.addQuadCurve(to: CGPoint(x: 300, y: 92), control: CGPoint(x: 301, y: 83))
    p.addLine(to: CGPoint(x: 295, y: 103))
    p.addQuadCurve(to: CGPoint(x: 276, y: 108), control: CGPoint(x: 289, y: 109))
    p.addLine(to: CGPoint(x: 252, y: 109))
    p.addQuadCurve(to: CGPoint(x: 234, y: 124), control: CGPoint(x: 237, y: 111))
    p.addLine(to: CGPoint(x: 247, y: 150))
    p.addQuadCurve(to: CGPoint(x: 245, y: 158), control: CGPoint(x: 251, y: 156))
    p.addQuadCurve(to: CGPoint(x: 234, y: 155), control: CGPoint(x: 240, y: 158))
    p.addLine(to: CGPoint(x: 215, y: 145))
    p.addQuadCurve(to: CGPoint(x: 209, y: 133), control: CGPoint(x: 207, y: 141))
    p.addLine(to: CGPoint(x: 209, y: 122))
    p.addQuadCurve(to: CGPoint(x: 197, y: 109), control: CGPoint(x: 208, y: 109))
    p.addQuadCurve(to: CGPoint(x: 170, y: 116), control: CGPoint(x: 183, y: 109))
    p.closeSubpath()
  }
  static let bodyLight = Path { p in
    p.move(to: CGPoint(x: 70, y: 80))
    p.addQuadCurve(to: CGPoint(x: 81, y: 68), control: CGPoint(x: 71, y: 69))
    p.addQuadCurve(to: CGPoint(x: 161, y: 69), control: CGPoint(x: 119, y: 64))
    p.move(to: CGPoint(x: 70, y: 91))
    p.addLine(to: CGPoint(x: 71, y: 124))
    p.addQuadCurve(to: CGPoint(x: 77, y: 133), control: CGPoint(x: 71, y: 132))
  }
  static let bodyGrain = Path { p in
    p.move(to: CGPoint(x: 81, y: 78))
    p.addQuadCurve(to: CGPoint(x: 82, y: 106), control: CGPoint(x: 89, y: 90))
    p.addQuadCurve(to: CGPoint(x: 85, y: 126), control: CGPoint(x: 75, y: 122))
    p.move(to: CGPoint(x: 104, y: 76))
    p.addQuadCurve(to: CGPoint(x: 104, y: 106), control: CGPoint(x: 112, y: 88))
    p.addQuadCurve(to: CGPoint(x: 108, y: 129), control: CGPoint(x: 96, y: 124))
    p.move(to: CGPoint(x: 128, y: 76))
    p.addQuadCurve(to: CGPoint(x: 129, y: 109), control: CGPoint(x: 137, y: 90))
    p.addQuadCurve(to: CGPoint(x: 132, y: 128), control: CGPoint(x: 121, y: 128))
    p.move(to: CGPoint(x: 151, y: 76))
    p.addQuadCurve(to: CGPoint(x: 151, y: 108), control: CGPoint(x: 160, y: 89))
    p.addQuadCurve(to: CGPoint(x: 151, y: 129), control: CGPoint(x: 142, y: 127))
  }
  static let archLight = Path { p in
    p.move(to: CGPoint(x: 177, y: 91))
    p.addQuadCurve(to: CGPoint(x: 212, y: 75), control: CGPoint(x: 197, y: 89))
    p.addQuadCurve(to: CGPoint(x: 234, y: 79), control: CGPoint(x: 222, y: 71))
    p.addQuadCurve(to: CGPoint(x: 286, y: 89), control: CGPoint(x: 252, y: 90))
    p.move(to: CGPoint(x: 218, y: 122))
    p.addQuadCurve(to: CGPoint(x: 216, y: 136), control: CGPoint(x: 220, y: 130))
  }
  static let upperJoint = Path { p in
    p.move(to: CGPoint(x: 216, y: 145))
    p.addQuadCurve(to: CGPoint(x: 244, y: 157), control: CGPoint(x: 232, y: 152))
  }
  static let lowerJoint = Path { p in
    p.move(to: CGPoint(x: 219, y: 46))
    p.addLine(to: CGPoint(x: 246, y: 60))
  }
  static let endplateTop = Path { p in
    p.move(to: CGPoint(x: 73, y: 139))
    p.addLine(to: CGPoint(x: 166, y: 139))
  }
  static let endplateBottom = Path { p in
    p.move(to: CGPoint(x: 73, y: 63))
    p.addQuadCurve(to: CGPoint(x: 163, y: 62), control: CGPoint(x: 117, y: 56))
  }
  static let neutralEndplate = Path { p in
    p.move(to: CGPoint(x: 61, y: 139))
    p.addLine(to: CGPoint(x: 177, y: 139))
  }
  static let neutralJoint = Path { p in
    p.move(to: CGPoint(x: 215, y: 145))
    p.addQuadCurve(to: CGPoint(x: 247, y: 158), control: CGPoint(x: 232, y: 152))
  }
}
