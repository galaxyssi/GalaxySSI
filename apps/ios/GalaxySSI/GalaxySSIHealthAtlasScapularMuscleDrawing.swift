import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func scapularSerratus(_ frame: GalaxySSIHealthAtlasScapularPose, _ emphasis: Double) {
    let m = GalaxySSIHealthAtlasScapularMotion.self, pts = frame.points
    for i in 0...4 {
      let f = Double(i)/4, x = m.blend(pts[6].x,pts[4].x,f), y = m.blend(pts[6].y,pts[4].y,f)
      let rx = m.ribEnds[i].x, ry = m.ribEnds[i].y
      let p = Path { p in
        p.move(to:CGPoint(x:x-2,y:y-9))
        p.addCurve(to:CGPoint(x:rx,y:ry),control1:CGPoint(x:m.blend(x,rx,0.43),y:y-11),control2:CGPoint(x:rx-9,y:ry-15))
        p.addCurve(to:CGPoint(x:x-1,y:y+3),control1:CGPoint(x:rx-11,y:ry-3),control2:CGPoint(x:m.blend(x,rx,0.56),y:y+10))
        p.closeSubpath()
      }
      scapularTissue(p,161,245,0xD3EBE3,0x96C1B7,0x477E79)
      let fold = Path { p in
        p.move(to:CGPoint(x:x,y:y-3))
        p.addQuadCurve(to:CGPoint(x:rx-6,y:ry-4),control:CGPoint(x:m.blend(x,rx,0.65),y:y-1))
      }
      stroke(fold,0xDDF1FBEF,1+0.6*emphasis)
    }
  }
  func scapularTrapezius(_ frame: GalaxySSIHealthAtlasScapularPose, _ reveal: Double) {
    scapularFan(frame,0,0,111,54,113,111,49,125,0xEFCBD1,0xD49CB4,0x9C5F79,reveal)
    scapularFan(frame,1,2,113,111,114,159,102,159,0xE8D2E9,0xC1A0C2,0x846280,reveal)
    scapularFan(frame,2,3,114,159,110,275,147,274,0xD9CBE7,0xAA9BC8,0x735D8C,reveal)
  }
  private func scapularFan(_ frame: GalaxySSIHealthAtlasScapularPose, _ start: Int, _ end: Int,
    _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double, _ top: Double, _ bottom: Double,
    _ from: UInt32, _ to: UInt32, _ color: UInt32, _ reveal: Double) {
    let m = GalaxySSIHealthAtlasScapularMotion.self, pts = frame.points
    let x1 = pts[start].x, y1 = pts[start].y
    let x2 = pts[end].x-(start == end ? 13 : 0), y2 = pts[end].y+(start == end ? 6 : 0)
    let p = Path { p in
      p.move(to:CGPoint(x:ax,y:ay))
      p.addQuadCurve(to:CGPoint(x:x1,y:y1),control:CGPoint(x:m.blend(ax,x1,0.36),y:m.blend(ay,y1,0.73)-10))
      p.addLine(to:CGPoint(x:x2,y:y2))
      p.addQuadCurve(to:CGPoint(x:bx,y:by),control:CGPoint(x:m.blend(bx,x2,0.47),y:m.blend(by,y2,0.60)+9))
      p.addQuadCurve(to:CGPoint(x:ax,y:ay),control:CGPoint(x:bx+6,y:(ay+by)/2)); p.closeSubpath()
    }
    scapularTissue(p,top,bottom,from,to,color)
    let focus = m.regionFocus(start,reveal)
    for i in 1...5 {
      let f = Double(i)/6, fromX = m.blend(ax,bx,f)+4, fromY = m.blend(ay,by,f)
      let toX = m.blend(x1,x2,f)-5, toY = m.blend(y1,y2,f)
      let fold = Path { p in
        p.move(to:CGPoint(x:fromX,y:fromY))
        p.addQuadCurve(to:CGPoint(x:toX,y:toY),control:CGPoint(x:m.blend(fromX,toX,0.44),y:m.blend(fromY,toY,0.69)+f*10-6))
      }
      stroke(fold,i % 2 == 0 ? 0xD9FFF3F4 : color,0.9+focus*0.9)
    }
  }
}
