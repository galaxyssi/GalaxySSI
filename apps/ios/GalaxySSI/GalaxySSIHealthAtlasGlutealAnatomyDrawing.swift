import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func glutealAnatomy(_ frame: GalaxySSIHealthAtlasGlutealPose, _ lumbarFlex: Double) {
    let g = GalaxySSIHealthAtlasGlutealGeometry.self
    var pelvis = context; pelvis.concatenate(frame.pelvis)
    let art = copy(pelvis)
    art.glutealLumbar(lumbarFlex)
    art.glutealTissue(g.sacrum,144,205,0xF2E7D8,0xBDD5D2,0x779095)
    art.glutealTissue(g.ilium,112,304,0xFFF4DE,0xB8CDCC,0x779095)
    art.stroke(g.crest,0xA7B8AA,1.45)
    art.oval(165,150,215,196,top:144,bottom:205,from:0xF2E7D8,to:0xBDD5D2,border:0x779095)
    var femur = context; femur.concatenate(frame.femur)
    let limb = copy(femur)
    limb.glutealTissue(g.femur,112,304,0xFFF4DE,0xB8CDCC,0x779095)
    limb.stroke(g.femoralRidge,0xA6B9AD,1.25)
    glutealMuscle(frame)
    disc(190,173,6.5,Self.cream,border:Self.blue); disc(190,173,2.6,Self.blue)
  }
  func glutealTissue(_ p: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ border: UInt32) {
    gradient(p,top,bottom,from,to); stroke(p,border,1.45)
  }
  func glutealLumbar(_ flex: Double, ghost: Bool = false) {
    let spine = Path { p in
      p.move(to:CGPoint(x:139+38*flex,y:56))
      p.addCurve(to:CGPoint(x:135,y:134),control1:CGPoint(x:151+14*flex,y:79),control2:CGPoint(x:151+8*flex,y:104))
    }
    stroke(spine,ghost ? 0x9DB4B8 : 0x779095,ghost ? 1.4 : 3.5)
    for i in 0...4 {
      let y = 60+14*Double(i), f = Double(i)/5
      let x = 141+7*sin(.pi*f)+34*flex*(1-f)*(1-f)
      if ghost {
        stroke(Path(roundedRect:CGRect(x:x-10,y:y-5,width:19,height:10),cornerRadius:3.4),0x9DB4B8,1.25)
      } else {
        oval(x-11,y-5.5,x+9,y+5.5,fill:0xF8F1DF,border:0x779095)
        line(x-11,y,x-16,y+3,0x779095,1.4)
      }
    }
  }
}
