import Foundation

enum GalaxySSIHealthAtlasEndothelialMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static func travel(_ t: Double, delay: Int = 0) -> Double {
    let time = t.isFinite ? min(1, max(0, t)) : 0
    let f = min(1, max(0, (time - 0.08 - 0.09 * Double(delay)) / 0.66))
    return f * f * (3 - 2 * f)
  }
  static func waterTissueX(_ i: Int) -> Double { 121 + 17 * Double(i) }
  static func waterTissueY(_ i: Int) -> Double { 194 + 9 * Double(i) }
  static let lymphRoutes: [Route] = (0..<3).map { i in
    let x = waterTissueX(i), y = waterTissueY(i)
    return Route(start: .init(x: x, y: y), commands: [
      .init(kind: .cubic, points: [.init(x: x - 6, y: y + 34), .init(x: x - 4, y: 262), .init(x: x + 2, y: 275)]),
      .init(kind: .quad, points: [.init(x: x + 9, y: 292), .init(x: x + 31, y: 287 - 2 * Double(i))])
    ])
  }
}
