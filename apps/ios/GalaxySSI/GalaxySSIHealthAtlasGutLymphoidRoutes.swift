import SwiftUI

enum GalaxySSIHealthAtlasGutLymphoidRoutes {
  struct Track {
    let route: GalaxySSIHealthAtlasSectionLesson.Route
    let path: Path
    init(_ route: GalaxySSIHealthAtlasSectionLesson.Route) {
      self.route=route
      path=GalaxySSIHealthAtlasSectionLessonView.path(route,width:360,height:360)
    }
  }
  static let domeTrack = Track(.init(start:.init(x:30,y:151),commands:[
    .init(kind:.quad,points:[.init(x:45,y:150),.init(x:48,y:128)]),
    .init(kind:.cubic,points:[.init(x:50,y:102),.init(x:66,y:104),.init(x:68,y:128)]),
    .init(kind:.quad,points:[.init(x:70,y:159),.init(x:83,y:148)]),
    .init(kind:.quad,points:[.init(x:91,y:139),.init(x:94,y:123)]),
    .init(kind:.cubic,points:[.init(x:99,y:103),.init(x:112,y:111),.init(x:112,y:132)]),
    .init(kind:.quad,points:[.init(x:114,y:156),.init(x:131,y:143)]),
    .init(kind:.cubic,points:[.init(x:146,y:132),.init(x:156,y:132),.init(x:170,y:132)]),
    .init(kind:.cubic,points:[.init(x:193,y:130),.init(x:204,y:142),.init(x:221,y:150)]),
    .init(kind:.quad,points:[.init(x:237,y:158),.init(x:242,y:130)]),
    .init(kind:.cubic,points:[.init(x:246,y:99),.init(x:262,y:105),.init(x:263,y:132)]),
    .init(kind:.quad,points:[.init(x:268,y:158),.init(x:279,y:148)]),
    .init(kind:.quad,points:[.init(x:289,y:140),.init(x:290,y:123)]),
    .init(kind:.cubic,points:[.init(x:294,y:104),.init(x:306,y:106),.init(x:310,y:125)]),
    .init(kind:.quad,points:[.init(x:315,y:147),.init(x:330,y:145)]),
  ]))
  static let sampleTrack = Track(.init(start:.init(x:92,y:94),commands:[
    .init(kind:.cubic,points:[.init(x:124,y:92),.init(x:153,y:101),.init(x:168,y:129)]),
    .init(kind:.cubic,points:[.init(x:172,y:143),.init(x:169,y:150),.init(x:170,y:162)]),
    .init(kind:.quad,points:[.init(x:172,y:178),.init(x:173,y:195)]),
  ]))
  static let apicalEdge = Track(.init(start:.init(x:30,y:130),commands:[
    .init(kind:.cubic,points:[.init(x:78,y:113),.init(x:155,y:132),.init(x:206,y:126)]),
    .init(kind:.cubic,points:[.init(x:247,y:125),.init(x:289,y:109),.init(x:329,y:121)]),
  ]))
  static let basalEdge = Track(.init(start:.init(x:31,y:167),commands:[
    .init(kind:.cubic,points:[.init(x:78,y:154),.init(x:155,y:168),.init(x:206,y:163)]),
    .init(kind:.cubic,points:[.init(x:247,y:163),.init(x:289,y:147),.init(x:330,y:159)]),
  ]))
  static let igaTrack = Track(.init(start:.init(x:123,y:237),commands:[
    .init(kind:.cubic,points:[.init(x:145,y:225),.init(x:183,y:205),.init(x:208,y:178)]),
    .init(kind:.cubic,points:[.init(x:219,y:163),.init(x:213,y:143),.init(x:215,y:125)]),
    .init(kind:.cubic,points:[.init(x:217,y:108),.init(x:254,y:117),.init(x:287,y:108)]),
  ]))
  static let domeMarkers: [CGPoint] = (1..<46).compactMap {
    GalaxySSIHealthAtlasFunctionPath.sample(domeTrack.route,position:Double($0)/46,width:360,height:360)?.point
  }
  struct EpithelialCell { let apical: CGPoint; let basal: CGPoint }
  static let epithelialCells: [EpithelialCell] = (1..<17).compactMap { i in
    let f=Double(i)/17
    guard let a=GalaxySSIHealthAtlasFunctionPath.sample(apicalEdge.route,position:f,width:360,height:360),
      let b=GalaxySSIHealthAtlasFunctionPath.sample(basalEdge.route,position:f,width:360,height:360) else { return nil }
    return EpithelialCell(apical:a.point,basal:b.point)
  }
}
