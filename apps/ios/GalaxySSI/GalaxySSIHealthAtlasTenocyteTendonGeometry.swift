import SwiftUI

enum GalaxySSIHealthAtlasTenocyteTendonGeometry {
  static let fiberYs: [Double] = [78, 89, 106, 119, 167, 179, 196, 208]
  static let field = Path(roundedRect: CGRect(x: 20, y: 70, width: 320, height: 147), cornerRadius: 8)
  static func deformation(step: Int, fraction: Double) -> Double {
    let t = GalaxySSIHealthAtlasFunctionCatalogue.Story.safePhase(fraction)
    let eased = t * t * (3 - 2 * t)
    switch step {
    case 1: return 0.56 * eased
    case 2: return 0.56 + 0.44 * eased
    case 3: return 1 - eased
    default: return 0
    }
  }
  static func fiber(x: Double, y: Double, spread: Double, rise: Double) -> Path {
    Path { p in
      p.move(to: CGPoint(x: x - 190 * spread, y: y))
      p.addCurve(to: CGPoint(x: x - 46 * spread, y: y), control1: CGPoint(x: x - 148 * spread, y: y - rise), control2: CGPoint(x: x - 84 * spread, y: y + rise))
      p.addCurve(to: CGPoint(x: x + 46 * spread, y: y), control1: CGPoint(x: x - 14 * spread, y: y - rise), control2: CGPoint(x: x + 15 * spread, y: y + rise))
      p.addCurve(to: CGPoint(x: x + 190 * spread, y: y), control1: CGPoint(x: x + 86 * spread, y: y - rise), control2: CGPoint(x: x + 145 * spread, y: y + rise))
    }
  }
  static func cell(x: Double, y: Double, length: Double, height: Double, amount: Double) -> Path {
    let halfLength = length * (1 + 0.23 * amount), halfHeight = height * (1 - 0.12 * amount)
    let skew = halfHeight * 0.64 * amount
    return Path { p in
      p.move(to: CGPoint(x: x - halfLength, y: y + skew))
      p.addCurve(to: CGPoint(x: x + halfLength, y: y - skew), control1: CGPoint(x: x - 0.44 * halfLength, y: y - halfHeight + skew), control2: CGPoint(x: x + 0.12 * halfLength, y: y - halfHeight - skew))
      p.addCurve(to: CGPoint(x: x - halfLength, y: y + skew), control1: CGPoint(x: x + 0.24 * halfLength, y: y + halfHeight - skew), control2: CGPoint(x: x - 0.40 * halfLength, y: y + halfHeight + skew))
      p.closeSubpath()
    }
  }
}
