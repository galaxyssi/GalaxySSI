import SwiftUI

enum GalaxySSIHealthAtlasSinusRoutes {
  struct Track {
    let route: GalaxySSIHealthAtlasSectionLesson.Route
    let path: Path
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      self.route = route
      path = GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360)
    }
  }
  static let ascent = Track(.init(start: .init(x: 121, y: 254), commands: [
    .init(kind: .cubic, points: [.init(x: 135, y: 265), .init(x: 159, y: 256), .init(x: 173, y: 245)]),
    .init(kind: .cubic, points: [.init(x: 191, y: 229), .init(x: 198, y: 211), .init(x: 197, y: 191)]),
    .init(kind: .cubic, points: [.init(x: 196, y: 173), .init(x: 197, y: 161), .init(x: 203, y: 149)]),
  ]))
  static let exit = Track(.init(start: .init(x: 200, y: 151), commands: [
    .init(kind: .cubic, points: [.init(x: 207, y: 146), .init(x: 215, y: 145), .init(x: 220, y: 153)]),
    .init(kind: .quad, points: [.init(x: 225, y: 163), .init(x: 239, y: 171)]),
    .init(kind: .cubic, points: [.init(x: 251, y: 179), .init(x: 266, y: 173), .init(x: 281, y: 183)]),
  ]))
  struct CiliumAnchor { let index: Int; let sample: GalaxySSIHealthAtlasFunctionPath.Sample }
  static let cilia: [CiliumAnchor] = (0...15).compactMap { i in
    guard let sample = GalaxySSIHealthAtlasFunctionPath.sample(ascent.route, position: 0.05 + Double(i) * 0.057, width: 360, height: 360) else { return nil }
    return CiliumAnchor(index: i, sample: sample)
  }
}
