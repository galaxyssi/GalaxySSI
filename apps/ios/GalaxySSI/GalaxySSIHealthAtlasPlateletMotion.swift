import Foundation

enum GalaxySSIHealthAtlasPlateletMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  struct Pose: Equatable { let x: Double; let y: Double; let angle: Double }
  struct Arrival { let from: Pose; let to: Pose; let delay: Double }
  static let anchor = Arrival(from: Pose(x: 104, y: 165, angle: -22), to: Pose(x: 166, y: 221, angle: 18), delay: 0)
  static let recruits = [
    Arrival(from: Pose(x: 225, y: 154, angle: 20), to: Pose(x: 185, y: 214, angle: -18), delay: 0),
    Arrival(from: Pose(x: 252, y: 188, angle: -25), to: Pose(x: 199, y: 226, angle: 20), delay: 0.10),
    Arrival(from: Pose(x: 126, y: 129, angle: 11), to: Pose(x: 176, y: 201, angle: -28), delay: 0.20),
    Arrival(from: Pose(x: 229, y: 205, angle: 12), to: Pose(x: 181, y: 234, angle: 8), delay: 0.30)
  ]
  static func ease(_ value: Double) -> Double {
    let f = value.isFinite ? min(1, max(0, value)) : 0
    return f * f * (3 - 2 * f)
  }
  static func attached(step: Int, phase: Double) -> Double { step == 0 ? 0 : step == 1 ? ease(phase / 0.82) : 1 }
  static func active(step: Int, phase: Double) -> Double { step < 2 ? 0 : step == 2 ? ease(phase / 0.58) : 1 }
  static func joined(step: Int, phase: Double, delay: Double) -> Double { step < 3 ? 0 : step == 3 ? ease((phase - delay) / 0.64) : 1 }
  static func pose(_ arrival: Arrival, fraction: Double) -> Pose {
    let f = fraction.isFinite ? min(1, max(0, fraction)) : 0
    return Pose(x: mix(arrival.from.x, arrival.to.x, f), y: mix(arrival.from.y, arrival.to.y, f), angle: mix(arrival.from.angle, arrival.to.angle, f))
  }
  static func mix(_ from: Double, _ to: Double, _ f: Double) -> Double { from + (to - from) * f }
  static func outline(activation: Double) -> [GalaxySSIHealthAtlasSectionLesson.Point] {
    let a = activation.isFinite ? min(1, max(0, activation)) : 0
    return (0..<14).map { i in
      let tip = i % 2 == 0 ? 1.0 : 0, angle = Double(i) * 2 * .pi / 14 - .pi / 2
      return .init(x: cos(angle) * (13 + a * (8 * tip - 3)), y: sin(angle) * (7 + a * (8 * tip + 1)))
    }
  }
  static func strandFraction(_ t: Double, index: Int) -> Double { ease(0.32 + t * 1.55 - Double(index) * 0.18) }
  private static func fiber(_ x: Double, _ y: Double, _ c: [Double]) -> Route {
    .init(start: .init(x: x, y: y), commands: [.init(kind: .cubic,
      points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })])
  }
  static let strands = [
    fiber(157, 226, [167,199,193,207,205,228]), fiber(162, 239, [176,224,183,200,200,213]),
    fiber(160, 219, [180,216,187,236,201,238]), fiber(172, 199, [170,214,189,218,190,247]),
    fiber(172, 246, [183,233,198,222,199,214])
  ]
}
