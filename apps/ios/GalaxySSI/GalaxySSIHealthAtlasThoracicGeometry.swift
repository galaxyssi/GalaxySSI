import SwiftUI

enum GalaxySSIHealthAtlasThoracicGeometry {
  typealias M = GalaxySSIHealthAtlasThoracicMotion
  static func frontRib(_ i: Int, _ b: Double) -> Path {
    let x = M.lateral[i], y = M.outerY(i), tip = M.join[i], tipY = M.joinY(i), bend = x-(x-tip)*0.52
    return Path { p in
      p.move(to: CGPoint(x: M.frontX(x,b), y: M.frontY(x,y,b)))
      p.addCurve(to: CGPoint(x: M.frontX(tip,b), y: M.frontY(tip,tipY,b)),
        control1: CGPoint(x: M.frontX(x+6,b), y: M.frontY(x+6,y+17,b)),
        control2: CGPoint(x: M.frontX(bend,b), y: M.frontY(bend,tipY+8,b)))
    }
  }
  static func rearRib(_ i: Int, _ b: Double) -> Path {
    let x = M.lateral[i], y = M.outerY(i)
    return Path { p in
      p.move(to: CGPoint(x: 12, y: 62+14.7*Double(i)))
      p.addCurve(to: CGPoint(x: M.frontX(x,b), y: M.frontY(x,y,b)),
        control1: CGPoint(x: x*0.44, y: y-32),
        control2: CGPoint(x: M.frontX(x-10,b), y: M.frontY(x-10,y-24,b)))
    }
  }
  static func cartilage(_ i: Int, _ b: Double) -> Path {
    let x = M.join[i], y = M.joinY(i)
    return Path { p in
      p.move(to: CGPoint(x: M.frontX(x,b), y: M.frontY(x,y,b)))
      p.addQuadCurve(to: CGPoint(x: 8, y: M.contactY(i)-6*b),
        control: CGPoint(x: M.frontX(x-11,b), y: M.frontY(x-11,y-3,b)))
    }
  }
  static func costalMargin(_ b: Double) -> Path {
    Path { p in
      p.move(to: CGPoint(x: 8, y: M.contactY(6)-6*b))
      p.addQuadCurve(to: CGPoint(x: M.frontX(M.join[6],b), y: M.frontY(M.join[6],M.joinY(6),b)),
        control: CGPoint(x: M.frontX(32,b), y: M.frontY(32,188,b)))
      for i in 7...9 {
        let x = M.join[i], y = M.joinY(i)
        p.addQuadCurve(to: CGPoint(x: M.frontX(x,b), y: M.frontY(x,y,b)),
          control: CGPoint(x: M.frontX(x-5,b), y: M.frontY(x-5,y-10,b)))
      }
    }
  }
  static func sideRib(_ i: Int) -> Path {
    let x = M.rearX(i), y = M.rearY(i), endX = 207+4.5*Double(i), endY = 101+17*Double(i)
    return Path { p in
      p.move(to: CGPoint(x: x, y: y))
      p.addCurve(to: CGPoint(x: endX, y: endY),
        control1: CGPoint(x: x+22, y: y-8), control2: CGPoint(x: endX-54, y: endY+9))
    }
  }
  static func sideCartilage(_ i: Int, _ b: Double) -> Path {
    let px = M.rearX(i), py = M.rearY(i), endX = 207+4.5*Double(i), endY = 101+17*Double(i)
    let angle = -8*b * .pi/180, cosine = cos(angle), sine = sin(angle)
    let x = px+(endX-px)*cosine-(endY-py)*sine
    let y = py+(endX-px)*sine+(endY-py)*cosine, s = M.contactY(i)
    return Path { p in
      p.move(to: CGPoint(x: x, y: y))
      p.addQuadCurve(to: CGPoint(x: M.sideSternumX(s,b)-4, y: s-9*b), control: CGPoint(x: x+11, y: y+2))
    }
  }
}
