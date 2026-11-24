import SwiftUI

enum GalaxySSIHealthAtlasEpendymalRoutes {
  struct Track {
    let route: GalaxySSIHealthAtlasSectionLesson.Route
    let path: Path
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      self.route = route
      path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
    }
  }
  static let singleRoute = Track(.init(start: .init(x: 28, y: 156), commands: [
    .init(kind: .cubic, points: [.init(x: 106, y: 131), .init(x: 204, y: 164), .init(x: 331, y: 135)]),
  ]))
  static let leftRoute = Track(.init(start: .init(x: 167, y: 148), commands: [
    .init(kind: .cubic, points: [.init(x: 126, y: 134), .init(x: 76, y: 137), .init(x: 29, y: 156)]),
  ]))
  static let rightRoute = Track(.init(start: .init(x: 193, y: 153), commands: [
    .init(kind: .cubic, points: [.init(x: 233, y: 166), .init(x: 290, y: 158), .init(x: 331, y: 137)]),
  ]))
}
