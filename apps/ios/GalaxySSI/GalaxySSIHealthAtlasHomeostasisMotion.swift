import Foundation

struct GalaxySSIHealthAtlasHomeostasisMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  let cooling: Bool
  let chapter: Int
  let fraction: Double
  init(courseID: String, chapter: Int, fraction: Double) {
    cooling = courseID == "SWEAT_COOLING"
    self.chapter = min(4, max(0, chapter))
    self.fraction = Self.safePhase(fraction)
  }
  private static func safePhase(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func liquidRemaining(_ fraction: Double, humid: Bool) -> Double {
    1 - safePhase(fraction) * (humid ? 0.35 : 0.91)
  }
  static func glycogenRemaining(_ fraction: Double) -> Double { 1 - 0.72 * safePhase(fraction) }
  var glycogenCount: Int { max(3, Int(12 * Self.glycogenRemaining(fraction))) }
  static func loop(_ t: Double) -> Double { t.isFinite ? t.truncatingRemainder(dividingBy: 1) : 0 }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: c.count == 2 ? .line : c.count == 4 ? .quad : .cubic,
        points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
    })
  }
  static let nerve = route(63, 234, [95,240,102,190,145,194])
  static let alphaExit = route(207, 158, [220,182,224,211,216,231], [257,229,308,236])
  static let liverEntry = route(40, 205, [98,205,145,209,172,211], [180,215,180,230])
  static let glucoseExit = route(176, 281, [180,244,180,216], [180,128], [206,115,266,121], [313,121])
  static let sweatDuct = route(173, 66, [173,83], [152,93,173,103], [194,113,170,125], [149,136,174,145], [174,170], [145,181,144,199], [145,227,181,230], [214,231,210,204], [208,183,183,190], [159,194,168,211], [177,223,192,216])
}
