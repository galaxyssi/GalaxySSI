import Foundation

struct GalaxySSIHealthAtlasSmoothMuscleMotion {
  static let positions: [Double] = [58, 99, 102, 137, 239, 309]
  let center: Double
  let opening: Double
  let squeeze: Double
  let fullness: Double
  var behind: Double { center - 48 }
  var ahead: Double { center + 44 }
  var stretch: Double { 1 + squeeze / 180 }
  var heightScale: Double { (1.18 + 0.025 * fullness) / stretch }
  init(step: Int, fraction: Double) {
    let step = min(4, max(0, step)), t = fraction.isFinite ? min(1, max(0, fraction)) : 0
    center = Self.positions[step] + (Self.positions[step + 1] - Self.positions[step]) * t
    opening = step == 0 ? 0 : step == 1 ? 16 * t : step == 4 ? 16 * (1 - t) : 16
    squeeze = step == 2 ? 23 * t : step == 3 ? 23 : step == 4 ? 23 * (1 - t) : 0
    fullness = step == 0 ? 3 + 10 * t : 13
  }
  static func bump(_ distance: Double, width: Double) -> Double {
    guard distance.isFinite, width.isFinite, width > 0 else { return 0 }
    let q = max(0, 1 - abs(distance) / width)
    return q * q * (3 - 2 * q)
  }
  func squeezeAt(_ x: Double) -> Double { squeeze * Self.bump(x - behind, width: 34) }
  func openingAt(_ x: Double) -> Double { opening * Self.bump(x - ahead, width: 39) }
  func radius(_ x: Double) -> Double {
    let edge = min(1, max(0, min(x - 16, 344 - x) / 19))
    return 28 + edge * (fullness * Self.bump(x - center, width: 43) + openingAt(x) - squeezeAt(x))
  }
}
