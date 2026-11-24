import SwiftUI

enum GalaxySSIHealthAtlasCoronaryRoutes {
  struct Track {
    let route: GalaxySSIHealthAtlasSectionLesson.Route
    let path: Path
    let length: Double?
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      self.route = route
      path = GalaxySSIHealthAtlasSectionLessonView.path(route,width: 360,height: 360)
      length = GalaxySSIHealthAtlasCurveLength.route(route,width: 360,height: 360)
    }
  }
  static let rightCoronary = Track(.init(start: .init(x: 145, y: 95), commands: [
    .init(kind: .cubic, points: [.init(x: 126, y: 96), .init(x: 128, y: 112), .init(x: 115, y: 120)]),
    .init(kind: .cubic, points: [.init(x: 104, y: 127), .init(x: 102, y: 137), .init(x: 110, y: 150)]),
    .init(kind: .quad, points: [.init(x: 118, y: 163), .init(x: 134, y: 171)]),
  ]))
  static let rightBranch = Track(.init(start: .init(x: 113, y: 121), commands: [
    .init(kind: .cubic, points: [.init(x: 130, y: 124), .init(x: 135, y: 146), .init(x: 155, y: 156)]),
  ]))
  static let leftMain = Track(.init(start: .init(x: 178, y: 94), commands: [
    .init(kind: .quad, points: [.init(x: 189, y: 96), .init(x: 195, y: 116)]),
  ]))
  static let descending = Track(.init(start: .init(x: 195, y: 116), commands: [
    .init(kind: .cubic, points: [.init(x: 182, y: 143), .init(x: 180, y: 171), .init(x: 208, y: 203)]),
  ]))
  static let circumflex = Track(.init(start: .init(x: 195, y: 116), commands: [
    .init(kind: .cubic, points: [.init(x: 210, y: 113), .init(x: 235, y: 113), .init(x: 251, y: 137)]),
  ]))
  static let diagonal = Track(.init(start: .init(x: 186, y: 143), commands: [
    .init(kind: .cubic, points: [.init(x: 204, y: 147), .init(x: 204, y: 168), .init(x: 231, y: 178)]),
  ]))
  static let anteriorVein = Track(.init(start: .init(x: 198, y: 205), commands: [
    .init(kind: .cubic, points: [.init(x: 170, y: 177), .init(x: 171, y: 151), .init(x: 180, y: 132)]),
    .init(kind: .cubic, points: [.init(x: 188, y: 111), .init(x: 222, y: 102), .init(x: 245, y: 117)]),
  ]))
  static let cardiacVein = Track(.init(start: .init(x: 99, y: 285), commands: [
    .init(kind: .cubic, points: [.init(x: 110, y: 267), .init(x: 132, y: 267), .init(x: 155, y: 277)]),
  ]))
  static let tributary = Track(.init(start: .init(x: 161, y: 323), commands: [
    .init(kind: .cubic, points: [.init(x: 182, y: 308), .init(x: 170, y: 296), .init(x: 188, y: 286)]),
  ]))
  static let coronarySinus = Track(.init(start: .init(x: 155, y: 277), commands: [
    .init(kind: .cubic, points: [.init(x: 178, y: 282), .init(x: 199, y: 297), .init(x: 222, y: 282)]),
    .init(kind: .quad, points: [.init(x: 231, y: 276), .init(x: 239, y: 273)]),
  ]))
  static let arteriole = Track(.init(start: .init(x: 42, y: 291), commands: [
    .init(kind: .cubic, points: [.init(x: 74, y: 282), .init(x: 96, y: 290), .init(x: 121, y: 290)]),
  ]))
  static let venule = Track(.init(start: .init(x: 248, y: 290), commands: [
    .init(kind: .quad, points: [.init(x: 280, y: 294), .init(x: 318, y: 286)]),
  ]))
  static let ostialFlows: [Track] = [-1.0,1].map { side in
    Track(.init(start: .init(x: 180 + side * 4, y: 251), commands: [
      .init(kind: .cubic, points: [.init(x: 180 + side * 7, y: 276),.init(x: 180 + side * 24, y: 299),.init(x: 180 + side * 48, y: 291)]),
      .init(kind: .cubic, points: [.init(x: 180 + side * 71, y: 281),.init(x: 180 + side * 89, y: 288),.init(x: 180 + side * 107, y: 302)])
    ]))
  }
  static let capillaries: [Track] = [-1.0,0,1].map { side in
    Track(.init(start: .init(x: 121, y: 290), commands: [
      .init(kind: .cubic, points: [.init(x: 145, y: 290 + 24 * side),.init(x: 153, y: 282 + 12 * side),.init(x: 174, y: 289 + 13 * side)]),
      .init(kind: .cubic, points: [.init(x: 198, y: 297 + 15 * side),.init(x: 224, y: 290 + 19 * side),.init(x: 248, y: 290)])
    ]))
  }
}
