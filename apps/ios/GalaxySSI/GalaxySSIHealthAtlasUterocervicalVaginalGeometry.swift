import SwiftUI

// Android #4385 declarations evaluated with original Float arithmetic and relative controls.
enum GalaxySSIHealthAtlasUterocervicalVaginalGeometry {
  static let deepVaginalWall = Path { p in
    p.move(to: CGPoint(x: 199, y: 104))
    p.addQuadCurve(to: CGPoint(x: 235, y: 107), control: CGPoint(x: 217, y: 98))
    p.addCurve(to: CGPoint(x: 256, y: 267), control1: CGPoint(x: 211, y: 138), control2: CGPoint(x: 218, y: 209))
    p.addQuadCurve(to: CGPoint(x: 230, y: 274), control: CGPoint(x: 245, y: 279))
    p.addCurve(to: CGPoint(x: 199, y: 104), control1: CGPoint(x: 191, y: 228), control2: CGPoint(x: 175, y: 150))
    p.closeSubpath()
  }
  static let muscleVaginalWall = Path { p in
    p.move(to: CGPoint(x: 210, y: 102))
    p.addQuadCurve(to: CGPoint(x: 235, y: 107), control: CGPoint(x: 223, y: 102))
    p.addCurve(to: CGPoint(x: 256, y: 267), control1: CGPoint(x: 211, y: 148), control2: CGPoint(x: 220, y: 213))
    p.addQuadCurve(to: CGPoint(x: 240, y: 275), control: CGPoint(x: 251, y: 273))
    p.addCurve(to: CGPoint(x: 210, y: 102), control1: CGPoint(x: 206, y: 235), control2: CGPoint(x: 185, y: 154))
    p.closeSubpath()
  }
  static let facingVaginalWall = Path { p in
    p.move(to: CGPoint(x: 258, y: 104))
    p.addQuadCurve(to: CGPoint(x: 289, y: 111), control: CGPoint(x: 277, y: 101))
    p.addCurve(to: CGPoint(x: 291, y: 259), control1: CGPoint(x: 260, y: 154), control2: CGPoint(x: 276, y: 230))
    p.addQuadCurve(to: CGPoint(x: 273, y: 271), control: CGPoint(x: 285, y: 271))
    p.addCurve(to: CGPoint(x: 258, y: 104), control1: CGPoint(x: 255, y: 244), control2: CGPoint(x: 232, y: 150))
    p.closeSubpath()
  }
  static let vaginalMuscleFibers = Path { p in
    p.move(to: CGPoint(x: 209, y: 120))
    p.addCurve(to: CGPoint(x: 237, y: 260), control1: CGPoint(x: 193, y: 155), control2: CGPoint(x: 209, y: 225))
    p.move(to: CGPoint(x: 213, y: 120))
    p.addCurve(to: CGPoint(x: 241, y: 260), control1: CGPoint(x: 197, y: 155), control2: CGPoint(x: 213, y: 225))
    p.move(to: CGPoint(x: 217, y: 120))
    p.addCurve(to: CGPoint(x: 245, y: 260), control1: CGPoint(x: 201, y: 155), control2: CGPoint(x: 217, y: 225))
  }
}
