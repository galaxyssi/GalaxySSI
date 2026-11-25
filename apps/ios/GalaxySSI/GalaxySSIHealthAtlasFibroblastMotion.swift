import Foundation

enum GalaxySSIHealthAtlasFibroblastMotion {
  typealias Point = GalaxySSIHealthAtlasSectionLesson.Point
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  struct Fiber: Equatable {
    let start: Point
    let control1: Point
    let control2: Point
    let end: Point
    init(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double) {
      start = .init(x: x0, y: y0); control1 = .init(x: x1, y: y1); control2 = .init(x: x2, y: y2); end = .init(x: x3, y: y3)
    }
    private init(start: Point, control1: Point, control2: Point, end: Point) {
      self.start = start; self.control1 = control1; self.control2 = control2; self.end = end
    }
    func interpolated(to target: Self, fraction: Double) -> Self {
      func mix(_ a: Point, _ b: Point) -> Point { .init(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction) }
      return .init(start: mix(start,target.start),control1: mix(control1,target.control1),control2: mix(control2,target.control2),end: mix(end,target.end))
    }
    var route: Route { .init(start: start, commands: [.init(kind: .cubic, points: [control1,control2,end])]) }
  }
  static func eased(_ t: Double, from: Double, to: Double) -> Double {
    let f = t.isFinite ? min(1,max(0,(t - from) / (to - from))) : 0
    return f * f * (3 - 2 * f)
  }
  static func turnover(step: Int, t: Double) -> Double { step == 4 ? eased(t,from: 0.06,to: 0.92) : 0 }
  static func arrangement(step: Int, t: Double) -> Double { step == 2 ? 0 : step == 3 ? eased(t,from: 0.08,to: 0.92) : 1 }
  static func growth(step: Int, t: Double, index: Int) -> Double { step == 2 ? eased(t,from: 0.05 + 0.11 * Double(index),to: 0.54 + 0.13 * Double(index)) : 1 }
  static func focus(_ t: Double) -> Double { eased(t,from: 0.45,to: 0.75) * (1 - eased(t,from: 0.82,to: 1)) }
  static func repairCue(_ t: Double, index: Int) -> (radius: Double, alpha: Int)? {
    guard t.isFinite else { return nil }
    let pulse = min(1,max(0,(t - 0.19 * Double(index)) / 0.78)), alpha = 4 * pulse * (1 - pulse)
    guard alpha > 0 else { return nil }
    return (7 + 40 * pulse, Int(185 * alpha))
  }
  static let scaffold: [Fiber] = [
    .init(54,162,92,143,111,164,143,150),
    .init(150,154,191,166,214,135,248,150),
    .init(248,150,267,155,283,164,298,154),
    .init(47,208,75,207,97,179,147,188),
    .init(57,225,73,201,103,207,118,190),
    .init(156,174,189,169,201,190,227,168),
    .init(62,238,95,226,122,247,151,233),
    .init(57,257,84,244,101,261,127,253),
    .init(112,262,143,254,156,225,195,234),
    .init(179,257,215,239,241,257,270,239),
    .init(249,247,270,228,285,243,299,225)
  ]
  static let outgoing: [(from: Fiber, to: Fiber)] = [
    (.init(216,182,238,166,263,192,288,171), .init(216,181,239,168,260,174,294,169)),
    (.init(231,194,261,181,276,213,299,185), .init(230,195,253,186,275,196,298,187)),
    (.init(214,215,236,200,242,238,270,217), .init(213,213,232,218,246,239,279,226)),
    (.init(202,226,221,221,224,246,243,244), .init(202,225,220,229,220,249,243,253))
  ]
  static let olderFiber = Fiber(62,181,86,160,109,186,134,171)
  static let renewedFiber = Fiber(62,183,92,178,105,158,133,170)
}
