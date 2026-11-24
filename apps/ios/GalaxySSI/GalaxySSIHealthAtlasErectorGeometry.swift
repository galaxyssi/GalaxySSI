import SwiftUI

enum GalaxySSIHealthAtlasErectorGeometry {
  static let pelvis = Path { p in
    p.move(to: CGPoint(x: 149, y: 245))
    p.addCurve(to: CGPoint(x: 222, y: 232), control1: CGPoint(x: 162, y: 224), control2: CGPoint(x: 195, y: 222))
    p.addCurve(to: CGPoint(x: 223, y: 261), control1: CGPoint(x: 235, y: 237), control2: CGPoint(x: 234, y: 251))
    p.addQuadCurve(to: CGPoint(x: 217, y: 281), control: CGPoint(x: 217, y: 269))
    p.addQuadCurve(to: CGPoint(x: 200, y: 286), control: CGPoint(x: 213, y: 289))
    p.addQuadCurve(to: CGPoint(x: 182, y: 287), control: CGPoint(x: 192, y: 278))
    p.addQuadCurve(to: CGPoint(x: 153, y: 291), control: CGPoint(x: 169, y: 301))
    p.addQuadCurve(to: CGPoint(x: 150, y: 266), control: CGPoint(x: 143, y: 279))
    p.closeSubpath()
  }
  static let sacrum = Path { p in
    p.move(to: CGPoint(x: 149, y: 248))
    p.addQuadCurve(to: CGPoint(x: 166, y: 253), control: CGPoint(x: 159, y: 247))
    p.addQuadCurve(to: CGPoint(x: 152, y: 282), control: CGPoint(x: 163, y: 269))
    p.addQuadCurve(to: CGPoint(x: 144, y: 276), control: CGPoint(x: 147, y: 283))
    p.addQuadCurve(to: CGPoint(x: 149, y: 248), control: CGPoint(x: 150, y: 262))
    p.closeSubpath()
  }
  static func trunk(_ flexion: Double) -> Path {
    let shift = GalaxySSIHealthAtlasErectorMotion.shift
    return Path { p in
      p.move(to:CGPoint(x:142+shift(59,flexion),y:59))
      p.addCurve(to:CGPoint(x:116+shift(139,flexion),y:139),
        control1:CGPoint(x:133+shift(88,flexion),y:88),control2:CGPoint(x:117+shift(103,flexion),y:103))
      p.addCurve(to:CGPoint(x:130,y:251),
        control1:CGPoint(x:112+shift(189,flexion),y:189),control2:CGPoint(x:141+shift(212,flexion),y:212))
      p.addQuadCurve(to:CGPoint(x:136,y:295),control:CGPoint(x:114,y:278))
      p.addQuadCurve(to:CGPoint(x:229,y:293),control:CGPoint(x:181,y:310))
      p.addCurve(to:CGPoint(x:225+shift(214,flexion),y:214),control1:CGPoint(x:242,y:281),control2:CGPoint(x:223,y:247))
      p.addCurve(to:CGPoint(x:226+shift(114,flexion),y:114),
        control1:CGPoint(x:240+shift(185,flexion),y:185),control2:CGPoint(x:238+shift(140,flexion),y:140))
      p.addQuadCurve(to:CGPoint(x:181+shift(54,flexion),y:54),control:CGPoint(x:210+shift(82,flexion),y:82))
      p.addQuadCurve(to:CGPoint(x:142+shift(59,flexion),y:59),control:CGPoint(x:157+shift(47,flexion),y:47))
      p.closeSubpath()
    }
  }
  static func trace(_ flexion: Double, _ offset: Double, _ top: Double, _ bottom: Double) -> Path {
    let spineX = GalaxySSIHealthAtlasErectorMotion.spineX
    return Path { p in
      p.move(to:CGPoint(x:spineX(top,flexion)+offset,y:top))
      for i in 1...32 {
        let y = top+(bottom-top)*Double(i)/32
        p.addLine(to:CGPoint(x:spineX(y,flexion)+offset*(1-0.3*Double(i)/32),y:y))
      }
    }
  }
  static let extensionRoute = GalaxySSIHealthAtlasSectionLesson.Route(start:.init(x:207,y:52),commands:[
    .init(kind:.quad,points:[.init(x:181,y:27),.init(x:139,y:50)])
  ])
  static let extensionArc = GalaxySSIHealthAtlasSectionLessonView.path(extensionRoute,width:360,height:360)
}
