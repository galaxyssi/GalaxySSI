import Foundation

enum GalaxySSIHealthAtlasSalivaMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  typealias Point = GalaxySSIHealthAtlasSectionLesson.Point
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func streamFraction(_ t: Double, index: Int, count: Int, end: Double) -> Double {
    guard count > 0, index >= 0, index < count else { return 0 }
    return end * (safe(t) + Double(index) / Double(count)).truncatingRemainder(dividingBy: 1)
  }
  static func ductX(_ t: Double, index: Int) -> Double { 173 + 152 * (safe(t) + Double(index) / 7).truncatingRemainder(dividingBy: 1) }
  static func sodium(_ t: Double) -> Point { let t = safe(t); return .init(x: 209 + 11 * t, y: 262 - 30 * t) }
  static func potassium(_ t: Double) -> Point { let t = safe(t); return .init(x: 284 - 11 * t, y: 300 - 30 * t) }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: c.count == 2 ? .line : c.count == 4 ? .quad : .cubic,
        points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
    })
  }
  static let cheekTrack = route(151, 96, [171,96,190,96,198,114])
  static let mouthTrack = route(151, 96, [171,96,190,96,198,114], [204,118,212,118,225,120])
  static let fluidTrack = route(83, 267, [111,267], [136,267,168,265])
  static let proteinTrack = route(99, 246, [108,258,112,267], [128,269,152,268])
}
