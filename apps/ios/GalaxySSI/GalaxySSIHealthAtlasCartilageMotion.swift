import Foundation

struct GalaxySSIHealthAtlasCartilageMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  let depth: Double
  let travel: Double
  let pressure: Double
  init(step: Int, fraction: Double) {
    let t = Self.safe(fraction), f = t * t * (3 - 2 * t)
    switch step {
    case 1: depth = max(0, 23 * f - 16)
    case 2: depth = 7 + 14 * f
    case 3: depth = 21 - 4 * f
    case 4: depth = 17 * (1 - f)
    default: depth = 0
    }
    travel = step == 1 ? 23 * f : step == 2 ? 16 + depth : step == 3 ? 37 * (1 - f) : 0
    pressure = step == 1 ? depth / 7 : step == 2 ? 1 - 0.83 * f : step == 3 ? 0.17 * (1 - f) : 0
  }
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func offsetSquared(_ x: Double) -> Double { (x - 180) * (x - 180) }
  static func patellarFaceY(_ x: Double) -> Double { 168 - 0.0034 * offsetSquared(x) }
  static func baseY(_ x: Double) -> Double { 245 - 0.0007 * offsetSquared(x) }
  static func faceY(_ x: Double, depth: Double) -> Double {
    let radiusSquared = offsetSquared(x), rest = 184 - 0.0005 * radiusSquared
    guard depth > 0 else { return rest }
    let overlap = depth - 0.0029 * radiusSquared, edge = min(3, depth * 0.5)
    let localDepth = overlap >= edge ? overlap : overlap <= -edge ? 0 : (overlap + edge) * (overlap + edge) / (4 * edge)
    return rest + localDepth
  }
  static func matrixY(_ x: Double, depth: Double, fraction: Double) -> Double {
    let top = faceY(x, depth: depth)
    return top + (baseY(x) - top) * fraction
  }
  static func flowRoute(side: Int, depth: Double) -> Route {
    let start = 180 + Double(side) * 22, bend = 180 + Double(side) * 76, exit = 180 + Double(side) * 110
    return Route(start: .init(x: start, y: matrixY(start, depth: depth, fraction: 0.43)), commands: [
      .init(kind: .cubic, points: [.init(x: bend, y: matrixY(bend, depth: depth, fraction: 0.55)),
        .init(x: exit, y: faceY(exit, depth: depth) + 25), .init(x: exit, y: faceY(exit, depth: depth) - 8)])
    ])
  }
  static func flowFraction(_ t: Double, index: Int) -> Double { 0.04 + 0.92 * (safe(t) * 1.4 + Double(index) * 0.5).truncatingRemainder(dividingBy: 1) }
  static func flowAlpha(_ t: Double, returning: Bool) -> Int { returning ? Int(255 * min(1, (1 - safe(t)) * 4)) : 255 }
}
