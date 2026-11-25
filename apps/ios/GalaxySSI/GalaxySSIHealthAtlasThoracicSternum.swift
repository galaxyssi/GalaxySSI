import SwiftUI

enum GalaxySSIHealthAtlasThoracicSternum {
  static let front = Path { p in
    p.move(to: CGPoint(x: -18, y: 67))
    p.addQuadCurve(to: CGPoint(x: -7, y: 65), control: CGPoint(x: -15, y: 59))
    p.addQuadCurve(to: CGPoint(x: 7, y: 65), control: CGPoint(x: 0, y: 70))
    p.addQuadCurve(to: CGPoint(x: 18, y: 67), control: CGPoint(x: 15, y: 59))
    p.addCurve(to: CGPoint(x: 10, y: 99), control1: CGPoint(x: 21, y: 75), control2: CGPoint(x: 12, y: 84))
    p.addCurve(to: CGPoint(x: 10, y: 186), control1: CGPoint(x: 9, y: 130), control2: CGPoint(x: 14, y: 163))
    p.addQuadCurve(to: CGPoint(x: 4, y: 195), control: CGPoint(x: 7, y: 194))
    p.addQuadCurve(to: CGPoint(x: 0, y: 210), control: CGPoint(x: 5, y: 204))
    p.addQuadCurve(to: CGPoint(x: -4, y: 195), control: CGPoint(x: -6, y: 204))
    p.addQuadCurve(to: CGPoint(x: -11, y: 182), control: CGPoint(x: -10, y: 193))
    p.addCurve(to: CGPoint(x: -10, y: 99), control1: CGPoint(x: -14, y: 159), control2: CGPoint(x: -10, y: 131))
    p.addCurve(to: CGPoint(x: -18, y: 67), control1: CGPoint(x: -11, y: 87), control2: CGPoint(x: -21, y: 76))
    p.closeSubpath()
  }
  static let relief = Path { p in
    p.move(to: CGPoint(x: -5, y: 108))
    p.addCurve(to: CGPoint(x: -4, y: 180), control1: CGPoint(x: -3, y: 132), control2: CGPoint(x: -7, y: 158))
  }
  static func side(_ b: Double) -> Path {
    let x = 251+14*b
    return Path { p in
      p.move(to: CGPoint(x: x - 9, y: 67))
    p.addQuadCurve(to: CGPoint(x: x + 3, y: 67), control: CGPoint(x: x - 2, y: 60))
    p.addCurve(to: CGPoint(x: x + 15, y: 190), control1: CGPoint(x: x + 5, y: 88), control2: CGPoint(x: x + 13, y: 148))
    p.addQuadCurve(to: CGPoint(x: x + 18, y: 208), control: CGPoint(x: x + 13, y: 200))
    p.addQuadCurve(to: CGPoint(x: x + 7, y: 196), control: CGPoint(x: x + 10, y: 207))
    p.addCurve(to: CGPoint(x: x - 4, y: 99), control1: CGPoint(x: x + 4, y: 169), control2: CGPoint(x: x + 1, y: 133))
    p.addQuadCurve(to: CGPoint(x: x - 9, y: 67), control: CGPoint(x: x - 11, y: 76))
    p.closeSubpath()
    }
  }
}
