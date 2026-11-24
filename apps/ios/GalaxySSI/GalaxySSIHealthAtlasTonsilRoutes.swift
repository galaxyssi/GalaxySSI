import SwiftUI

enum GalaxySSIHealthAtlasTonsilRoutes {
  typealias Route = GalaxySSIHealthAtlasSectionLesson.Route
  static let smallCryptTrack = Route(start: .init(x: 84, y: 134), commands: [
    .init(kind: .cubic, points: [.init(x: 89, y: 156), .init(x: 92, y: 165), .init(x: 83, y: 178)]),
    .init(kind: .quad, points: [.init(x: 81, y: 186), .init(x: 94, y: 182)]),
    .init(kind: .cubic, points: [.init(x: 95, y: 195), .init(x: 101, y: 208), .init(x: 106, y: 207)]),
    .init(kind: .cubic, points: [.init(x: 113, y: 203), .init(x: 105, y: 182), .init(x: 106, y: 167)]),
    .init(kind: .quad, points: [.init(x: 106, y: 145), .init(x: 114, y: 133)]),
  ])
  static let surfaceTrack = Route(start: .init(x: 34, y: 116), commands: [
    .init(kind: .cubic, points: [.init(x: 74, y: 98), .init(x: 127, y: 102), .init(x: 143, y: 118)]),
    .init(kind: .cubic, points: [.init(x: 157, y: 134), .init(x: 151, y: 177), .init(x: 164, y: 201)]),
    .init(kind: .cubic, points: [.init(x: 172, y: 221), .init(x: 192, y: 222), .init(x: 202, y: 194)]),
    .init(kind: .cubic, points: [.init(x: 213, y: 164), .init(x: 207, y: 124), .init(x: 225, y: 115)]),
    .init(kind: .quad, points: [.init(x: 267, y: 93), .init(x: 326, y: 111)]),
  ])
  static let epithelialTrack = Route(start: .init(x: 29, y: 132), commands: [
    .init(kind: .cubic, points: [.init(x: 84, y: 118), .init(x: 126, y: 147), .init(x: 176, y: 151)]),
    .init(kind: .cubic, points: [.init(x: 229, y: 156), .init(x: 259, y: 126), .init(x: 330, y: 134)]),
  ])
  static let approachTrack = Route(start: .init(x: 87, y: 74), commands: [
    .init(kind: .cubic, points: [.init(x: 121, y: 69), .init(x: 157, y: 99), .init(x: 174, y: 136)]),
    .init(kind: .quad, points: [.init(x: 187, y: 170), .init(x: 181, y: 201)]),
  ])
  static let pickupTrack = Route(start: .init(x: 161, y: 95), commands: [
    .init(kind: .cubic, points: [.init(x: 167, y: 139), .init(x: 151, y: 161), .init(x: 139, y: 195)]),
    .init(kind: .quad, points: [.init(x: 135, y: 206), .init(x: 129, y: 224)]),
  ])
  static let surfacePoints = markers(surfaceTrack, count: 44)
  static let epithelialPoints = markers(epithelialTrack, count: 34)
  private static func markers(_ route: Route, count: Int) -> [CGPoint] {
    (1..<count).compactMap { index in
      GalaxySSIHealthAtlasFunctionPath.sample(route, position: Double(index) / Double(count), width: 360, height: 360)?.point
    }
  }
}
