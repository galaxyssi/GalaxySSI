import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func ependymalWallCell(_ left: Double, _ right: Double, _ top: Double,
    _ depth: Double, _ index: Int, _ focused: Bool) {
    let rim = GalaxySSIHealthAtlasEpendymalMotion.rim
    let high = rim(left,top), low = rim(right,top), center = (left+right)/2
    let middleY = rim(center,top)
    let p = Path { p in
      p.move(to: CGPoint(x: left, y: high))
      p.addQuadCurve(to: CGPoint(x: right, y: low), control: CGPoint(x: center, y: middleY-1.1))
      p.addCurve(to: CGPoint(x: right, y: low+depth),
        control1: CGPoint(x: right-3, y: low+22), control2: CGPoint(x: right+3, y: low+depth-18))
      p.addQuadCurve(to: CGPoint(x: left, y: high+depth), control: CGPoint(x: center-2, y: middleY+depth+5))
      p.addCurve(to: CGPoint(x: left, y: high),
        control1: CGPoint(x: left+3, y: high+depth-18), control2: CGPoint(x: left-3, y: high+22))
      p.closeSubpath()
    }
    gradient(p, focused ? 187 : 191, focused ? 292 : 277, focused ? 0xDBF3EB : 0xE6EEF8, focused ? 0x8AC6C2 : 0xADB9D4)
    stroke(p, 0x647C9A, 1.2)
    let relief = Path { p in
      p.move(to: CGPoint(x: left+3, y: high+4))
      p.addQuadCurve(to: CGPoint(x: right-3, y: low+4), control: CGPoint(x: center, y: middleY+3))
    }
    stroke(relief, 0xF2F8F8, 2.2)
    let nx = center+Double(index % 3-1)*2, ny = middleY+depth*0.64
    var c = context; c.translateBy(x: nx, y: ny); c.rotate(by: .degrees(Double(index % 3-1)*13)); c.translateBy(x: -nx, y: -ny)
    let art = copy(c)
    art.oval(nx-10, ny-12, nx+10, ny+12, fill: 0xA59FC3, border: 0x73698F)
    art.disc(nx-2, ny+1, 3.1, 0x7F749C)
    line(center-9, ny-20, center-3, ny-22, 0xB6C9DC, 1.7)
    line(center+3, ny-24, center+10, ny-21, 0xB6C9DC, 1.7)
    disc(right-1, low+6, 1.8, 0x647C9A)
  }
}
