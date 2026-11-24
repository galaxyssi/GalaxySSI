import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func thoracicSpine(_ center: Double, _ top: Double, _ gap: Double, side: Bool) {
    for i in 0...11 {
      let x = center+(side ? 6*sin(Double(i)*0.26) : 0), y = top+gap*Double(i), w = 8.5+Double(i)*0.29
      rounded(x-w-1, y-5.5, x+w+1, y+6.5, 3.8, 0x9BA8AF)
      rounded(x-w, y-4.5, x+w, y+5.4, 3.1, 0xE4E7E2)
      line(x-w+3, y-2.4, x+w-3, y-2.4, 0xF9FAF2, 1.35)
      if side { line(x-w, y, x-w-9, y+5, 0x9BA8AF, 2.8) }
    }
  }
  func thoracicRibbon(_ p: Path, _ edge: UInt32, _ fill: UInt32, _ width: Double) {
    stroke(p, edge, width); stroke(p, fill, width-2); stroke(p, 0x88FFFFFF, (width-3)*0.35)
  }
  func thoracicWashed(_ p: Path, _ top: Double, _ bottom: Double, _ from: UInt32, _ to: UInt32, _ edge: UInt32) {
    gradient(p, top, bottom, from, to); stroke(p, edge, 1.45)
  }
  func thoracicDashed(_ p: Path, _ width: Double) {
    context.stroke(p, with: .color(Self.color(0x8197A4)),
      style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: [4,4], dashPhase: 0))
  }
  func thoracicCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double,
    _ tx: Double, _ ty: Double, below: Bool = false) {
    line(x, y+(below ? -17 : 6), tx, ty, 0x526C79, 1.05)
    disc(tx, ty, 2.1, 0x526C79, border: 0xF4F7F3); label(key, x, y, width)
  }
  func thoracicAxis(_ x: Double, _ y: Double, _ trackWidth: Double, _ span: Double, _ tint: UInt32, _ key: String) {
    line(x-trackWidth/2, y, x+trackWidth/2, y, 0xBCCBCD, 1.4)
    line(x-span/2, y, x+span/2, y, tint, 2.6)
    for side in [-1.0,1.0] {
      let end = x+side*span/2
      line(end, y-4, end, y+4, tint, 2)
    }
    label(key, x, y+24, 109)
  }
}
