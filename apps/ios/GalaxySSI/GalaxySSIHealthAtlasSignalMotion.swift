import Foundation

struct GalaxySSIHealthAtlasSignalMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  enum Course: Equatable { case synaptic, myelin, thyroid }
  let course: Course
  let chapter: Int
  let fraction: Double
  init(courseID: String, chapter: Int, fraction: Double) {
    course = courseID == "SYNAPTIC_SIGNAL" ? .synaptic : courseID == "MYELIN_SIGNAL" ? .myelin : .thyroid
    self.chapter = min(4, max(0, chapter)); self.fraction = Self.safePhase(fraction)
  }
  private static func safePhase(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func axonTravel(_ t: Double, myelinated: Bool) -> Double { safePhase(t) * (myelinated ? 0.98 : 0.63) }
  static func upstreamDrive(_ t: Double) -> Double { 1 - 0.70 * safePhase(t) }
  static func synapticRelease(_ t: Double, index: Int) -> Double {
    guard t.isFinite, (0...4).contains(index) else { return 0 }
    return min(1, max(0, (t - 0.38 - Double(index) * 0.085) / 0.39))
  }
  static func loop(_ t: Double) -> Double { t.isFinite ? t.truncatingRemainder(dividingBy: 1) : 0 }
  static func trailStart(_ f: Double, length: Double) -> Double? {
    guard f.isFinite, (0...1).contains(f), length.isFinite, length > 0 else { return nil }
    return max(0, f - 27 / length)
  }
  static let nodes = [94.0, 160, 226, 292]
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: c.count == 2 ? .line : c.count == 4 ? .quad : .cubic,
        points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
    })
  }
  static let dendriteA = route(113, 59, [119,77,131,84,150,103])
  static let dendriteB = route(193, 58, [181,79,173,89,150,103])
  static let dendrites = [dendriteA, dendriteB]
  static let axon = route(150, 103, [153,121,150,133,158,145], [176,172,198,203,212,229], [223,253,227,264,247,270], [258,275,263,281])
  static let portal = route(189, 54, [175,65,177,79], [182,113,174,148], [154,170,130,188])
  static let tshRoute = route(77, 138, [85,207,148,212], [187,216,225,202])
  static let thyroidOut = route(137, 177, [138,210,155,229], [199,231,255,238], [305,244])
  static let dendriteLengths = dendrites.map { GalaxySSIHealthAtlasCurveLength.route($0, width: 360, height: 360) }
  static let axonLength = GalaxySSIHealthAtlasCurveLength.route(axon, width: 360, height: 360)
}
