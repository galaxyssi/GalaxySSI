import SwiftUI

enum GalaxySSIHealthAtlasIntercalatedRoutes {
  static let protonRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 148, y: 174), commands: [
    .init(kind: .cubic, points: [.init(x: 146, y: 156), .init(x: 153, y: 142), .init(x: 151, y: 132)]),
    .init(kind: .quad, points: [.init(x: 151, y: 120), .init(x: 165, y: 107)]),
  ])
  static let bicarbonateRoute = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 193, y: 182), commands: [
    .init(kind: .cubic, points: [.init(x: 186, y: 201), .init(x: 201, y: 214), .init(x: 201, y: 230)]),
    .init(kind: .cubic, points: [.init(x: 201, y: 250), .init(x: 218, y: 259), .init(x: 227, y: 274)]),
    .init(kind: .quad, points: [.init(x: 235, y: 290), .init(x: 281, y: 285)]),
  ])
}
