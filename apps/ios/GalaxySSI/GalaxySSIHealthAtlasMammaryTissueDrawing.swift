import SwiftUI

private typealias MammaryTissueMotion = GalaxySSIHealthAtlasMammaryMotion
private typealias MammaryTissueInk = GalaxySSIHealthAtlasMammaryInk

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func mammaryTissue(_ frame: GalaxySSIHealthAtlasMammaryMotion) {
    let r = frame.radius, outline = MammaryTissueInk.outline(r)
    gradient(outline, 100, 245, 0xFFFCF4, 0xF7ECDA)
    var milk = context; milk.opacity *= Double(Int(165 * frame.amount)) / 255
    milk.fill(outline, with: .linearGradient(Gradient(colors: [Self.color(0xECCD93), Self.color(0xECCD93).opacity(0)]), startPoint: CGPoint(x: 82, y: 0), endPoint: CGPoint(x: 253, y: 0)))
    context.stroke(outline, with: .color(Self.color(MammaryTissueInk.rim)), style: StrokeStyle(lineWidth: 27, lineCap: .butt, lineJoin: .round))
    context.stroke(outline, with: .linearGradient(Gradient(colors: [Self.color(0xF7D4C5), Self.color(0xE6A5AE)]), startPoint: CGPoint(x: 0, y: 78), endPoint: CGPoint(x: 0, y: 279)),
      style: StrokeStyle(lineWidth: 24.5, lineCap: .butt, lineJoin: .round))
    for i in 0...15 {
      let a = 48 + 17.6 * Double(i), p = MammaryTissueMotion.point(r + 4, a)
      mammaryCell(p.x, p.y, angle: a + 90)
      if i < 15 {
        let b = a + 8.8, inner = MammaryTissueMotion.point(r - 12, b - 1), outer = MammaryTissueMotion.point(r + 12, b + 1)
        line(inner.x, inner.y, outer.x, outer.y, MammaryTissueInk.seam, 0.9)
      }
    }
    for row in 0...1 {
      let y = 153 + Double(row) * 48
      for i in 0...3 {
        let x = 267 + Double(i) * 17
        mammaryCell(x, y - 4 + 8 * Double(row), angle: 0)
        if i < 3 { line(x + 8.5, y - 11, x + 8.5, y + 11, MammaryTissueInk.seam, 0.9) }
      }
    }
    for a in stride(from: 66, through: 306, by: 40) {
      let reach = r + 16, half = 13 - 2 * frame.squeeze
      var arc = Path(); arc.addArc(center: CGPoint(x: 138, y: 177), radius: reach, startAngle: .degrees(Double(a) - half), endAngle: .degrees(Double(a) + half), clockwise: false)
      stroke(arc, MammaryTissueInk.basal, 5.8); stroke(arc, 0xA8CBB7, 2)
      let p = MammaryTissueMotion.point(reach, Double(a))
      var local = context; local.translateBy(x: p.x, y: p.y); local.rotate(by: .degrees(Double(a + 90)))
      copy(local).fill(Path(ellipseIn: CGRect(x: -5.5, y: -2.9, width: 11, height: 5.8)), Self.teal)
    }
    for i in 0...18 {
      if let dot = frame.milkDot(i) { disc(dot.point.x, dot.point.y, dot.radius, MammaryTissueInk.milk, border: MammaryTissueInk.milkEdge) }
    }
  }
  private func mammaryCell(_ x: Double, _ y: Double, angle: Double) {
    var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(angle))
    let art = copy(local)
    art.oval(-5.2, -3.6, 5.2, 3.6, fill: MammaryTissueInk.nucleus, border: Self.violet); art.disc(-1.6, -0.6, 1.15, 0xDEC4D2)
  }
}
