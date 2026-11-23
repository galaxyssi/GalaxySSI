import SwiftUI

private typealias MammaryMotion = GalaxySSIHealthAtlasMammaryMotion
private typealias MammaryInk = GalaxySSIHealthAtlasMammaryInk

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func mammaryScene(_ frame: GalaxySSIHealthAtlasMammaryMotion, step: Int, t: Double) {
    mammaryTissue(frame)
    switch step {
    case 0:
      var arc = Path(); arc.addArc(center: CGPoint(x: 138, y: 177), radius: frame.radius - 15, startAngle: .degrees(100 + 126 * t), endAngle: .degrees(142 + 126 * t), clockwise: false)
      stroke(arc, Self.teal, 2.5)
    case 1:
      for i in 0...3 {
        let travel = MammaryMotion.safe(t * 1.35 - Double(i) * 0.11), a = 202 + 29 * Double(i)
        let p = MammaryMotion.point(frame.radius - 7 - 25 * travel, a)
        disc(p.x, p.y, 1.6 + 1.6 * travel, MammaryInk.milk, border: MammaryInk.milkEdge)
      }
    case 3: mammarySignal(frame, t)
    case 4:
      for i in 0...5 { if let p = MammaryMotion.flow(t, index: i) { disc(p.x, p.y, 3.4, MammaryInk.milk, border: MammaryInk.milkEdge) } }
      arrow(269, 226, 320, 226, Self.teal)
    default: break
    }
    let epithelium = MammaryMotion.point(frame.radius, 249), basal = MammaryMotion.point(frame.radius + 16, 106)
    mammaryLeader(91, 61, epithelium.x, epithelium.y); label("mammary_story_luminal_epithelium", 91, 55, 150)
    mammaryLeader(289, 121, 300, 153); label("mammary_story_duct", 289, 115, 109)
    label("mammary_story_lumen", 138, 181, 100)
    mammaryLeader(102, 308, basal.x, basal.y); label("mammary_story_myoepithelial_cells", 102, 325, 177)
  }
  private func mammarySignal(_ frame: MammaryMotion, _ t: Double) {
    label("mammary_story_oxytocin_signal", 264, 335, 136)
    for i in 0...2 {
      let dot = frame.signal(t, index: i), p = dot.point, size = dot.radius
      guard size > 0 else { continue }
      var detail = Path(); detail.move(to: CGPoint(x: p.x, y: p.y - size)); detail.addLine(to: CGPoint(x: p.x + size, y: p.y))
      detail.addLine(to: CGPoint(x: p.x, y: p.y + size)); detail.addLine(to: CGPoint(x: p.x - size, y: p.y)); detail.closeSubpath()
      fill(detail, Self.violet)
    }
  }
  private func mammaryLeader(_ x: Double, _ y: Double, _ targetX: Double, _ targetY: Double) {
    line(x, y, targetX, targetY, MammaryInk.guide, 1.1); disc(targetX, targetY, 2.15, MammaryInk.guide)
  }
}
