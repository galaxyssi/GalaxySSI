import SwiftUI

enum GalaxySSIHealthAtlasCranialRoutes {
  struct Track {
    let route: GalaxySSIHealthAtlasSectionLesson.Route
    let path: Path
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      self.route = route
      path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
    }
  }
  struct Side {
    let direction: Double
    func x(_ value: Double) -> Double { direction > 0 ? value : 360 - value }
    let nerve: Track
    let stay: Track
    let cross: Track
    let localRelay: Track
    let crossRelay: Track
    let returnNerve: Track
    let toIris: Track
    init(_ direction: Double) {
      self.direction = direction
      func x(_ value: Double) -> Double { direction > 0 ? value : 360 - value }
      nerve = Track(.init(start: .init(x: x(90), y: 122), commands: [
        .init(kind: .cubic, points: [.init(x: x(95), y: 147), .init(x: x(130), y: 159), .init(x: x(156), y: 184)]),
      ]))
      stay = Track(.init(start: .init(x: x(156), y: 184), commands: [
        .init(kind: .cubic, points: [.init(x: x(166), y: 195), .init(x: x(148), y: 215), .init(x: x(154), y: 239)]),
      ]))
      cross = Track(.init(start: .init(x: x(156), y: 184), commands: [
        .init(kind: .cubic, points: [.init(x: x(170), y: 194), .init(x: x(196), y: 206), .init(x: x(206), y: 239)]),
      ]))
      localRelay = Track(.init(start: .init(x: x(154), y: 239), commands: [
        .init(kind: .quad, points: [.init(x: x(143), y: 257), .init(x: x(148), y: 277)]),
      ]))
      crossRelay = Track(.init(start: .init(x: x(154), y: 239), commands: [
        .init(kind: .cubic, points: [.init(x: x(160), y: 253), .init(x: x(200), y: 261), .init(x: x(212), y: 277)]),
      ]))
      returnNerve = Track(.init(start: .init(x: x(148), y: 277), commands: [
        .init(kind: .cubic, points: [.init(x: x(119), y: 273), .init(x: x(89), y: 260), .init(x: x(76), y: 234)]),
        .init(kind: .cubic, points: [.init(x: x(63), y: 211), .init(x: x(60), y: 179), .init(x: x(49), y: 153)]),
      ]))
      toIris = Track(.init(start: .init(x: x(49), y: 153), commands: [
        .init(kind: .cubic, points: [.init(x: x(42), y: 127), .init(x: x(51), y: 103), .init(x: x(72), y: 87)]),
      ]))
    }
  }
  static let sides = [Side(1), Side(-1)]
}
