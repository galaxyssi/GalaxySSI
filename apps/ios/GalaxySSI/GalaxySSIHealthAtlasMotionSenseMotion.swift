import Foundation

struct GalaxySSIHealthAtlasMotionSenseMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  let balance: Bool
  let chapter: Int
  let fraction: Double
  init(courseID: String, chapter: Int, fraction: Double) {
    balance = courseID == "VESTIBULAR_BALANCE"
    self.chapter = min(4, max(0, chapter)); self.fraction = Self.safePhase(fraction)
  }
  private static func safePhase(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func touchLoad(step: Int, time: Double) -> Double {
    let t = safePhase(time)
    switch step {
    case 0: return max(0, (t - 0.31) / 0.69)
    case 1: return 0.66 + 0.20 * t
    case 2: return 0.48 + 0.46 * t
    case 3: return 0.91
    default: return 0.91 * max(0, 1 - t / 0.74)
    }
  }
  static func headHeading(_ t: Double) -> Double { 31 * safePhase(t) }
  static func gazeCounterRotation(_ t: Double) -> Double { -headHeading(t) }
  static func relativeFluid(_ t: Double) -> Double { -16 * sin(.pi * safePhase(t)) }
  static func deflection(_ x: Double, load: Double) -> Double {
    guard x.isFinite, load.isFinite else { return 0 }
    let distance = (x - 179) / 58
    return 29 * load * exp(-distance * distance)
  }
  static func touchLift(step: Int, time: Double) -> Double {
    let t = safePhase(time)
    return step == 0 ? 22 * max(0, 1 - t / 0.31) : step == 4 ? 28 * max(0, (t - 0.74) / 0.26) : 0
  }
  static func pressure(sample: Int) -> Double { min(1, max(0, Double(sample) / 41)) * 42 }
  static func spike(sample: Int) -> Bool { sample > 27 && sample % (sample < 75 ? 11 : 31) < 2 }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: c.count == 2 ? .line : c.count == 4 ? .quad : .cubic,
        points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
    })
  }
  static let canal = route(142, 238, [100,206,130,120,178,107], [238,95,269,154,233,204], [219,223,204,235,188,247])
  static let lateralCanal = route(164, 245, [121,243,56,222,61,191], [66,162,124,173,158,195], [196,213,235,218,212,243], [198,254,181,253])
  static let posteriorCanal = route(153, 242, [105,229,72,149,94,105], [108,68,145,78,168,120], [199,175,179,214,173,244])
  static let touchNerve = route(179, 205, [194,226,178,238,210,253], [234,265,244,286,307,283])
}
