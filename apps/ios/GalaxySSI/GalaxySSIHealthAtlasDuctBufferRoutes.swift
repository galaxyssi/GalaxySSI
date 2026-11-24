import SwiftUI

enum GalaxySSIHealthAtlasDuctBufferRoutes {
  struct Track {
    let route: GalaxySSIHealthAtlasSectionLesson.Route
    let path: Path
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      self.route = route
      path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
    }
  }
  static let orientationTrack = Track(.init(start: .init(x: 86, y: 180), commands: [
    .init(kind: .cubic, points: [.init(x: 146, y: 173), .init(x: 168, y: 188), .init(x: 230, y: 183)]),
    .init(kind: .quad, points: [.init(x: 233, y: 209), .init(x: 242, y: 223)]),
    .init(kind: .quad, points: [.init(x: 260, y: 250), .init(x: 301, y: 265)]),
  ]))
  static let acidTrack = Track(.init(start: .init(x: 38, y: 115), commands: [
    .init(kind: .cubic, points: [.init(x: 109, y: 109), .init(x: 163, y: 113), .init(x: 218, y: 137)]),
  ]))
  static let deliveryTrack = Track(.init(start: .init(x: 45, y: 142), commands: [
    .init(kind: .cubic, points: [.init(x: 93, y: 154), .init(x: 147, y: 153), .init(x: 191, y: 173)]),
    .init(kind: .cubic, points: [.init(x: 222, y: 188), .init(x: 261, y: 189), .init(x: 298, y: 185)]),
    .init(kind: .cubic, points: [.init(x: 304, y: 194), .init(x: 304, y: 203), .init(x: 293, y: 219)]),
    .init(kind: .quad, points: [.init(x: 271, y: 260), .init(x: 226, y: 261)]),
  ]))
  static let inflowTrack = Track(.init(start: .init(x: 215, y: 97), commands: [
    .init(kind: .cubic, points: [.init(x: 215, y: 121), .init(x: 188, y: 131), .init(x: 192, y: 165)]),
    .init(kind: .quad, points: [.init(x: 192, y: 180), .init(x: 201, y: 189)]),
  ]))
  static let mixingTrack = Track(.init(start: .init(x: 199, y: 188), commands: [
    .init(kind: .quad, points: [.init(x: 255, y: 208), .init(x: 310, y: 188)]),
  ]))
  static let signalTrack = Track(.init(start: .init(x: 219, y: 190), commands: [
    .init(kind: .cubic, points: [.init(x: 220, y: 221), .init(x: 185, y: 229), .init(x: 146, y: 225)]),
    .init(kind: .cubic, points: [.init(x: 103, y: 222), .init(x: 78, y: 229), .init(x: 85, y: 256)]),
    .init(kind: .quad, points: [.init(x: 92, y: 269), .init(x: 130, y: 266)]),
  ]))
  static let acidStream = Track(.init(start: .init(x: 53, y: 182), commands: [
    .init(kind: .cubic, points: [.init(x: 112, y: 165), .init(x: 151, y: 172), .init(x: 190, y: 185)]),
    .init(kind: .quad, points: [.init(x: 253, y: 209), .init(x: 310, y: 188)]),
  ]))
}
