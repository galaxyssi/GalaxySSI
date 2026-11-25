import Foundation

enum GalaxySSIHealthAtlasAirwayMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  private static func safePhase(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func surfaceTravel(step: Int, fraction: Double) -> Double {
    switch step {
    case 3: return safePhase(fraction) * 0.84
    case 4: return 0.84 + 0.16 * safePhase(fraction)
    default: return 0
    }
  }
  static func fall(step: Int, fraction: Double, index: Int) -> Double {
    step == 0 ? min(1, max(0, safePhase(fraction) * 1.42 - Double(index) * 0.13)) : 1
  }
  static func secretion(_ t: Double, index: Int) -> Double {
    min(1, max(0, (safePhase(t) - Double(index + 1) * 0.14) * 1.38))
  }
  static func ciliaryBeat(step: Int, fraction: Double, column: Int, fiber: Int) -> Double {
    (2...4).contains(step) ? 13 * sin((safePhase(fraction) * 2 - 0.13 * Double(column) - 0.035 * Double(fiber)) * 2 * .pi) : 2
  }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: .cubic, points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
    })
  }
  static let clearance = route(61, 109, [70,102,87,98,95,89], [99,75,94,51,95,34])
  static let toEsophagus = route(95, 34, [104,24,111,32,108,48], [109,61,118,69,123,79])
}
