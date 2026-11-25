import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func obliqueDirection(_ motion: GalaxySSIHealthAtlasObliqueMotion) {
    let d = motion.right ? 1.0 : -1.0, tip = -90+motion.degrees+8*d, start = tip-22*d
    let base = Path { p in
      p.addArc(center:CGPoint(x:180,y:177),radius:101,startAngle:.degrees(-127),endAngle:.degrees(-53),clockwise:false)
    }
    stroke(base,0xB4C6C5,1.1)
    let low = min(start,tip)
    let active = Path { p in
      p.addArc(center:CGPoint(x:180,y:177),radius:101,startAngle:.degrees(low),endAngle:.degrees(low+22),clockwise:false)
    }
    stroke(active,Self.blue,1.85)
    let a = tip * .pi/180, x = 180+101*cos(a), y = 177+101*sin(a)
    arrow(x+8*d*sin(a),y-8*d*cos(a),x,y,Self.blue)
  }
}
