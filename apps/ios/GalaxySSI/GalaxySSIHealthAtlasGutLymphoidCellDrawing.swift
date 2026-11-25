import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func gutLymphoidFill(_ p: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ edge: UInt32) {
    gradient(p,top,bottom,from,to); stroke(p,edge,1.45)
  }
  func gutLymphoidDendritic(_ tip: Double) {
    let processes = Path { p in
      p.move(to:CGPoint(x:147,y:226))
      p.addQuadCurve(to:CGPoint(x:131,y:209),control:CGPoint(x:137,y:219))
      p.move(to:CGPoint(x:156,y:214))
      p.addQuadCurve(to:CGPoint(x:153,y:195),control:CGPoint(x:148,y:203))
      p.move(to:CGPoint(x:165,y:213))
      p.addQuadCurve(to:CGPoint(x:173,y:191),control:CGPoint(x:172,y:201))
      p.move(to:CGPoint(x:176,y:224))
      p.addQuadCurve(to:CGPoint(x:tip,y:225),control:CGPoint(x:183,y:222))
      p.move(to:CGPoint(x:171,y:237))
      p.addQuadCurve(to:CGPoint(x:183,y:247),control:CGPoint(x:178,y:245))
      p.move(to:CGPoint(x:154,y:237))
      p.addQuadCurve(to:CGPoint(x:141,y:252),control:CGPoint(x:151,y:246))
    }
    stroke(processes,0x895D84,5); stroke(processes,0xDDBEDC,3)
    oval(141,211,181,243,top:178,bottom:255,from:0xEBD4E8,to:0xC4A0CB,border:0x895D84)
    oval(149,219,167,233,fill:0xAC84B5,border:0x895D84); disc(169,216,2,Self.cream)
  }
  func gutLymphoidFollicle(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double) {
    oval(x-rx,y-ry,x+rx,y+ry,top:199,bottom:303,from:0xEBCEDD,to:0xBD91B1,border:0xA67C9B)
    oval(x-rx*0.60,y-ry*0.66,x+rx*0.50,y+ry*0.35,fill:0xEFDAE0,border:0xC9A0B4)
    for i in 0...9 {
      let dx = Double(i % 5-2)*rx*0.32, dy = (Double(i/5)-0.5)*ry*0.98+Double(i % 3-1)*4
      disc(x+dx,y+dy,1.3,0xAE839F)
    }
  }
  func gutLymphoidAntibody(_ x: Double, _ y: Double, _ secreted: Bool) {
    let color = secreted ? Self.teal : Self.blue
    line(x-4,y-2,x+4,y+2,color,1.8)
    line(x-4,y-2,x-8,y-5,color,1.9); line(x-8,y-5,x-11,y-4,color,1.9); line(x-8,y-5,x-8,y-9,color,1.9)
    line(x+4,y+2,x+8,y+5,color,1.9); line(x+8,y+5,x+11,y+4,color,1.9); line(x+8,y+5,x+8,y+9,color,1.9)
    disc(x,y,2,secreted ? 0xD9EAD8 : Self.cream,border:color)
  }
  func gutLymphoidProtein(_ x: Double, _ y: Double, _ r: Double) {
    var c = context; c.translateBy(x:x,y:y); c.rotate(by:.degrees(-25))
    copy(c).oval(-r,-r*0.67,r,r*0.67,fill:0xEDBD73,border:0xA77336)
  }
}
