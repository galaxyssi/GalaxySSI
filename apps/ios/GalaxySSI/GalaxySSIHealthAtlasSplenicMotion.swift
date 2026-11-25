import Foundation

enum GalaxySSIHealthAtlasSplenicMotion {
  typealias Point = GalaxySSIHealthAtlasSectionLesson.Point
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  typealias Command = GalaxySSIHealthAtlasSectionLesson.Command
  static let wallLeft = 198.0, wallRight = 216.0, slitY = 210.0, retainedX = 176.0
  static let wallSegments = [139.0,164,172,203,217,264,278,313]
  static func ease(_ value: Double) -> Double {
    let f = value.isFinite ? min(1, max(0, value)) : 0
    return f * f * (3 - 2 * f)
  }
  static func mix(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * f }
  static func pinch(_ x: Double) -> Double { ease(1 - abs(x - 207) / 41) }
  static func centerHeight(_ x: Double) -> Double { mix(1.9, 5.5, ease(max(wallLeft - x, max(x - wallRight, 0)) / 13)) }
  static func passingPoints(_ x: Double) -> [Point] {
    let reach = mix(22, 33, pinch(x))
    return (0..<64).map { i in
      let angle = 2 * Double.pi * Double(i) / 64, dx = reach * cos(angle), px = x + dx
      let fromWall = max(wallLeft - px, max(px - wallRight, 0)), height = mix(5, 13, ease(fromWall / 13))
      return .init(x: dx, y: height * sin(angle))
    }
  }
  struct Capture {
    let extensionAmount: Double
    let x: Double
    let y: Double
    let scale: Double
    let angle: Double
    let spread: Double
    let sweep: Double
  }
  static func capture(_ t: Double) -> Capture {
    let f = ease(t)
    return .init(extensionAmount: ease(t / 0.48) * (1 - ease((t - 0.56) / 0.44)),
      x: mix(retainedX, 109, f), y: mix(slitY, 259, ease(t / 0.82)),
      scale: mix(0.96, 0.85, f), angle: -18 * f,
      spread: (1 - f) * 5, sweep: 360 * ease((t - 0.43) / 0.57))
  }
  static func reuse(_ t: Double, index: Int) -> (fraction: Double, size: Double) {
    let time = t - 0.14 - 0.08 * Double(index)
    return (ease(time / 0.67) * (1 - 0.10 * Double(index)), ease(time / 0.16))
  }
  private static func cubic(_ c: [Double]) -> Command {
    .init(kind: .cubic, points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
  }
  static let approach = Route(start: .init(x: 61, y: 192), commands: [cubic([86,194,103,211,128,slitY])])
  static let sinusRun = Route(start: .init(x: 228, y: slitY), commands: [cubic([258,211,278,196,328,203])])
  static let reuseRun = Route(start: .init(x: 109, y: 259), commands: [
    cubic([137,265,160,271,207,271]), cubic([248,271,263,253,315,252])
  ])
}
