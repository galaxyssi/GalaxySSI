import SwiftUI

enum GalaxySSIHealthAtlasSensorimotorRoutes {
  struct Track {
    let route: GalaxySSIHealthAtlasSectionLesson.Route
    let path: Path
    let length: Double?
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      self.route = route
      path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
      length = GalaxySSIHealthAtlasCurveLength.route(route, width: 360, height: 360)
    }
  }
  static let centralSulcus = Track(.init(start: .init(x: 176, y: 58), commands: [
    .init(kind: .cubic, points: [.init(x: 165, y: 71), .init(x: 176, y: 80), .init(x: 164, y: 93)]),
    .init(kind: .cubic, points: [.init(x: 152, y: 104), .init(x: 158, y: 116), .init(x: 152, y: 125)]),
    .init(kind: .quad, points: [.init(x: 148, y: 133), .init(x: 149, y: 140)]),
  ]))
  static let plansAcross = Track(.init(start: .init(x: 228, y: 100), commands: [
    .init(kind: .cubic, points: [.init(x: 207, y: 62), .init(x: 146, y: 61), .init(x: 117, y: 98)]),
  ]))
  static let plansBack = Track(.init(start: .init(x: 117, y: 107), commands: [
    .init(kind: .cubic, points: [.init(x: 146, y: 84), .init(x: 199, y: 84), .init(x: 228, y: 107)]),
  ]))
  static let touchPath = Track(.init(start: .init(x: 218, y: 277), commands: [
    .init(kind: .cubic, points: [.init(x: 230, y: 253), .init(x: 206, y: 249), .init(x: 199, y: 222)]),
    .init(kind: .cubic, points: [.init(x: 189, y: 190), .init(x: 201, y: 153), .init(x: 177, y: 102)]),
  ]))
  static let commandPath = Track(.init(start: .init(x: 145, y: 106), commands: [
    .init(kind: .cubic, points: [.init(x: 127, y: 154), .init(x: 139, y: 190), .init(x: 139, y: 211)]),
    .init(kind: .cubic, points: [.init(x: 139, y: 244), .init(x: 87, y: 250), .init(x: 55, y: 270)]),
  ]))
  static func position(_ x: Double, _ y: Double) -> Track {
    Track(.init(start: .init(x: x, y: y), commands: [
      .init(kind: .cubic, points: [.init(x: x + 14, y: y - 31), .init(x: 106, y: 253), .init(x: 150, y: 237)]),
      .init(kind: .cubic, points: [.init(x: 206, y: 213), .init(x: 165, y: 174), .init(x: 172, y: 110)])
    ]))
  }
}
