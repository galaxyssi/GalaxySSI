import Foundation

enum GalaxySSIHealthAtlasKneeMotion {
  typealias Point = GalaxySSIHealthAtlasSectionLesson.Point
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  struct Pose { let bend: Double; let extensor: Double; let flexor: Double }
  static let poses = [Pose(bend: 0.12, extensor: 0.14, flexor: 0.14), Pose(bend: 0.17, extensor: 0.16, flexor: 0.27),
    Pose(bend: 0.84, extensor: 0.18, flexor: 0.85), Pose(bend: 0.92, extensor: 0.36, flexor: 0.43),
    Pose(bend: 0.18, extensor: 0.74, flexor: 0.17), Pose(bend: 0.12, extensor: 0.14, flexor: 0.14)]
  static func at(step: Int, fraction: Double) -> Pose {
    let step = min(4, max(0, step)), t = fraction.isFinite ? min(1, max(0, fraction)) : 0, ease = t * t * (3 - 2 * t)
    let from = poses[step], to = poses[step + 1]
    func between(_ a: Double, _ b: Double) -> Double { a + (b - a) * ease }
    return Pose(bend: between(from.bend, to.bend), extensor: between(from.extensor, to.extensor), flexor: between(from.flexor, to.flexor))
  }
  static func local(_ x: Double, _ y: Double, angle: Double) -> Point {
    let radians = angle * 0.017453293
    return Point(x: 178 + x * cos(radians) - y * sin(radians), y: 192 + x * sin(radians) + y * cos(radians))
  }
  static func curve(_ x: Double, _ y: Double, _ c: [Double]) -> Route {
    .init(start: .init(x: x, y: y), commands: [.init(kind: .cubic,
      points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })])
  }
}
