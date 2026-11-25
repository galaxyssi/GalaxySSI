import SwiftUI

enum GalaxySSIHealthAtlasGanglionRoutes {
  struct Track {
    let route: GalaxySSIHealthAtlasSectionLesson.Route
    let path: Path
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      self.route = route
      path = GalaxySSIHealthAtlasSectionLessonView.path(route, width:360, height:360)
    }
  }
  static let sensoryTrack = Track(.init(start:.init(x:334,y:187),commands:[
    .init(kind:.cubic,points:[.init(x:279,y:187),.init(x:239,y:185),.init(x:192,y:183)]),
    .init(kind:.cubic,points:[.init(x:152,y:181),.init(x:107,y:182),.init(x:76,y:176)]),
    .init(kind:.quad,points:[.init(x:65,y:174),.init(x:60,y:162)]),
  ]))
  static let inputTrack = Track(.init(start:.init(x:26,y:153),commands:[
    .init(kind:.cubic,points:[.init(x:67,y:153),.init(x:89,y:144),.init(x:112,y:148)]),
    .init(kind:.cubic,points:[.init(x:128,y:151),.init(x:134,y:155),.init(x:143,y:160)]),
  ]))
  static let outputTrack = Track(.init(start:.init(x:231,y:187),commands:[
    .init(kind:.cubic,points:[.init(x:255,y:177),.init(x:279,y:179),.init(x:302,y:187)]),
    .init(kind:.quad,points:[.init(x:319,y:192),.init(x:334,y:190)]),
  ]))
}
