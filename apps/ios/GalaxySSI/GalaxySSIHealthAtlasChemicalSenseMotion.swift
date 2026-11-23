import Foundation

struct GalaxySSIHealthAtlasChemicalSenseMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  let smell: Bool
  let chapter: Int
  let fraction: Double
  init(courseID: String, chapter: Int, fraction: Double) {
    smell = courseID == "OLFACTION"
    self.chapter = min(4, max(0, chapter)); self.fraction = Self.safePhase(fraction)
  }
  private static func safePhase(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func transfer(_ t: Double, index: Int, startsAt: Double = 0) -> Double {
    guard (0...7).contains(index), startsAt.isFinite else { return 0 }
    return min(1, max(0, (safePhase(t) - startsAt - 0.078 * Double(index)) * 1.55))
  }
  static func odorChannels(_ variant: Bool) -> [Int] { variant ? [1, 2] : [0, 2] }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: c.count == 2 ? .line : c.count == 4 ? .quad : .cubic,
        points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
    })
  }
  static let airway = route(31, 242, [47,240,65,225,96,214], [136,195,146,143,182,121], [203,109,235,119])
  static let smellRoutes: [Route] = (0..<3).map { i in
    let x = Double(79 + i * 94)
    return route(x, 218, [x-10,195,x+13,171,x,130], [x-3,100,x,88])
  }
  static let tasteNerve = route(182, 272, [192,287,214,289,229,297], [254,320,315,306])
}
