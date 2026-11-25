import Foundation

enum GalaxySSIHealthAtlasCardiacSignalMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func shortening(step: Int, fraction: Double) -> Double {
    let f = safe(fraction), ease = f * f * (3 - 2 * f)
    return step == 3 ? ease : step == 4 ? 1 - ease : 0
  }
  static func progress(step: Int, fraction: Double, route: Int) -> Double? {
    let t = safe(fraction)
    if step == 0 && (0...1).contains(route) { return t }
    if step == 2 && route == 2 { return min(1, t / 0.56) }
    if step == 2 && (3...4).contains(route) && t >= 0.56 { return (t - 0.56) / 0.44 }
    return nil
  }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: c.count == 2 ? .line : c.count == 4 ? .quad : .cubic,
        points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
    })
  }
  static let routes = [
    route(112, 48, [126,58,153,42,184,65]), route(112, 48, [112,74,121,81,140,95]),
    route(140, 95, [151,111,151,124], [153,159]), route(153, 159, [140,169,128,151,120,131]),
    route(153, 159, [169,177,188,158,197,118])
  ]
}
