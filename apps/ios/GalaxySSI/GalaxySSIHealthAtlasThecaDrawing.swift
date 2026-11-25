import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private static let thecaSource: Path = {
    var p = Path(); p.addArc(center: CGPoint(x: 134, y: 160), radius: 85, startAngle: .degrees(-146), endAngle: .degrees(-22), clockwise: false)
    p.addQuadCurve(to: CGPoint(x: 221, y: 149), control: CGPoint(x: 219, y: 135)); return p
  }()
  func thecaCooperation(_ step: Int, _ t: Double) {
    label("theca_cooperation_art_follicle", 134, 31, 215)
    disc(134, 160, 109, 0xE3CBD2, border: 0x796071); disc(134, 160, 95, 0xF0CBA6, border: 0xA15D37)
    for i in 0..<25 { let a = Double(i) * 2 * .pi / 25; disc(134 + 85 * cos(a), 160 + 85 * sin(a), 4.3, 0xC08062) }
    disc(134, 160, 73, 0xB5D6C2, border: 0x695957); disc(134, 160, 55, 0xE5F5F0, border: 0x3E776E)
    for i in 0..<32 { let a = Double(i) * 2 * .pi / 32; disc(134 + 63 * cos(a), 160 + 63 * sin(a), 3.8, 0x619B8B) }
    oval(68, 146, 118, 180, fill: 0xA9CEBA, border: 0x3E776E); disc(103, 163, 12, 0xF1D3BC, border: 0xA15D37); disc(103, 163, 4, 0xAE7B78)
    for (start, sweep) in [(-170.0, 148.0), (39.0, 103.0)] {
      endocrineArc(134, 160, 85, 85, start, sweep, 0xA55369, 6.3); endocrineArc(134, 160, 85, 85, start, sweep, 0xF4B9BD, 2.7)
    }
    for (key, x, y, baseline, tint) in [("externa", 208.0, 88.0, 82.0, UInt32(0x796071)),
      ("interna", 215, 126, 127, 0xA15D37), ("boundary", 197, 197, 205, 0x695957), ("granulosa", 172, 211, 251, 0x3E776E)] {
      line(x, y, 245, baseline - 4, Self.cream, 3.2); line(x, y, 245, baseline - 4, tint, 1.05)
      disc(x, y, 2.6, Self.cream, border: tint); label("theca_cooperation_art_" + key, 300, baseline, 104)
    }
    let key: String
    switch step {
    case 0: endocrineArc(134, 160, 93, 93, -162, 26 + 116 * t, 0xA55369, 2.5); key = "vascular"
    case 1:
      let p = min(1, t / 0.72)
      if p > 0 { stroke(Self.thecaSource.trimmedPath(from: 0, to: p), 0x713751, 2.1) }
      let point = p == 0 ? CGPoint(x: 134 + 85 * cos(-146 * .pi / 180), y: 160 + 85 * sin(-146 * .pi / 180)) : Self.thecaSource.trimmedPath(from: 0, to: p).cgPath.currentPoint
      disc(point.x, point.y, 3.3, Self.cream, border: 0xA55369)
      if t >= 0.6 { let reveal = min(1, max(0, (t - 0.6) / 0.4)); thecaAndrogen(221, 157, 0.35 + 0.65 * reveal) }
      key = "androgen"
    case 2:
      endocrineArc(134, 160, 73, 73, -12, 24, 0x695957, 2.7)
      line(221, 157, 197, 157, Self.cream, 2.4); line(221, 157, 197, 157, 0x965412, 0.9)
      thecaAndrogen(221 - 24 * t * t * (3 - 2 * t), 157, 1); key = "handoff"
    default:
      let crossing = min(1, max(0, (t - 0.22) / 0.56))
      if crossing < 1 { thecaAndrogen(197, 157, 1 - crossing) }
      if crossing > 0 {
        var local = context; local.opacity = Double(Int(200 * (1 - crossing))) / 255
        let r = 6 + 8 * crossing
        copy(local).stroke(Path(ellipseIn: CGRect(x: 197 - r, y: 157 - r, width: 2 * r, height: 2 * r)), 0x135669, 1.45)
        disc(197, 157, 2 + 3.2 * crossing, Self.cream, border: 0x135669)
      }
      key = "estradiol"
    }
    rounded(32, 296, 328, 324, 7, 0xFBF8EE); label("theca_cooperation_art_" + key, 180, 314, 278)
    label("gonadal_story_art_educational", 180, 345, 255)
  }
  private func thecaAndrogen(_ x: Double, _ y: Double, _ scale: Double) {
    var local = context; local.translateBy(x: x, y: y); local.scaleBy(x: scale, y: scale)
    let art = copy(local)
    var triangle = Path(); triangle.move(to: CGPoint(x: 0, y: -5.3)); triangle.addLine(to: CGPoint(x: 4.8, y: 3.7)); triangle.addLine(to: CGPoint(x: -4.8, y: 3.7)); triangle.closeSubpath()
    art.fill(triangle, 0x965412); art.stroke(triangle, Self.cream, 1.1)
  }
}
