import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func placentalInterface(_ t: Double) {
    let highlight = GalaxySSIHealthAtlasPlacentalMotion.emphasis(t)
    // Trace adjacent surfaces separately, without suggesting a connecting channel.
    let arc = Path { p in
      p.addArc(center:.zero,radius:1,startAngle:.degrees(110),endAngle:.degrees(250),clockwise:false)
    }
    stroke(arc.applying(CGAffineTransform(a:5.1,b:0,c:0,d:20.5,tx:142.9,ty:181.5)),0xFBE4C1,1.4+1.5*highlight)
    stroke(arc.applying(CGAffineTransform(a:4.9,b:0,c:0,d:19,tx:154.1,ty:181)),0xE1F1EA,1.4+1.5*highlight)
  }
  func placentalGases(_ t: Double) {
    let m = GalaxySSIHealthAtlasPlacentalMotion.self
    arrow(117,161,163,161,0x286556); arrow(158,196,116,196,0x765380)
    let oxygen = m.transfer(t,0.08,0.79), carbon = m.transfer(t,0.20,0.91)
    placentalGas(117+45*oxygen,161,true); placentalGas(158-42*carbon,196,false)
    placentalGas(55,335,true); label("placental_exchange_story_oxygen",107,340,92)
    placentalGas(192,335,false); label("placental_exchange_story_carbon_dioxide",263,340,126)
  }
  func placentalGlucose(_ t: Double) {
    arrow(115,179,161,179,0x82511E)
    placentalTransporter(138.8,179); placentalTransporter(146.2,179)
    let travel = GalaxySSIHealthAtlasPlacentalMotion.transfer(t,0.07,0.89)
    placentalDiamond(115+44*travel,179,3.3); placentalDiamond(55,335,4)
    label("placental_exchange_story_glucose",107,340,92)
    placentalTransporter(192,335); label("placental_exchange_story_glut1",263,340,126)
  }
  private func placentalGas(_ x: Double, _ y: Double, _ oxygen: Bool) {
    if oxygen { disc(x,y,3.7,0xB9DDBB,border:0x286556) }
    else { oval(x-4.1,y-2.7,x+4.1,y+2.7,fill:0xE3D1E9,border:0x765380) }
  }
  private func placentalTransporter(_ x: Double, _ y: Double) {
    oval(x-2.1,y-4.3,x+2.1,y+4.3,fill:0xF6DCAD,border:0x82511E)
  }
  private func placentalDiamond(_ x: Double, _ y: Double, _ size: Double) {
    let p = Path { p in
      p.move(to:CGPoint(x:x,y:y-size)); p.addLine(to:CGPoint(x:x+size,y:y))
      p.addLine(to:CGPoint(x:x,y:y+size)); p.addLine(to:CGPoint(x:x-size,y:y)); p.closeSubpath()
    }
    fill(p,0xF1CA7E); stroke(p,0x82511E,1.1)
  }
}
