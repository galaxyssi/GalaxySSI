import Foundation

enum GalaxySSIHealthAtlasThymusMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static func ramp(_ t: Double, start: Double, end: Double) -> Double {
    let p = t.isFinite ? min(1, max(0, (t - start) / (end - start))) : 0
    return p * p * (3 - 2 * p)
  }
  struct Positive { let x: Double; let y: Double; let signal: Double; let selected: Bool }
  static func positive(_ t: Double) -> Positive {
    let contact = ramp(t, start: 0, end: 0.55)
    return .init(x: 119 + 27 * contact, y: 126 - 9 * contact, signal: ramp(t, start: 0.47, end: 0.8), selected: t >= 0.72)
  }
  struct Negative { let x: Double; let y: Double; let removal: Double; let radius: Double; let alpha: Int; let debrisAlpha: Int }
  static func negative(_ t: Double) -> Negative {
    let approach = ramp(t, start: 0, end: 0.46), removal = ramp(t, start: 0.46, end: 0.89)
    return .init(x: 170 + 24 * approach, y: 186 + 6 * approach, removal: removal,
      radius: 8.5 - 3 * removal, alpha: Int(255 * (1 - removal)), debrisAlpha: Int(185 * (1 - removal)))
  }
  static func travel(_ t: Double) -> Double { 0.025 + 0.90 * t }
  static let enter = Route(start: .init(x: 68, y: 285), commands: [
    .init(kind: .cubic, points: [.init(x: 104, y: 282), .init(x: 107, y: 258), .init(x: 136, y: 248)]),
    .init(kind: .quad, points: [.init(x: 150, y: 244), .init(x: 156, y: 226)]),
    .init(kind: .cubic, points: [.init(x: 162, y: 207), .init(x: 122, y: 203), .init(x: 119, y: 167)]),
  ])
  static let migrate = Route(start: .init(x: 141, y: 121), commands: [
    .init(kind: .cubic, points: [.init(x: 125, y: 153), .init(x: 128, y: 174), .init(x: 149, y: 183)]),
    .init(kind: .cubic, points: [.init(x: 167, y: 193), .init(x: 181, y: 174), .init(x: 200, y: 186)]),
  ])
  static let leave = Route(start: .init(x: 196, y: 218), commands: [
    .init(kind: .quad, points: [.init(x: 214, y: 214), .init(x: 228, y: 241)]),
    .init(kind: .cubic, points: [.init(x: 224, y: 266), .init(x: 248, y: 273), .init(x: 260, y: 283)]),
    .init(kind: .quad, points: [.init(x: 279, y: 293), .init(x: 296, y: 291)]),
  ])
}
