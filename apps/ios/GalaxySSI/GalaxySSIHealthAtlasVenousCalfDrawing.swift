import SwiftUI

private typealias VenousShapes = GalaxySSIHealthAtlasVenousShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func venousCalf(_ squeeze: Double, focus: Double) {
    gradient(VenousShapes.leg, 73, 296, 0xFAE4CD, 0xEDC4AD); stroke(VenousShapes.leg, 0xB88C79, 1.45)
    gradient(VenousShapes.soleus, 133, 245, 0xEFD1BB, 0xCC8F8F); stroke(VenousShapes.soleus, 0xAD7472, 1.45)
    var local = context; local.translateBy(x: 72, y: 101); local.scaleBy(x: 1 + 0.075 * squeeze, y: 1 - 0.075 * squeeze); local.translateBy(x: -72, y: -101)
    let art = copy(local)
    art.gradient(VenousShapes.gastro, 85, 202, 0xF3C2B6, 0xD6909C); art.stroke(VenousShapes.gastro, Self.coral, 1.45)
    for i in -2...2 {
      let offset = Double(i) * 8
      var detail = Path(); detail.move(to: CGPoint(x: 72 + offset, y: Double(104 + 2 * abs(i))))
      detail.addQuadCurve(to: CGPoint(x: 72 + 0.45 * offset, y: 190), control: CGPoint(x: 72 + 1.45 * offset, y: 151))
      art.stroke(detail, i == 0 ? Self.coral : 0xF8D9CE, i == 0 ? 1.4 : 1.1)
    }
    stroke(VenousShapes.vein, 0xE1EEF0, 7); stroke(VenousShapes.vein, VenousShapes.wall, 3.2)
    label("venous_return_story_gastrocnemius", 75, 58, 116); line(63, 63, 63, 108, VenousShapes.leader, 1); disc(63, 108, 2.1, Self.coral, border: Self.cream)
    label("venous_return_story_soleus", 75, 326, 116)
    var leader = Path(); leader.move(to: CGPoint(x: 56, y: 313)); leader.addLine(to: CGPoint(x: 27, y: 284)); leader.addLine(to: CGPoint(x: 27, y: 190)); leader.addLine(to: CGPoint(x: 49, y: 183))
    stroke(leader, VenousShapes.leader, 1); disc(49, 183, 2.1, Self.coral, border: Self.cream)
    line(96, 169, 151, 169, VenousShapes.wall, 1.1); stroke(Path(ellipseIn: CGRect(x: 74, y: 158, width: 22, height: 22)), VenousShapes.wall, 1.4)
    venousStationRing(85, 169, focus, radius: 12)
  }
  func venousMuscle(_ squeeze: Double) {
    for side in [-1.0, 1.0] {
      func x(_ offset: Double) -> Double { 230 + side * offset }
      let edge = 27 - 9 * squeeze
      let detail = Path { p in
        p.move(to: CGPoint(x: x(68), y: 142))
        p.addCurve(to: CGPoint(x: x(edge), y: 181), control1: CGPoint(x: x(43), y: 143), control2: CGPoint(x: x(edge), y: 154))
        p.addCurve(to: CGPoint(x: x(68), y: 224), control1: CGPoint(x: x(edge), y: 209), control2: CGPoint(x: x(43), y: 221))
        p.addQuadCurve(to: CGPoint(x: x(68), y: 142), control: CGPoint(x: x(83), y: 181)); p.closeSubpath()
      }
      gradient(detail, 85, 202, 0xF3C2B6, 0xD6909C); stroke(detail, 0xBF8590, 1.45)
      for i in -1...1 {
        let y = 181 + Double(i) * 13
        line(x(68), y + Double(i) * 7, x(edge + 8 + Double(abs(i)) * 5), y, 0xF7D9D1, 1.4)
      }
    }
  }
}
