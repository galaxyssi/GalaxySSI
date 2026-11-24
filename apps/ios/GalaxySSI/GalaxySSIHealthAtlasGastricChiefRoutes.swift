import SwiftUI

enum GalaxySSIHealthAtlasGastricChiefRoutes {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static let locateTrack = Route(start: .init(x: 252, y: 112), commands: [
      .init(kind: .cubic, points: [.init(x: 256, y: 176), .init(x: 234, y: 215), .init(x: 246, y: 270)]),
    ])
  static let acidTrack = Route(start: .init(x: 106, y: 152), commands: [
      .init(kind: .cubic, points: [.init(x: 139, y: 144), .init(x: 159, y: 139), .init(x: 175, y: 176)]),
    ])
  static let packTracks: [Route] = [
    Route(start: .init(x: 150, y: 151), commands: [
      .init(kind: .quad, points: [.init(x: 168, y: 128), .init(x: 207, y: 148)]),
    ]),
    Route(start: .init(x: 158, y: 171), commands: [
      .init(kind: .quad, points: [.init(x: 169, y: 157), .init(x: 204, y: 178)]),
    ]),
    Route(start: .init(x: 155, y: 220), commands: [
      .init(kind: .quad, points: [.init(x: 180, y: 243), .init(x: 209, y: 221)]),
    ]),
  ]
  static let secretionTracks: [Route] = [
    Route(start: .init(x: 219, y: 195), commands: [
      .init(kind: .cubic, points: [.init(x: 237, y: 197), .init(x: 253, y: 178), .init(x: 254, y: 134)]),
    ]),
    Route(start: .init(x: 221, y: 195), commands: [
      .init(kind: .cubic, points: [.init(x: 237, y: 195), .init(x: 274, y: 189), .init(x: 270, y: 153)]),
    ]),
    Route(start: .init(x: 223, y: 195), commands: [
      .init(kind: .cubic, points: [.init(x: 240, y: 196), .init(x: 261, y: 209), .init(x: 276, y: 190)]),
    ]),
  ]
}
