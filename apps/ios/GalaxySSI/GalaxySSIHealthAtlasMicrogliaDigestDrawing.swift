import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func microgliaPocket(_ x: Double, _ y: Double, _ closure: Double) {
    if closure >= 0.98 {
      oval(x-19, y-14, x+17, y+14, fill: 0xC1E0D3, border: 0x36786C)
      return
    }
    let rimX = x-13+30*closure, gap = 11-9*closure
    let p = Path { p in
      p.move(to: CGPoint(x: rimX, y: y-gap))
      p.addCurve(to: CGPoint(x: x-15, y: y+4),
        control1: CGPoint(x: x-17, y: y-16), control2: CGPoint(x: x-20, y: y-10))
      p.addCurve(to: CGPoint(x: rimX, y: y+gap),
        control1: CGPoint(x: x-14, y: y+14), control2: CGPoint(x: x+1, y: y+16))
    }
    stroke(p, 0x36786C, 4.8); stroke(p, 0x83C2B1, 2.7)
  }
  func microgliaFragments(_ x: Double, _ y: Double, _ scale: Double) {
    var c = context; c.translateBy(x: x, y: y); c.scaleBy(x: scale, y: scale)
    let art = copy(c)
    art.oval(-8, -6, 3, 4, fill: 0xE8BDAF, border: 0x9B6458)
    art.disc(5, 4, 2.8, 0xE7AE9E, border: 0x9B6458); art.disc(6, -4, 1.9, 0xB67B74)
  }
  func microgliaDigestion(_ t: Double) {
    microgliaPocket(263, 150, 1)
    line(276, 139, 285, 119, 0x36786C, 1.25)
    disc(270, 88, 38, 0xF7FBFA, border: 0x36786C)
    oval(243, 68, 297, 108, fill: 0xC8E4D8, border: 0x36786C)
    let remain = 1-GalaxySSIHealthAtlasMicrogliaMotion.ease(t, 0.15, 0.88)
    if remain > 0.04 {
      microgliaFragments(268, 87, remain*1.45); microgliaFragments(263, 150, remain)
    }
    for i in 0...4 {
      let x = 254+8*Double(i)+1.3*wave(t+Double(i)*0.22)
      let y = 86+(1-remain)*Double(i % 3-1)*11
      disc(x, y, 1.65, 0x729E9F)
    }
  }
}
