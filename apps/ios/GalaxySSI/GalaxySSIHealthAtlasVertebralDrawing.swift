import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func vertebralScene(_ step: Int, _ t: Double) {
    let g = GalaxySSIHealthAtlasVertebralGeometry.self
    let motion = GalaxySSIHealthAtlasVertebralMotion(step: step, phase: t)
    var segment = context; segment.translateBy(x: 0, y: 40)
    copy(segment).vertebralDisc(motion)
    var lower = segment; lower.translateBy(x: 0, y: 108)
    copy(lower).vertebra(upper: false)
    var upper = segment
    upper.translateBy(x: 119 + motion.glide, y: 151); upper.rotate(by: .degrees(motion.angle)); upper.translateBy(x: -119, y: -151)
    copy(upper).vertebra(upper: true)
    let art = copy(segment), facet = motion.facet
    if step == 0 {
      let focus = min(2, Int(t * 3))
      var highlight = segment
      highlight.opacity = Double(Int(80 + 100 * (1 - abs(2 * (t * 3 - Double(focus)) - 1)))) / 255
      let x = focus == 0 ? 117 : focus == 1 ? 121 : facet.x
      let y = focus == 0 ? 97 : focus == 1 ? 151 : facet.y
      let radius = focus == 0 ? 22.0 : 10
      copy(highlight).stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), 0x357D83, 1.5)
    } else {
      for path in [g.neutralEndplate, g.neutralJoint] {
        segment.stroke(path, with: .color(Self.color(0x9D616D78)), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round, dash: [3, 4]))
      }
      if motion.bend > 0.12 {
        art.arrow(61, 100, 39, 108, 0x7E526A); art.arrow(271, 157, 262, 136, 0x34766E)
      } else if motion.bend < -0.12 {
        art.arrow(39, 108, 61, 100, 0x7E526A); art.arrow(262, 136, 271, 157, 0x34766E)
      }
    }
    label("vertebral_motion_art_anterior", 79, 54, 133)
    label("vertebral_motion_art_posterior", 279, 54, 133)
    let body = motion.point(114, 96)
    if step == 0 { vertebralCallout("body", 117, 89, 126, body.x, body.y + 40, 96) }
    vertebralCallout("facet", 285, 285, 140, facet.x, facet.y + 40, 269)
    let discX = (motion.left.x + 73) * 0.5, discY = (motion.left.y + 171) * 0.5
    line(43, 213, 47, 40 + discY, 0x506E78, 1)
    vertebralCallout("disc", 43, 232, 81, discX, discY + 40, 40 + discY, fromX: 47)
    label("vertebral_motion_art_" + (motion.bend > 0.12 ? "flexion" : motion.bend < -0.12 ? "extension" : "neutral"), 180, 328, 204)
  }
  private func vertebralDisc(_ motion: GalaxySSIHealthAtlasVertebralMotion) {
    let lx = motion.left.x, ly = motion.left.y, rx = motion.right.x, ry = motion.right.y
    let outline = Path { p in
      p.move(to: CGPoint(x: lx, y: ly)); p.addLine(to: CGPoint(x: rx, y: ry))
      p.addQuadCurve(to: CGPoint(x: 163, y: 170), control: CGPoint(x: max(rx, 163) + 6, y: (ry + 170) / 2))
      p.addQuadCurve(to: CGPoint(x: 73, y: 171), control: CGPoint(x: 117, y: 164))
      p.addQuadCurve(to: CGPoint(x: lx, y: ly), control: CGPoint(x: min(lx, 73) - 6, y: (ly + 171) / 2))
      p.closeSubpath()
    }
    vertebralWash(outline, 134, 174, 0xD7EDF0, 0x85B1BE, 0x577E88)
    var local = context; local.clip(to: outline)
    let art = copy(local), center = (ly + ry + 165 * 2) / 4
    art.fill(Path { p in
      p.move(to: CGPoint(x: 91, y: center + 1))
      p.addCurve(to: CGPoint(x: 149, y: center - 1), control1: CGPoint(x: 99, y: center - 7), control2: CGPoint(x: 137, y: center - 7))
      p.addCurve(to: CGPoint(x: 91, y: center + 1), control1: CGPoint(x: 140, y: center + 6), control2: CGPoint(x: 105, y: center + 8))
    }, 0xD2ECEB)
    for i in 1...3 {
      let f = Double(i) / 4, y = ly + (171 - ly) * f, y2 = ry + (170 - ry) * f
      art.stroke(Path { p in
        p.move(to: CGPoint(x: lx + (73 - lx) * f - 4, y: y))
        p.addQuadCurve(to: CGPoint(x: 93 + Double(i) * 2, y: y - 1), control: CGPoint(x: 85, y: y + 2.2))
        p.move(to: CGPoint(x: rx + (163 - rx) * f + 4, y: y2))
        p.addQuadCurve(to: CGPoint(x: 145 - Double(i) * 2, y: y2 - 1), control: CGPoint(x: 156, y: y2 + 2.2))
      }, 0x6895A2, 1.25)
    }
  }
  private func vertebra(upper: Bool) {
    let g = GalaxySSIHealthAtlasVertebralGeometry.self
    vertebralWash(g.arch, 42, 159, 0xF1DCC4, 0xB59683, 0x897468)
    stroke(g.archLight, 0x96FFF4E4, 2.8)
    vertebralWash(g.body, 58, 139, 0xFFEED8, 0xC9A68B, 0x897468)
    stroke(g.bodyLight, 0xF8E9D9, 2.3); stroke(g.bodyGrain, 0x53A37A65, 1.05)
    stroke(upper ? g.endplateTop : g.endplateBottom, 0x897468, 1.9)
    let surface = upper ? g.upperJoint : g.lowerJoint
    stroke(surface, 0x34766E, 3.2); stroke(surface, 0xA4CBBD, 1.55)
  }
  private func vertebralCallout(_ key: String, _ x: Double, _ y: Double, _ width: Double, _ tx: Double, _ ty: Double, _ fromY: Double, fromX: Double? = nil) {
    line(fromX ?? x, fromY, tx, ty, 0x506E78, 1); disc(tx, ty, 2.3, 0xF8F7EC, border: 0x506E78)
    label("vertebral_motion_art_" + key, x, y, width)
  }
  private func vertebralWash(_ path: Path, _ top: Double, _ bottom: Double, _ first: UInt32, _ last: UInt32, _ edge: UInt32) {
    gradient(path, top, bottom, first, last); stroke(path, edge, 1.25)
  }
}
