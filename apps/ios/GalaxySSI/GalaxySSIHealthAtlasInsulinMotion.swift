import Foundation
import CoreGraphics

struct GalaxySSIHealthAtlasInsulinMotion {
  let chapter: Int
  let fraction: Double
  static let fusionStart = 0.54
  init(chapter: Int, fraction: Double) {
    self.chapter = min(4, max(0, chapter))
    self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
  }
  private static func interval(_ t: Double, _ start: Double, _ end: Double) -> Double {
    t.isFinite ? min(1, max(0, (t - start) / (end - start))) : 0
  }
  private static func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }
  static func potassiumOpen(_ t: Double) -> Double { 1 - ease(interval(t, 0.04, 0.68)) }
  static func calciumOpen(_ t: Double) -> Double { ease(interval(t, 0.04, 0.34)) }
  static func approach(_ t: Double) -> Double { ease(interval(t, 0, fusionStart)) }
  static func aperture(_ t: Double) -> Double { ease(interval(t, fusionStart, 0.72)) }
  static func release(_ t: Double, index: Int) -> Double {
    guard (0...2).contains(index) else { return 0 }
    return interval(t, 0.60 + 0.075 * Double(index), 0.90 + 0.04 * Double(index))
  }
  static func wrap(_ t: Double) -> Double { t.isFinite ? t.truncatingRemainder(dividingBy: 1) : 0 }
  var granuleCenterY: Double { 239 - 64 * Self.approach(fraction) }
  var potassiumParticles: [CGPoint] {
    let open = Self.potassiumOpen(fraction)
    return (0...4).map { i in
      let f = Self.wrap(fraction * (1.15 + open * 0.25) + Double(i) / 5)
      let y = Double(i) < (open - 0.4) / 0.6 * 5 ? 222 - 132 * f : 185 + f * 52
      let x = 182 + ((126...165).contains(y) ? 0 : Double(i - 2) * 10)
      return CGPoint(x: x, y: y)
    }
  }
  var calciumParticles: [CGPoint] {
    let open = Self.calciumOpen(fraction)
    return (0...6).compactMap { i in
      let f = Self.wrap(fraction * 1.34 + Double(i) / 7), passage = 0.38 + 0.59 * open
      let y = 87 + 153 * min(f, passage), spread = y <= 163 ? 0 : (y - 163) * 0.29
      guard open > 0.67 || y < 127 else { return nil }
      return CGPoint(x: 182 + Double(i - 3) * spread / 4, y: y)
    }
  }
  static let bloodRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 190, y: 111), commands: [
    .init(kind: .quad, points: [.init(x: 188, y: 133), .init(x: 189, y: 149)]),
    .init(kind: .quad, points: [.init(x: 222, y: 157), .init(x: 242, y: 126)]),
    .init(kind: .quad, points: [.init(x: 270, y: 91), .init(x: 320, y: 101)])
  ])
}
