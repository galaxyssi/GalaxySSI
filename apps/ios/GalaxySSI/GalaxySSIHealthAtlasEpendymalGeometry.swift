import SwiftUI

enum GalaxySSIHealthAtlasEpendymalGeometry {
  static let field = Path(roundedRect: CGRect(x: 1, y: 1, width: 358, height: 358), cornerRadius: 8)
  static let brainSection = Path { p in
    p.move(to: CGPoint(x: 74, y: 52))
    p.addCurve(to: CGPoint(x: 24, y: 83), control1: CGPoint(x: 53, y: 35), control2: CGPoint(x: 24, y: 56))
    p.addCurve(to: CGPoint(x: 60, y: 109), control1: CGPoint(x: 23, y: 103), control2: CGPoint(x: 41, y: 117))
    p.addQuadCurve(to: CGPoint(x: 88, y: 109), control: CGPoint(x: 74, y: 103))
    p.addCurve(to: CGPoint(x: 124, y: 83), control1: CGPoint(x: 107, y: 117), control2: CGPoint(x: 125, y: 103))
    p.addCurve(to: CGPoint(x: 74, y: 52), control1: CGPoint(x: 124, y: 56), control2: CGPoint(x: 95, y: 35))
    p.closeSubpath()
  }
  static let ventricularHorn = Path { p in
    p.move(to: CGPoint(x: 69, y: 78))
    p.addCurve(to: CGPoint(x: 44, y: 78), control1: CGPoint(x: 61, y: 70), control2: CGPoint(x: 51, y: 68))
    p.addQuadCurve(to: CGPoint(x: 60, y: 86), control: CGPoint(x: 54, y: 74))
    p.addCurve(to: CGPoint(x: 69, y: 78), control1: CGPoint(x: 63, y: 94), control2: CGPoint(x: 70, y: 96))
    p.closeSubpath()
  }
  static let bulkGuide = Path { p in
    p.move(to: CGPoint(x: 27, y: 124))
    p.addCurve(to: CGPoint(x: 328, y: 103), control1: CGPoint(x: 113, y: 109), control2: CGPoint(x: 203, y: 133))
  }
  static let channel = Path { p in
    p.move(to: CGPoint(x: 28, y: 156))
    p.addCurve(to: CGPoint(x: 331, y: 135), control1: CGPoint(x: 106, y: 131), control2: CGPoint(x: 204, y: 164))
  }
  static let leftChannel = Path { p in
    p.move(to: CGPoint(x: 167, y: 148))
    p.addCurve(to: CGPoint(x: 29, y: 156), control1: CGPoint(x: 126, y: 134), control2: CGPoint(x: 76, y: 137))
  }
  static let rightChannel = Path { p in
    p.move(to: CGPoint(x: 193, y: 153))
    p.addCurve(to: CGPoint(x: 331, y: 137), control1: CGPoint(x: 233, y: 166), control2: CGPoint(x: 290, y: 158))
  }
}
