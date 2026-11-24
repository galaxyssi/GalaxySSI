import SwiftUI

enum GalaxySSIHealthAtlasClubRoutes {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static let releaseTracks: [Route] = [
    Route(start: .init(x: 176, y: 158), commands: [
      .init(kind: .quad, points: [.init(x: 173, y: 143), .init(x: 160, y: 143)]),
    ]),
    Route(start: .init(x: 176, y: 158), commands: [
      .init(kind: .quad, points: [.init(x: 176, y: 142), .init(x: 188, y: 141)]),
    ]),
    Route(start: .init(x: 176, y: 158), commands: [
      .init(kind: .quad, points: [.init(x: 187, y: 146), .init(x: 201, y: 152)]),
    ]),
  ]
  static let spreadLeft = Route(start: .init(x: 177, y: 141), commands: [
      .init(kind: .cubic, points: [.init(x: 144, y: 141), .init(x: 144, y: 170), .init(x: 117, y: 180)]),
      .init(kind: .quad, points: [.init(x: 95, y: 182), .init(x: 41, y: 180)]),
    ])
  static let spreadRight = Route(start: .init(x: 177, y: 142), commands: [
      .init(kind: .cubic, points: [.init(x: 207, y: 142), .init(x: 217, y: 177), .init(x: 238, y: 180)]),
      .init(kind: .line, points: [.init(x: 312, y: 180)]),
    ])
}
