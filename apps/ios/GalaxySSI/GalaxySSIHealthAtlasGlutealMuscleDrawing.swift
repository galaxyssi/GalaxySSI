import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func glutealMuscle(_ frame: GalaxySSIHealthAtlasGlutealPose) {
    let a=frame.origins, b=frame.insertions, shape=GalaxySSIHealthAtlasGlutealGeometry.muscle(frame)
    glutealTissue(shape,121,236,0xECC4C7,0xB87996,0x9E617A)
    var c = context; c.clip(to:shape)
    let art = copy(c)
    for i in 1...6 {
      let f = Double(i)/7
      let x = Double(a[0].x)+(Double(a[3].x)-Double(a[0].x))*f-9
      let y = Double(a[0].y)+(Double(a[3].y)-Double(a[0].y))*f
      let tx = Double(b[0].x)+(Double(b[2].x)-Double(b[0].x))*f
      let ty = Double(b[0].y)+(Double(b[2].y)-Double(b[0].y))*f
      let fiber = Path { p in
        p.move(to:CGPoint(x:x,y:y))
        p.addCurve(to:CGPoint(x:tx,y:ty),control1:CGPoint(x:x+23,y:y+9),control2:CGPoint(x:tx-18,y:ty-15))
      }
      art.stroke(fiber,i % 2 == 0 ? 0xF8D9D4 : 0xB77E93,1.25)
    }
    let tendon = Path { p in
      p.move(to:CGPoint(x:b[0].x,y:b[0].y))
      p.addQuadCurve(to:CGPoint(x:b[1].x,y:b[1].y),control:CGPoint(x:b[1].x+5,y:b[1].y-5))
      p.addQuadCurve(to:CGPoint(x:b[2].x,y:b[2].y),control:CGPoint(x:b[2].x+3,y:b[2].y-5))
    }
    stroke(tendon,0xEEDBD5,3.3); stroke(tendon,0xA17E8D,1.15)
  }
}
