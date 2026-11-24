import SwiftUI

enum GalaxySSIHealthAtlasMesangialRoutes {
  struct Track {
    let route: GalaxySSIHealthAtlasSectionLesson.Route
    let path: Path
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      self.route = route
      path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
    }
  }
  static let tuft = Track(.init(start: .init(x: 18, y: 49), commands: [
      .init(kind: .cubic, points: [.init(x: 41, y: 55), .init(x: 48, y: 50), .init(x: 54, y: 34)]),
      .init(kind: .cubic, points: [.init(x: 61, y: 17), .init(x: 89, y: 23), .init(x: 84, y: 40)]),
      .init(kind: .cubic, points: [.init(x: 80, y: 54), .init(x: 53, y: 52), .init(x: 62, y: 68)]),
      .init(kind: .cubic, points: [.init(x: 70, y: 82), .init(x: 88, y: 57), .init(x: 97, y: 48)]),
      .init(kind: .cubic, points: [.init(x: 116, y: 26), .init(x: 138, y: 55), .init(x: 122, y: 72)]),
      .init(kind: .cubic, points: [.init(x: 106, y: 88), .init(x: 91, y: 73), .init(x: 81, y: 84)]),
      .init(kind: .cubic, points: [.init(x: 65, y: 96), .init(x: 56, y: 77), .init(x: 48, y: 71)]),
      .init(kind: .quad, points: [.init(x: 36, y: 65), .init(x: 18, y: 69)]),
    ]))
  static let wall = Track(.init(start: .init(x: 245, y: 209), commands: [
      .init(kind: .cubic, points: [.init(x: 249, y: 168), .init(x: 231, y: 134), .init(x: 192, y: 133)]),
      .init(kind: .cubic, points: [.init(x: 155, y: 132), .init(x: 158, y: 153), .init(x: 137, y: 153)]),
    ]))
  static let fibers: [Track] = [
    Track(.init(start: .init(x: 124, y: 193), commands: [
      .init(kind: .quad, points: [.init(x: 120, y: 170), .init(x: 107, y: 145)]),
    ])),
    Track(.init(start: .init(x: 154, y: 192), commands: [
      .init(kind: .quad, points: [.init(x: 158, y: 165), .init(x: 171, y: 139)]),
    ])),
    Track(.init(start: .init(x: 126, y: 238), commands: [
      .init(kind: .quad, points: [.init(x: 119, y: 254), .init(x: 110, y: 278)]),
    ])),
    Track(.init(start: .init(x: 147, y: 241), commands: [
      .init(kind: .quad, points: [.init(x: 153, y: 258), .init(x: 166, y: 276)]),
    ])),
  ]
  static let uptake = Track(.init(start: .init(x: 138, y: 170), commands: [
      .init(kind: .quad, points: [.init(x: 151, y: 186), .init(x: 146, y: 218)]),
    ]))
}
