import SwiftUI

enum GalaxySSIHealthAtlasPinealRoutes {
  struct Track {
    let route: GalaxySSIHealthAtlasSectionLesson.Route
    let path: Path
    let length: Double
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      self.route = route
      path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
      length = GalaxySSIHealthAtlasCurveLength.route(route, width: 360, height: 360) ?? 0
    }
  }
  static let retinaTrack = Track(.init(start: .init(x: 130, y: 158), commands: [
    .init(kind: .cubic, points: [.init(x: 136, y: 169), .init(x: 129, y: 177), .init(x: 136, y: 183)]),
    .init(kind: .cubic, points: [.init(x: 159, y: 205), .init(x: 182, y: 213), .init(x: 203, y: 197)]),
    .init(kind: .quad, points: [.init(x: 208, y: 192), .init(x: 221, y: 184)]),
  ]))
  static let ray0 = Track(.init(start: .init(x: 15, y: 163), commands: [
    .init(kind: .line, points: [.init(x: 51, y: 164)]),
    .init(kind: .line, points: [.init(x: 132, y: 175)]),
  ]))
  static let ray1 = Track(.init(start: .init(x: 15, y: 170), commands: [
    .init(kind: .line, points: [.init(x: 51, y: 170)]),
    .init(kind: .line, points: [.init(x: 132, y: 166)]),
  ]))
  static let ray2 = Track(.init(start: .init(x: 15, y: 177), commands: [
    .init(kind: .line, points: [.init(x: 51, y: 176)]),
    .init(kind: .line, points: [.init(x: 128, y: 157)]),
  ]))
  static let relay0 = Track(.init(start: .init(x: 147, y: 105), commands: [
    .init(kind: .quad, points: [.init(x: 144, y: 98), .init(x: 152, y: 90)]),
  ]))
  static let relay1 = Track(.init(start: .init(x: 152, y: 90), commands: [
    .init(kind: .cubic, points: [.init(x: 191, y: 107), .init(x: 187, y: 135), .init(x: 185, y: 163)]),
    .init(kind: .cubic, points: [.init(x: 183, y: 185), .init(x: 179, y: 208), .init(x: 187, y: 232)]),
  ]))
  static let relay2 = Track(.init(start: .init(x: 187, y: 232), commands: [
    .init(kind: .cubic, points: [.init(x: 179, y: 232), .init(x: 166, y: 224), .init(x: 164, y: 210)]),
    .init(kind: .quad, points: [.init(x: 162, y: 183), .init(x: 145, y: 167)]),
  ]))
  static let relay3 = Track(.init(start: .init(x: 145, y: 167), commands: [
    .init(kind: .cubic, points: [.init(x: 150, y: 143), .init(x: 161, y: 123), .init(x: 183, y: 117)]),
    .init(kind: .quad, points: [.init(x: 209, y: 110), .init(x: 197, y: 98)]),
  ]))
  static let outgoing = Track(.init(start: .init(x: 210, y: 204), commands: [
    .init(kind: .cubic, points: [.init(x: 225, y: 209), .init(x: 228, y: 242), .init(x: 247, y: 260)]),
    .init(kind: .quad, points: [.init(x: 272, y: 257), .init(x: 285, y: 243)]),
  ]))
}
