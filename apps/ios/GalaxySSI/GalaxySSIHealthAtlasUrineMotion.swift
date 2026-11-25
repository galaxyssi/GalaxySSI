import Foundation

enum GalaxySSIHealthAtlasUrineMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func ease(_ t: Double) -> Double { let f = safe(t); return f * f * (3 - 2 * f) }
  static func bump(_ d: Double, span: Double) -> Double { ease(1 - abs(d) / span) }
  static func front(_ t: Double) -> Double { 0.23 + 0.73 * safe(t) }
  static func ureterRadius(_ fraction: Double, time: Double) -> Double {
    let front = Self.front(time), pinch = front - 0.16
    return 11 + 5 * bump(fraction - front, span: 0.13) - 8 * bump(fraction - pinch, span: 0.12)
  }
  static func junctionFront(_ t: Double) -> Double { 0.10 + 1.06 * ease(t) }
  static func tunnelRadius(_ fraction: Double, time: Double) -> Double {
    8 - 6 * ease((fraction - 0.4) / 0.55) * (1 - bump(fraction - junctionFront(time) + 0.06, span: 0.19))
  }
  static func pulseInterval(front: Double, length: Double, from: Double = 0) -> (start: Double, end: Double)? {
    guard front.isFinite, length.isFinite, from.isFinite, length > 0 else { return nil }
    let start = max(0, max(from, front - length)), end = min(1, front)
    return start < end ? (start, end) : nil
  }
  struct Reservoir {
    let open: Double
    let drain: Double
    let half: Double
    let dome: Double
    let level: Double
    init(time: Double, emptying: Bool) {
      let t = GalaxySSIHealthAtlasUrineMotion.safe(time)
      open = emptying ? GalaxySSIHealthAtlasUrineMotion.ease(t / 0.22) * (1 - GalaxySSIHealthAtlasUrineMotion.ease((t - 0.89) / 0.11)) : 0
      drain = emptying ? GalaxySSIHealthAtlasUrineMotion.ease((t - 0.14) / 0.80) : 0
      let size = emptying ? 1 - drain : GalaxySSIHealthAtlasUrineMotion.ease(t)
      half = 79 + 34 * size; dome = 134 - 62 * size
      level = emptying ? 111 + 149 * drain : 196 - 85 * size
    }
    func outletRadius(_ f: Double) -> Double {
      let relaxed = 5 + 2 * open
      return relaxed - (relaxed - 0.35) * (1 - open) * GalaxySSIHealthAtlasUrineMotion.bump(f - 0.43, span: 0.32)
    }
  }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: c.count == 2 ? .line : c.count == 4 ? .quad : .cubic,
        points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
    })
  }
  static let overviewUreter = route(127, 110, [156,113,139,142,137,169], [135,206,143,229,156,258])
  static let pelvisRoute = route(101, 90, [111,103,127,110], [156,113,139,142,137,169], [135,206,143,229,156,258])
  static let ureter = route(42, 100, [145,94,152,234,316,256])
  static let tunnel = route(42, 74, [107,93,120,151,260,231])
  static let junctionExit = route(260, 231, [268,242,287,257])
  static let inlet = route(49, 169, [52,199,94,199,118,215])
  static let outlet = route(180, 252, [180,324])
}
