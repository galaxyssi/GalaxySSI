import Foundation

struct GalaxySSIHealthAtlasBrainstemMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  let t: Double
  let expiration: Double
  let expansion: Double
  let burst: Double
  init(step: Int, fraction: Double) {
    let time = fraction.isFinite ? min(1, max(0, fraction)) : 0
    t = time; expiration = time / 0.79
    expansion = step == 3 ? Self.ease(time) : step == 4 ? 1 - Self.ease(expiration) : 0
    burst = step == 1 ? Self.envelope((time * 2).truncatingRemainder(dividingBy: 1)) : step == 2 ? Self.envelope(time / 0.26) : step == 4 ? Self.envelope((time - 0.81) / 0.19) : 0
  }
  static func ease(_ value: Double) -> Double {
    let t = value.isFinite ? min(1, max(0, value)) : 0
    return t * t * (3 - 2 * t)
  }
  static func envelope(_ progress: Double) -> Double { progress.isFinite && (0...1).contains(progress) ? sin(.pi * progress) : 0 }
  static func diaphragmCenter(_ expansion: Double) -> Double { 276 + 10 * expansion }
  static func motor(_ t: Double) -> (descending: Double?, branch: Double?) {
    let travel = t / 0.91
    return travel <= 0.29 ? (travel / 0.29, nil) : (nil, (travel - 0.29) / 0.71)
  }
  struct Air { let tail: Double; let head: Double }
  static func airflow(_ t: Double, index: Int, inward: Bool) -> Air? {
    let travel = 1.44 * t - 0.19 * Double(index)
    guard (0.08...1).contains(travel) else { return nil }
    let direction = inward ? 1.0 : -1.0, head = inward ? travel : 1 - travel
    return .init(tail: head - 0.077 * direction, head: head)
  }
  static let network = [272.0,73,294,69,306,87,287,98,267,93]
  static let connections = [0,1,1,2,2,3,3,4,4,0,0,3,1,3]
  static let descending = Route(start: .init(x: 191, y: 101), commands: [
    .init(kind: .cubic, points: [.init(x: 196, y: 111), .init(x: 196, y: 131), .init(x: 197, y: 145)]),
  ])
  static let leftNerve = Route(start: .init(x: 197, y: 145), commands: [
    .init(kind: .cubic, points: [.init(x: 181, y: 145), .init(x: 157, y: 150), .init(x: 151, y: 173)]),
    .init(kind: .cubic, points: [.init(x: 144, y: 202), .init(x: 138, y: 253), .init(x: 129, y: 285)]),
  ])
  static let rightNerve = Route(start: .init(x: 197, y: 145), commands: [
    .init(kind: .cubic, points: [.init(x: 208, y: 144), .init(x: 214, y: 154), .init(x: 217, y: 175)]),
    .init(kind: .cubic, points: [.init(x: 221, y: 202), .init(x: 224, y: 255), .init(x: 233, y: 285)]),
  ])
  static let airway = Route(start: .init(x: 138, y: 95), commands: [
    .init(kind: .cubic, points: [.init(x: 156, y: 94), .init(x: 170, y: 99), .init(x: 172, y: 115)]),
    .init(kind: .quad, points: [.init(x: 175, y: 139), .init(x: 175, y: 191)]),
  ])
  static let airRoute = Route(start: .init(x: 112, y: 95), commands: [
    .init(kind: .line, points: [.init(x: 138, y: 95)]),
    .init(kind: .cubic, points: [.init(x: 156, y: 94), .init(x: 170, y: 99), .init(x: 172, y: 115)]),
    .init(kind: .quad, points: [.init(x: 175, y: 139), .init(x: 175, y: 191)]),
  ])
}
