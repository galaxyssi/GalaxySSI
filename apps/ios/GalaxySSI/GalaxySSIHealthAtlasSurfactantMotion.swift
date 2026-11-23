import Foundation

enum GalaxySSIHealthAtlasSurfactantMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func width(step: Int, fraction: Double) -> Double {
    let breath = step == 3 ? safe(fraction) : step == 4 ? 1 - safe(fraction) : 0
    return 0.89 + 0.18 * breath
  }
  static func stretch(_ x: Double, center: Double, width: Double) -> Double { center + (x - center) * width }
  static func approach(_ t: Double) -> Double { min(1, safe(t) / 0.48) }
  static func release(_ t: Double) -> Double { min(1, max(0, (safe(t) - 0.48) / 0.52)) }
  static func spread(_ t: Double, side: Int) -> Double {
    let fraction = max(0, (safe(t) - 0.2) / 0.8), span = side < 0 ? 0.32 : 0.60
    return 0.35 + Double(side) * span * fraction
  }
  static func surfaceRoute(_ y: Double) -> Route {
    .init(start: .init(x: 28, y: y + 3), commands: [
      .init(kind: .cubic, points: [.init(x: 53, y: y + 8), .init(x: 74, y: y + 6), .init(x: 87, y: y)]),
      .init(kind: .cubic, points: [.init(x: 99, y: y - 7), .init(x: 96, y: y - 34), .init(x: 125, y: y - 34)]),
      .init(kind: .cubic, points: [.init(x: 150, y: y - 34), .init(x: 150, y: y - 11), .init(x: 170, y: y - 4)]),
      .init(kind: .cubic, points: [.init(x: 216, y: y + 13), .init(x: 274, y: y - 4), .init(x: 332, y: y + 4)])
    ])
  }
  static let filmTrack = surfaceRoute(230)
}
