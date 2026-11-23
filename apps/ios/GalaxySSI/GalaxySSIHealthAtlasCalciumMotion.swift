import Foundation

enum GalaxySSIHealthAtlasCalciumMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  enum Cargo { case calcium, pth, vitaminD }
  struct State {
    let calcium: Double
    let hormone: Double
    init(step: Int, fraction: Double) {
      let t = GalaxySSIHealthAtlasCalciumMotion.safe(fraction), ease = t * t * (3 - 2 * t)
      switch step {
      case 0: calcium = 1 - 0.66 * ease; hormone = 0
      case 1: calcium = 0.34; hormone = 0.24 + 0.76 * ease
      default: calcium = 0.34 + 0.66 * ease; hormone = 1 - 0.8 * ease
      }
    }
  }
  static func safe(_ t: Double) -> Double { t.isFinite ? min(1, max(0, t)) : 0 }
  static func wrap(_ t: Double) -> Double { t.isFinite ? t.truncatingRemainder(dividingBy: 1) : 0 }
  static func fraction(_ t: Double, index: Int, count: Int) -> Double {
    guard count > 0, index >= 0, index < count else { return 0 }
    return wrap(safe(t) + Double(index) / Double(count))
  }
  static func presence(_ strength: Double, index: Int, count: Int) -> Double { min(1, max(0, safe(strength) * Double(count) - Double(index))) }
  static func flowAlpha(_ t: Double, index: Int, count: Int, strength: Double = 1) -> Int {
    let f = fraction(t, index: index, count: count)
    return Int(255 * min(1, min(8 * f, 8 * (1 - f))) * presence(strength, index: index, count: count))
  }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: c.count == 2 ? .line : c.count == 4 ? .quad : .cubic,
        points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
    })
  }
  static let neckBlood = route(31, 291, [81,278,128,287,179,295], [234,303,282,288,329,281])
  static let release = route(179, 235, [178,253,187,283,201,295], [233,302,286,288,325,282])
  static let tubule = route(178, 143, [215,132,232,151,268,142], [296,136,327,144])
  static let renalBlood = route(178, 220, [223,231,279,207,327,216])
  static let retention = route(180, 142, [207,136,224,142,246,143], [264,144,250,214,274,217], [299,212,324,216])
  static let activeVitaminD = route(152, 296, [231,320,324,296])
  static let villus = route(107, 266, [140,254,127,199,133,155], [136,117,147,91,173,89], [204,85,223,108,224,153], [226,193,218,252,251,266])
  static let villusBlood = route(82, 277, [178,284,152,237,162,167], [164,134,170,122,182,122], [206,123,197,183,201,223], [204,283,305,277])
  static let uptake = route(54, 162, [91,156,128,173,161,181], [159,236,171,277,87,277])
  static let intestinalSignal = route(305, 277, [204,283,201,223], [195,195,216,173])
}
