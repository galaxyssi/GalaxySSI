import SwiftUI

struct GalaxySSIHealthAtlasObliqueBand {
  let external: Bool
  let effort: Double
  let shape: Path
  let strands: Path
  let focus: CGPoint
  init(_ start: CGPoint, _ end: CGPoint, _ effort: Double, _ external: Bool) {
    self.external = external; self.effort = effort
    let x=Double(start.x), y=Double(start.y), endX=Double(end.x), endY=Double(end.y)
    let dx=endX-x, dy=endY-y
    let length = max(1,hypot(dx,dy)), nx = -dy/length, ny = dx/length
    let mx = (x+endX)/2+(x < 180 ? -10 : 10), my = (y+endY)/2, spread = 10+4*effort
    shape = Path { p in
      p.move(to:CGPoint(x:x-nx*3,y:y-ny*3))
      p.addQuadCurve(to:CGPoint(x:endX-nx*5,y:endY-ny*5),control:CGPoint(x:mx-nx*spread,y:my-ny*spread))
      p.addQuadCurve(to:CGPoint(x:endX+nx*5,y:endY+ny*5),control:CGPoint(x:endX+dx*0.12,y:endY+dy*0.12))
      p.addQuadCurve(to:CGPoint(x:x+nx*3,y:y+ny*3),control:CGPoint(x:mx+nx*spread,y:my+ny*spread)); p.closeSubpath()
    }
    strands = Path { p in
      for strand in -1...1 {
        let strand = Double(strand), offset = strand*spread*0.5
        p.move(to:CGPoint(x:x+nx*strand*1.65,y:y+ny*strand*1.65))
        p.addQuadCurve(to:CGPoint(x:endX+nx*strand*2.25,y:endY+ny*strand*2.25),control:CGPoint(x:mx+nx*offset,y:my+ny*offset))
      }
    }
    focus = CGPoint(x:(x+2*mx+endX)*0.25,y:(y+2*my+endY)*0.25)
  }
}
