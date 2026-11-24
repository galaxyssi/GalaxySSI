import SwiftUI

enum GalaxySSIHealthAtlasMastGeometry {
  static let granules: [CGPoint] = [
    .init(x: -42, y: -17), .init(x: -31, y: -37), .init(x: -14, y: -46), .init(x: 7, y: -44),
    .init(x: 29, y: -39), .init(x: 42, y: -23), .init(x: 48, y: -6), .init(x: 43, y: 16),
    .init(x: 36, y: 34), .init(x: 21, y: 47), .init(x: 1, y: 51), .init(x: -21, y: 45),
    .init(x: -41, y: 32), .init(x: -47, y: 9), .init(x: 21, y: -23), .init(x: 28, y: -4),
    .init(x: 22, y: 18), .init(x: 18, y: 34), .init(x: -9, y: 38), .init(x: -27, y: 28),
    .init(x: -14, y: -27), .init(x: 3, y: -25)]
  static let spokesX = [0.72, 0.88, 1, 0.98, 0.90, 0.75], spokesY = [-0.69, -0.47, -0.10, 0.20, 0.43, 0.66]
  static let releaseRim = [50.0, 59, 63, 61, 55, 46]
  static let gutTop = Path { p in
    p.move(to: CGPoint(x: 0, y: 3)); p.addLine(to: CGPoint(x: 20, y: 3))
    for i in 0...2 {
      let x = 20 + Double(i) * 48
      p.addCurve(to: CGPoint(x: x + 19, y: -21), control1: CGPoint(x: x + 8, y: 3), control2: CGPoint(x: x + 5, y: -21))
      p.addCurve(to: CGPoint(x: x + 40, y: 3), control1: CGPoint(x: x + 33, y: -21), control2: CGPoint(x: x + 30, y: 3))
      p.addLine(to: CGPoint(x: x + 48, y: 3))
    }
    p.addLine(to: CGPoint(x: 178, y: 3)); p.addLine(to: CGPoint(x: 178, y: 12)); p.addLine(to: CGPoint(x: 0, y: 12)); p.closeSubpath()
  }
  static func fusionPhase(_ index: Int) -> Double { 0.31 + 0.074 * Double(index) }
}
