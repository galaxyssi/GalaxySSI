import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func cholangiocyteBile(_ x: Double, _ y: Double, _ r: Double) {
    oval(x-r, y-r*0.48, x+r, y+r*0.48, fill: 0xE2BF73, border: 0x916820)
  }
  func cholangiocyteBicarbonate(_ x: Double, _ y: Double, _ r: Double) {
    var p = Path()
    p.move(to: CGPoint(x: x, y: y-r)); p.addLine(to: CGPoint(x: x+r, y: y))
    p.addLine(to: CGPoint(x: x, y: y+r)); p.addLine(to: CGPoint(x: x-r, y: y)); p.closeSubpath()
    fill(p, 0xD6EDCA); stroke(p, 0x2B7569, 1.1)
  }
  func cholangiocyteChloride(_ x: Double, _ y: Double, _ r: Double) {
    disc(x, y, r, 0xF0DEED, border: 0x77528B)
  }
  func cholangiocyteWater(_ x: Double, _ y: Double, _ r: Double) {
    var p = Path()
    p.move(to: CGPoint(x: x, y: y-r))
    p.addCurve(to: CGPoint(x: x+r*0.73, y: y+r*0.55),
      control1: CGPoint(x: x+r*0.4, y: y-r*0.45), control2: CGPoint(x: x+r, y: y))
    p.addCurve(to: CGPoint(x: x-r*0.73, y: y+r*0.55),
      control1: CGPoint(x: x+r*0.42, y: y+r*1.08), control2: CGPoint(x: x-r*0.48, y: y+r*1.08))
    p.addCurve(to: CGPoint(x: x, y: y-r),
      control1: CGPoint(x: x-r, y: y), control2: CGPoint(x: x-r*0.4, y: y-r*0.45))
    p.closeSubpath(); fill(p, 0xDEEFF4); stroke(p, 0x326C95, 1.1)
  }
  func cholangiocytePore(_ x: Double, _ y: Double) {
    for side in [-1.0, 1.0] {
      let dx = side * 6
      line(x+dx, y-5, x+dx*0.77, y, 0x326C95, 4.1)
      line(x+dx*0.77, y, x+dx, y+5, 0x326C95, 4.1)
    }
  }
  func cholangiocyteChevron(_ x: Double, _ y: Double, _ dx: Double, _ dy: Double, _ color: UInt32) {
    line(x-5*dx+3*dy, y-5*dy-3*dx, x, y, color, 1.3)
    line(x-5*dx-3*dy, y-5*dy+3*dx, x, y, color, 1.3)
  }
  func cholangiocyteTube(_ p: Path, _ w: Double) {
    stroke(p, 0x527B79, w); stroke(p, 0xA0C2AD, w*0.76); stroke(p, 0xF0F2D3, w*0.47)
  }
  func cholangiocyteRibbon(_ track: GalaxySSIHealthAtlasCholangiocyteRoutes.Track,
    _ p: Double, _ span: Double, _ color: UInt32, _ w: Double) {
    stroke(track.path.trimmedPath(from: p, to: min(1, p+span)), color, w)
    if p+span > 1 { stroke(track.path.trimmedPath(from: 0, to: p+span-1), color, w) }
  }
}
