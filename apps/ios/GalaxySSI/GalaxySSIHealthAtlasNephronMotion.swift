import Foundation

struct GalaxySSIHealthAtlasNephronMotion {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  enum Stage: Int, CaseIterable { case filter, proximal, loop, distal, collect }
  enum Ink: UInt32 { case blood = 0xA84554, fluid = 0x19796F, crosses = 0x355F9E, salt = 0x98601C, secreted = 0x76508E }
  struct Stream { let route: Route; let ink: Ink; let count: Int }
  let stage: Stage
  let fraction: Double
  init(chapter: Int, fraction: Double) {
    stage = Stage(rawValue: chapter) ?? .filter
    self.fraction = fraction.isFinite ? min(1, max(0, fraction)) : 0
  }
  var vessel: Route? {
    stage == .proximal ? Self.periProximal : stage == .distal ? Self.periDistal : nil
  }
  var streams: [Stream] {
    switch stage {
    case .filter: return [.init(route: Self.throughGlomerulus, ink: .blood, count: 5), .init(route: Self.filter, ink: .crosses, count: 2)]
    case .proximal: return [.init(route: Self.proximal, ink: .fluid, count: 5), .init(route: Self.returnToBlood, ink: .crosses, count: 2)]
    case .loop: return [.init(route: Self.loop, ink: .fluid, count: 8), .init(route: Self.waterFromLoop, ink: .crosses, count: 2), .init(route: Self.saltFromLoop, ink: .salt, count: 2)]
    case .distal: return [.init(route: Self.distal, ink: .fluid, count: 7), .init(route: Self.intoDistal, ink: .secreted, count: 3)]
    case .collect: return [.init(route: Self.waterFromDuct, ink: .crosses, count: 2), .init(route: Self.drain, ink: .salt, count: 7)]
    }
  }
  func positions(count: Int) -> [Double] {
    guard (1...16).contains(count) else { return [] }
    return (0..<count).map {
      let value = fraction * 1.3 + Double($0) / Double(count)
      return value - value.rounded(.towardZero)
    }
  }
  private static func route(_ x: Double, _ y: Double, _ controls: [Double]...) -> Route {
    .init(start: .init(x: x, y: y), commands: controls.map { c in
      .init(kind: c.count == 2 ? .line : c.count == 4 ? .quad : .cubic,
        points: stride(from: 0, to: c.count, by: 2).map { .init(x: c[$0], y: c[$0 + 1]) })
    })
  }
  static let throughGlomerulus = route(87, 110, [160,108,171,193,234,205], [327,212,349,232,332,277], [297,335,233,302,222,259], [196,192,124,205,89,269])
  static let filter = route(304, 274, [335,297,344,336,375,324], [397,313,420,306])
  static let proximal = route(382, 306, [407,272,446,293,408,378], [391,427,440,455,477,398], [507,360,551,400,530,444], [510,471,479,487,501,541])
  static let returnToBlood = route(435, 425, [413,465,364,477,304,490])
  static let periProximal = route(271, 434, [283,455,296,482,315,497], [344,523,372,525])
  static let loop = route(500, 531, [533,642,496,794,514,913], [535,1027,481,1196,571,1209], [659,1223,648,1030,655,937], [652,830,675,753,659,644], [655,550])
  static let waterFromLoop = route(511, 765, [487,743,435,739])
  static let saltFromLoop = route(663, 821, [704,805,763,804])
  static let distal = route(654, 552, [642,477,692,424,742,392], [792,354,724,346,752,310], [781,288,802,349,817,316], [826,291,792,259,812,228], [856,206,832,291,868,298], [896,302,889,257,901,255], [929,247,919,296,960,311], [997,330,990,390])
  static let intoDistal = route(1081, 207, [1024,186,930,164,908,257])
  static let periDistal = route(1001, 165, [1035,176,1077,193,1105,221])
  static let drain = route(990, 341, [990,641,981,866,994,1127], [992,1228])
  static let waterFromDuct = route(987, 850, [926,828,870,836])
}
