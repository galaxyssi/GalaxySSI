import SwiftUI

// Original Android #4385 outlines in the source drawing coordinate system.
enum GalaxySSIHealthAtlasLatissimusGeometry {
  static let extensionTrace = guide(0, 1)
  static let adductionTrace = guide(1, 2)
  private static func guide(_ from: Double, _ to: Double) -> Path {
    Path { p in
      for i in 0...20 {
        let direction = GalaxySSIHealthAtlasLatissimusActionMotion.project(from + (to - from) * Double(i) / 20)
        let point = CGPoint(x: 220 + direction.x * 140, y: 121 + direction.y * 140)
        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
      }
    }
  }
  static let torso = Path { p in
    p.move(to: CGPoint(x: 69, y: 276))
    p.addCurve(to: CGPoint(x: 66, y: 188), control1: CGPoint(x: 60, y: 254), control2: CGPoint(x: 74, y: 222))
    p.addCurve(to: CGPoint(x: 51, y: 123), control1: CGPoint(x: 58, y: 163), control2: CGPoint(x: 50, y: 143))
    p.addCurve(to: CGPoint(x: 96, y: 89), control1: CGPoint(x: 54, y: 101), control2: CGPoint(x: 75, y: 96))
    p.addQuadCurve(to: CGPoint(x: 118, y: 63), control: CGPoint(x: 115, y: 82))
    p.addQuadCurve(to: CGPoint(x: 154, y: 67), control: CGPoint(x: 138, y: 60))
    p.addCurve(to: CGPoint(x: 196, y: 94), control1: CGPoint(x: 157, y: 84), control2: CGPoint(x: 170, y: 89))
    p.addCurve(to: CGPoint(x: 227, y: 137), control1: CGPoint(x: 220, y: 97), control2: CGPoint(x: 237, y: 117))
    p.addCurve(to: CGPoint(x: 189, y: 183), control1: CGPoint(x: 219, y: 156), control2: CGPoint(x: 201, y: 163))
    p.addCurve(to: CGPoint(x: 192, y: 264), control1: CGPoint(x: 179, y: 209), control2: CGPoint(x: 182, y: 243))
    p.addCurve(to: CGPoint(x: 69, y: 276), control1: CGPoint(x: 174, y: 289), control2: CGPoint(x: 91, y: 296))
    p.closeSubpath()
  }
  static let scapula = Path { p in
    p.move(to: CGPoint(x: 139, y: 107))
    p.addCurve(to: CGPoint(x: 211, y: 107), control1: CGPoint(x: 161, y: 108), control2: CGPoint(x: 185, y: 95))
    p.addQuadCurve(to: CGPoint(x: 217, y: 124), control: CGPoint(x: 222, y: 114))
    p.addQuadCurve(to: CGPoint(x: 205, y: 124), control: CGPoint(x: 212, y: 128))
    p.addCurve(to: CGPoint(x: 163, y: 178), control1: CGPoint(x: 195, y: 137), control2: CGPoint(x: 179, y: 163))
    p.addCurve(to: CGPoint(x: 139, y: 107), control1: CGPoint(x: 148, y: 169), control2: CGPoint(x: 138, y: 139))
    p.closeSubpath()
  }
  static let fasciaField = Path { p in
    p.move(to: CGPoint(x: 115, y: 144))
    p.addCurve(to: CGPoint(x: 142, y: 227), control1: CGPoint(x: 115, y: 168), control2: CGPoint(x: 123, y: 196))
    p.addQuadCurve(to: CGPoint(x: 170, y: 267), control: CGPoint(x: 155, y: 249))
    p.addCurve(to: CGPoint(x: 80, y: 264), control1: CGPoint(x: 142, y: 286), control2: CGPoint(x: 101, y: 282))
    p.addCurve(to: CGPoint(x: 115, y: 144), control1: CGPoint(x: 97, y: 251), control2: CGPoint(x: 113, y: 222))
    p.closeSubpath()
  }
  static let farSheet = Path { p in
    p.move(to: CGPoint(x: 114, y: 150))
    p.addCurve(to: CGPoint(x: 62, y: 130), control1: CGPoint(x: 91, y: 149), control2: CGPoint(x: 72, y: 138))
    p.addCurve(to: CGPoint(x: 80, y: 217), control1: CGPoint(x: 66, y: 171), control2: CGPoint(x: 78, y: 185))
    p.addQuadCurve(to: CGPoint(x: 78, y: 259), control: CGPoint(x: 81, y: 238))
    p.addCurve(to: CGPoint(x: 114, y: 150), control1: CGPoint(x: 102, y: 244), control2: CGPoint(x: 113, y: 194))
    p.closeSubpath()
  }
  static let arm = Path { p in
    p.move(to: CGPoint(x: -12, y: -12))
    p.addCurve(to: CGPoint(x: 83, y: -12), control1: CGPoint(x: 14, y: -21), control2: CGPoint(x: 48, y: -16))
    p.addCurve(to: CGPoint(x: 128, y: -8), control1: CGPoint(x: 102, y: -15), control2: CGPoint(x: 115, y: -12))
    p.addQuadCurve(to: CGPoint(x: 129, y: 6), control: CGPoint(x: 136, y: -1))
    p.addCurve(to: CGPoint(x: 82, y: 13), control1: CGPoint(x: 119, y: 10), control2: CGPoint(x: 102, y: 15))
    p.addCurve(to: CGPoint(x: -9, y: 14), control1: CGPoint(x: 54, y: 16), control2: CGPoint(x: 25, y: 18))
    p.addQuadCurve(to: CGPoint(x: -12, y: -12), control: CGPoint(x: -22, y: 4))
    p.closeSubpath()
  }
  static let armBone = Path { p in
    p.move(to: CGPoint(x: -10, y: -9))
    p.addCurve(to: CGPoint(x: 24, y: -7), control1: CGPoint(x: 4, y: -18), control2: CGPoint(x: 14, y: -9))
    p.addCurve(to: CGPoint(x: 80, y: -7), control1: CGPoint(x: 43, y: -3), control2: CGPoint(x: 65, y: -6))
    p.addQuadCurve(to: CGPoint(x: 91, y: 3), control: CGPoint(x: 93, y: -6))
    p.addQuadCurve(to: CGPoint(x: 77, y: 8), control: CGPoint(x: 87, y: 12))
    p.addCurve(to: CGPoint(x: 19, y: 9), control1: CGPoint(x: 58, y: 4), control2: CGPoint(x: 36, y: 6))
    p.addCurve(to: CGPoint(x: -12, y: 8), control1: CGPoint(x: 11, y: 15), control2: CGPoint(x: -8, y: 15))
    p.addQuadCurve(to: CGPoint(x: -10, y: -9), control: CGPoint(x: -16, y: 1))
    p.closeSubpath()
  }
}
