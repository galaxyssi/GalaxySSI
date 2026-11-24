import SwiftUI

enum GalaxySSIHealthAtlasCholangiocyteRoutes {
  struct Track {
    let route: GalaxySSIHealthAtlasSectionLesson.Route
    let path: Path
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      self.route = route
      path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
    }
  }
  static let orientLeft = Track(.init(start: .init(x: 83, y: 141), commands: [
    .init(kind: .cubic, points: [.init(x: 114, y: 152), .init(x: 147, y: 159), .init(x: 157, y: 174)]),
    .init(kind: .cubic, points: [.init(x: 170, y: 193), .init(x: 172, y: 220), .init(x: 198, y: 252)]),
    .init(kind: .quad, points: [.init(x: 205, y: 267), .init(x: 220, y: 283)]),
  ]))
  static let orientRight = Track(.init(start: .init(x: 278, y: 121), commands: [
    .init(kind: .cubic, points: [.init(x: 257, y: 124), .init(x: 241, y: 129), .init(x: 229, y: 134)]),
    .init(kind: .cubic, points: [.init(x: 201, y: 144), .init(x: 173, y: 157), .init(x: 157, y: 174)]),
    .init(kind: .cubic, points: [.init(x: 170, y: 193), .init(x: 172, y: 220), .init(x: 198, y: 252)]),
    .init(kind: .quad, points: [.init(x: 205, y: 267), .init(x: 220, y: 283)]),
  ]))
  static let ribbon0 = Track(.init(start: .init(x: 41, y: 166), commands: [
    .init(kind: .cubic, points: [.init(x: 133, y: 145), .init(x: 218, y: 177), .init(x: 306, y: 153)]),
  ]))
  static let ribbon1 = Track(.init(start: .init(x: 42, y: 183), commands: [
    .init(kind: .cubic, points: [.init(x: 121, y: 178), .init(x: 212, y: 192), .init(x: 312, y: 175)]),
  ]))
  static let ribbon2 = Track(.init(start: .init(x: 48, y: 197), commands: [
    .init(kind: .cubic, points: [.init(x: 133, y: 192), .init(x: 215, y: 212), .init(x: 315, y: 192)]),
  ]))
  static let bicarbonateTrack = Track(.init(start: .init(x: 151, y: 197), commands: [
    .init(kind: .cubic, points: [.init(x: 156, y: 183), .init(x: 171, y: 172), .init(x: 171, y: 154)]),
    .init(kind: .cubic, points: [.init(x: 169, y: 134), .init(x: 145, y: 122), .init(x: 116, y: 108)]),
  ]))
  static let chlorideTrack = Track(.init(start: .init(x: 245, y: 108), commands: [
    .init(kind: .cubic, points: [.init(x: 214, y: 119), .init(x: 187, y: 134), .init(x: 187, y: 154)]),
    .init(kind: .cubic, points: [.init(x: 186, y: 173), .init(x: 205, y: 182), .init(x: 211, y: 205)]),
  ]))
  static let waterTrack = Track(.init(start: .init(x: 173, y: 280), commands: [
    .init(kind: .cubic, points: [.init(x: 185, y: 264), .init(x: 198, y: 261), .init(x: 199, y: 246)]),
    .init(kind: .cubic, points: [.init(x: 199, y: 222), .init(x: 219, y: 212), .init(x: 215, y: 190)]),
    .init(kind: .cubic, points: [.init(x: 212, y: 174), .init(x: 214, y: 165), .init(x: 214, y: 153)]),
    .init(kind: .cubic, points: [.init(x: 213, y: 127), .init(x: 239, y: 108), .init(x: 278, y: 111)]),
  ]))
  static let downstream = Track(.init(start: .init(x: 57, y: 129), commands: [
    .init(kind: .cubic, points: [.init(x: 106, y: 117), .init(x: 125, y: 132), .init(x: 152, y: 140)]),
    .init(kind: .cubic, points: [.init(x: 197, y: 155), .init(x: 227, y: 158), .init(x: 267, y: 182)]),
    .init(kind: .cubic, points: [.init(x: 288, y: 188), .init(x: 283, y: 208), .init(x: 275, y: 226)]),
    .init(kind: .quad, points: [.init(x: 259, y: 252), .init(x: 232, y: 259)]),
  ]))
}
