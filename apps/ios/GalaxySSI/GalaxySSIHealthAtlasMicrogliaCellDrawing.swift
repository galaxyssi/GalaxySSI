import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func microgliaArbor(_ step: Int, _ t: Double) {
    for branch in GalaxySSIHealthAtlasMicrogliaArbor.branches(step,t) { microgliaBranch(branch) }
    let soma = GalaxySSIHealthAtlasMicrogliaGeometry.soma
    gradient(soma, 149, 195, 0xCCE9DD, 0x7DB8AA); stroke(soma, 0x36786C, 1.2)
    var c = context; c.translateBy(x: 151, y: 173); c.rotate(by: .degrees(-14)); c.translateBy(x: -151, y: -173)
    let art = copy(c)
    art.oval(134, 163, 164, 182, fill: 0x8792B6, border: 0x565F87)
    art.oval(141, 166, 153, 174, fill: 0xACB5D0, border: 0x939EC0); art.disc(155, 174, 2.6, 0x60678D)
    disc(169, 174, 2.1, 0xDCF2E8); disc(157, 184, 1.5, 0xE7F6EF)
  }
  private func microgliaBranch(_ branch: GalaxySSIHealthAtlasMicrogliaArbor.Branch) {
    let x=branch.x, y=branch.y, cx=branch.cx, cy=branch.cy, endX=branch.endX, endY=branch.endY
    let base=branch.base, tip=branch.tip, dx=endX-x, dy=endY-y, length=hypot(dx,dy)
    guard length > 0 else { return }
    let nx = -dy/length, ny = dx/length
    let p = Path { p in
      p.move(to: CGPoint(x: x+nx*base/2, y: y+ny*base/2))
      p.addQuadCurve(to: CGPoint(x: endX+nx*tip/2, y: endY+ny*tip/2),
        control: CGPoint(x: cx+nx*base/2, y: cy+ny*base/2))
      p.addLine(to: CGPoint(x: endX-nx*tip/2, y: endY-ny*tip/2))
      p.addQuadCurve(to: CGPoint(x: x-nx*base/2, y: y-ny*base/2),
        control: CGPoint(x: cx-nx*base/2, y: cy-ny*base/2))
      p.closeSubpath()
    }
    fill(p, 0x83C2B1); stroke(p, 0x36786C, 0.85)
  }
}
