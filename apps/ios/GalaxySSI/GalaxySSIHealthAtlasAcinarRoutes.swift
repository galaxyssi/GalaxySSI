import SwiftUI

enum GalaxySSIHealthAtlasAcinarRoutes {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static let toGolgi = Route(start: .init(x: 96, y: 145), commands: [
    .init(kind: .quad, points: [.init(x: 116, y: 143), .init(x: 127, y: 171)]),
  ])
  static let toStorage = Route(start: .init(x: 161, y: 174), commands: [
    .init(kind: .cubic, points: [.init(x: 177, y: 171), .init(x: 187, y: 159), .init(x: 210, y: 170)]),
  ])
  static let outOfCell = Route(start: .init(x: 230, y: 175), commands: [
    .init(kind: .cubic, points: [.init(x: 265, y: 177), .init(x: 246, y: 145), .init(x: 281, y: 128)]),
    .init(kind: .quad, points: [.init(x: 301, y: 105), .init(x: 324, y: 95)]),
  ])
  static let collectingTrack = Route(start: .init(x: 62, y: 181), commands: [
    .init(kind: .quad, points: [.init(x: 107, y: 180), .init(x: 134, y: 182)]),
    .init(kind: .line, points: [.init(x: 327, y: 182)]),
  ])
  static let deliveryTrack = Route(start: .init(x: 47, y: 151), commands: [
    .init(kind: .cubic, points: [.init(x: 94, y: 153), .init(x: 131, y: 158), .init(x: 168, y: 167)]),
    .init(kind: .cubic, points: [.init(x: 214, y: 178), .init(x: 251, y: 201), .init(x: 297, y: 184)]),
    .init(kind: .cubic, points: [.init(x: 298, y: 218), .init(x: 286, y: 233), .init(x: 269, y: 247)]),
    .init(kind: .cubic, points: [.init(x: 238, y: 271), .init(x: 197, y: 258), .init(x: 157, y: 264)]),
  ])
}
