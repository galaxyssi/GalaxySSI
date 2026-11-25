import SwiftUI

enum GalaxySSIHealthAtlasAutonomicRoutes {
  static let medullaX = 181.0, medullaY = 90.0
  static let spinalX = 174.0, spinalY = 147.0
  static let thoracicX = 120.0, thoracicY = 151.0
  static let cardiacX = 202.0, cardiacY = 204.0
  static let saX = 161.0, saY = 225.0
  struct Fiber {
    let route: GalaxySSIHealthAtlasSectionLesson.Route
    let path: Path
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      self.route = route
      path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
    }
  }
  static let symFirst = Fiber(.init(start: .init(x: spinalX, y: spinalY), commands: [
    .init(kind: .cubic, points: [.init(x: 157, y: 138), .init(x: 133, y: 144), .init(x: thoracicX, y: thoracicY)]),
  ]))
  static let symSecond = Fiber(.init(start: .init(x: thoracicX, y: thoracicY), commands: [
    .init(kind: .cubic, points: [.init(x: 105, y: 161), .init(x: 103, y: 192), .init(x: 121, y: 207)]),
    .init(kind: .quad, points: [.init(x: 135, y: 222), .init(x: saX, y: saY)]),
  ]))
  static let vagFirst = Fiber(.init(start: .init(x: medullaX, y: medullaY), commands: [
    .init(kind: .cubic, points: [.init(x: 207, y: 92), .init(x: 226, y: 110), .init(x: 227, y: 135)]),
    .init(kind: .cubic, points: [.init(x: 230, y: 160), .init(x: 228, y: 186), .init(x: cardiacX, y: cardiacY)]),
  ]))
  static let vagSecond = Fiber(.init(start: .init(x: cardiacX, y: cardiacY), commands: [
    .init(kind: .quad, points: [.init(x: 179, y: 209), .init(x: saX, y: saY)]),
  ]))
  static let compareSymFirst = Fiber(.init(start: .init(x: 40, y: 112), commands: [
    .init(kind: .line, points: [.init(x: 107, y: 112)]),
  ]))
  static let compareSymSecond = Fiber(.init(start: .init(x: 107, y: 112), commands: [
    .init(kind: .cubic, points: [.init(x: 191, y: 112), .init(x: 228, y: 111), .init(x: 271, y: 177)]),
  ]))
  static let compareVagFirst = Fiber(.init(start: .init(x: 40, y: 237), commands: [
    .init(kind: .line, points: [.init(x: 216, y: 237)]),
  ]))
  static let compareVagSecond = Fiber(.init(start: .init(x: 216, y: 237), commands: [
    .init(kind: .quad, points: [.init(x: 247, y: 233), .init(x: 271, y: 177)]),
  ]))
}
