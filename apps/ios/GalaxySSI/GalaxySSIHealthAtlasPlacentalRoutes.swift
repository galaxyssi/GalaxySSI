import SwiftUI

enum GalaxySSIHealthAtlasPlacentalRoutes {
  struct Track {
    let route: GalaxySSIHealthAtlasSectionLesson.Route
    let path: Path
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      self.route = route
      path = GalaxySSIHealthAtlasSectionLessonView.path(route,width:360,height:360)
    }
  }
  static let maternal = Track(.init(start:.init(x:43,y:257),commands:[
    .init(kind:.cubic,points:[.init(x:37,y:222),.init(x:40,y:160),.init(x:61,y:133)]),
    .init(kind:.cubic,points:[.init(x:78,y:112),.init(x:105,y:113),.init(x:113,y:143)]),
    .init(kind:.cubic,points:[.init(x:122,y:171),.init(x:104,y:207),.init(x:108,y:258)]),
  ]))
  static let fetal = Track(.init(start:.init(x:233,y:94),commands:[
    .init(kind:.cubic,points:[.init(x:226,y:117),.init(x:198,y:127),.init(x:176,y:141)]),
    .init(kind:.cubic,points:[.init(x:161,y:151),.init(x:158,y:169),.init(x:158,y:187)]),
    .init(kind:.cubic,points:[.init(x:158,y:216),.init(x:176,y:237),.init(x:205,y:232)]),
    .init(kind:.cubic,points:[.init(x:231,y:228),.init(x:258,y:217),.init(x:269,y:193)]),
    .init(kind:.cubic,points:[.init(x:282,y:167),.init(x:264,y:147),.init(x:270,y:122)]),
    .init(kind:.quad,points:[.init(x:274,y:105),.init(x:284,y:94)]),
  ]))
}
