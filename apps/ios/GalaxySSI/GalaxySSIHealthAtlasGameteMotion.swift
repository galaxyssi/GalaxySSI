import Foundation

struct GalaxySSIHealthAtlasGameteMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  let sperm: Bool
  let chapter: Int
  let fraction: Double
  static let follicleOpens = 0.30
  init(courseID: String, chapter: Int, fraction: Double) {
    sperm = courseID == "SPERM_TRANSPORT"
    self.chapter = min(4, max(0, chapter)); self.fraction = Self.safePhase(fraction)
  }
  private static func safePhase(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func release(_ t: Double) -> Double { min(1, max(0, (safePhase(t) - follicleOpens) / 0.70)) }
  static func pickup(_ t: Double) -> Double { let v = safePhase(t); return v * v * (3 - 2 * v) }
  static func ductRadius(_ x: Double, _ t: Double) -> Double {
    guard x.isFinite else { return 28 }
    let center = 16 + 328 * safePhase(t), distance = (x - center) / 26
    return 28 - 17 * exp(-distance * distance)
  }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: c.count == 2 ? .line : c.count == 4 ? .quad : .cubic,
        points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
    })
  }
  static let rete = route(94, 220, [132,223,169,214,176,186], [185,156,172,119,193,111], [211,104,222,109,243,104])
  static let epididymis = route(243, 104, [291,94,311,113,286,126], [254,141,211,122,226,146], [244,169,306,134,303,167], [300,194,231,158,236,190], [242,216,311,183,306,217], [301,245,251,207,253,238], [255,260,327,225,305,270], [288,294,266,289,249,277])
  static let vas = route(249, 277, [224,258,211,239,217,212], [225,165,200,128,217,88], [226,69,248,62,261,52])
  static let pickupPath = route(147, 202, [165,188,175,177,203,156], [232,134,253,137,275,135])
  static let ampulla = route(65, 173, [86,130,103,104,137,113], [184,126,211,173,263,175], [294,176,308,173])
}
