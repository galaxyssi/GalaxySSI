import Foundation

enum GalaxySSIHealthAtlasArterialMotion {
  typealias Point = GalaxySSIHealthAtlasSectionLesson.Point
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static let x0 = 28.0, x1 = 332.0, tubeY = 253.0
  static let layerLines = [0.0,6,9,16]
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1,max(0,t)) : 0 }
  private static func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
  static func expansion(step: Int, t: Double, location: Double) -> Double {
    let t = safe(t)
    switch step {
    case 1: return 0.88 * smooth(t)
    case 2:
      let distance = abs(safe(location) - (0.06 + 0.88 * t))
      return 0.22 + 0.67 * smooth(1 - min(1,distance / 0.36))
    case 3: return 0.8 * (1 - smooth(t))
    case 4: return 0.82 * sin(t * .pi)
    default: return 0
    }
  }
  static func front(step: Int, t: Double) -> Double? { step == 2 ? 0.06 + 0.88 * safe(t) : nil }
  static func flowTravel(step: Int, t: Double) -> Double? {
    let t = safe(t)
    switch step {
    case 1, 2: return 0.76 * t
    case 3: return 0.48 * t - 0.17 * t * t
    case 4: return 0.57 * t
    default: return nil
    }
  }
  static func xAt(_ f: Double) -> Double { x0 + (x1 - x0) * f }
  static func radius(step: Int, t: Double, location: Double) -> Double { 20 + 12 * expansion(step: step,t: t,location: location) }
  static func layer(step: Int, t: Double, offset: Double) -> [Point] {
    let upper: [Point] = (0...24).map { i in
      let f = Double(i) / 24
      return .init(x: xAt(f), y: tubeY - radius(step: step,t: t,location: f) - offset)
    }
    let lower: [Point] = stride(from: 24, through: 0, by: -1).map { i in
      let f = Double(i) / 24
      return .init(x: xAt(f), y: tubeY + radius(step: step,t: t,location: f) + offset)
    }
    return upper + lower
  }
  static func lamella(step: Int, t: Double, offset: Double, side: Double) -> [Point] {
    (0...24).map { i in
      let f = Double(i) / 24
      return .init(x: xAt(f), y: tubeY + side * (radius(step: step,t: t,location: f) + offset))
    }
  }
  static func flow(distance: Double, index: Int) -> Point {
    let f = (distance + Double(index) * 0.25).truncatingRemainder(dividingBy: 1)
    return .init(x: xAt(0.05 + 0.9 * f), y: tubeY + (index % 2 == 0 ? -5 : 6))
  }
  static let arch = Route(start: .init(x: 49, y: 132), commands: [
    .init(kind: .cubic, points: [.init(x: 51, y: 119), .init(x: 47, y: 112), .init(x: 55, y: 92)]),
    .init(kind: .cubic, points: [.init(x: 64, y: 70), .init(x: 81, y: 65), .init(x: 100, y: 72)]),
    .init(kind: .cubic, points: [.init(x: 120, y: 79), .init(x: 127, y: 95), .init(x: 125, y: 113)]),
    .init(kind: .cubic, points: [.init(x: 124, y: 122), .init(x: 123, y: 132), .init(x: 125, y: 145)])
  ])
  static let branches: [Route] = [
    .init(start: .init(x: 61, y: 82), commands: [.init(kind: .quad, points: [.init(x: 61, y: 71), .init(x: 53, y: 52)])]),
    .init(start: .init(x: 78, y: 73), commands: [.init(kind: .quad, points: [.init(x: 78, y: 62), .init(x: 77, y: 44)])]),
    .init(start: .init(x: 97, y: 73), commands: [.init(kind: .quad, points: [.init(x: 97, y: 62), .init(x: 103, y: 50)])])
  ]
}
