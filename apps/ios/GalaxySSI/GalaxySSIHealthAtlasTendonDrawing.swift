import SwiftUI

private typealias TendonFrame = GalaxySSIHealthAtlasTendonMotion
private typealias TendonShapes = GalaxySSIHealthAtlasTendonShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func tendonScene(_ frame: GalaxySSIHealthAtlasTendonMotion, step: Int, t: Double) {
    tendonLinkage(frame)
    let progress = step == 0 ? 3 * t : 0
    tendonCallout("tendon_story_muscle", 80, 87, progress, Self.coral)
    tendonCallout("tendon_story_tendon", 184, 112, progress - 1, Self.teal)
    tendonCallout("tendon_story_bone", 298, 89, progress - 2, TendonShapes.boneInk)
    line(184, 132, 184, 189, TendonShapes.leader, 1.25); disc(184, 132, 2.3, Self.teal, border: Self.cream)
    tendonFocusRing(269, 119, step == 3 ? t : 0, Self.violet)
    if frame.load > 0.06 {
      line(276, 152, 276, 164, Self.violet, 1.35); tendonLoadArrow(276, 164, direction: -1, frame: frame)
      label("tendon_story_pull", 277, 182, 119)
    }
    tendonCollagen(frame)
  }
  private func tendonLinkage(_ frame: TendonFrame) {
    gradient(TendonShapes.bone, 82, 155, 0xFFF5DF, 0xEAD3A8); stroke(TendonShapes.bone, TendonShapes.boneInk, 1.7)
    stroke(TendonShapes.corticalEdge, 0xC7A679, 1.5)
    let join = frame.join, narrow = frame.narrow, bulge = frame.bulge
    let tendon = Path { p in
      p.move(to: CGPoint(x: join - 7, y: 108))
      p.addCurve(to: CGPoint(x: 248, y: 112 + narrow), control1: CGPoint(x: join + 24, y: 115 + narrow), control2: CGPoint(x: 222, y: 111 + narrow))
      p.addQuadCurve(to: CGPoint(x: 269, y: 108), control: CGPoint(x: 259, y: 112))
      p.addQuadCurve(to: CGPoint(x: 269, y: 131), control: CGPoint(x: 274, y: 119))
      p.addQuadCurve(to: CGPoint(x: 248, y: 128 - narrow), control: CGPoint(x: 258, y: 126))
      p.addCurve(to: CGPoint(x: join - 7, y: 132), control1: CGPoint(x: 222, y: 129 - narrow), control2: CGPoint(x: join + 24, y: 124 - narrow)); p.closeSubpath()
    }
    gradient(tendon, 106, 133, 0xE4F2E7, 0xADD2C6); stroke(tendon, Self.teal, 1.7)
    for row in -1...1 {
      let offset = Double(row) * (4.5 - frame.load)
      var detail = Path(); detail.move(to: CGPoint(x: join - 4, y: 120 + offset))
      detail.addCurve(to: CGPoint(x: 268, y: 119 + Double(row) * 6), control1: CGPoint(x: join + 30, y: 121 + offset), control2: CGPoint(x: 231, y: 118 + offset))
      stroke(detail, 0x679D90, 1.35)
    }
    let muscle = Path { p in
      p.move(to: CGPoint(x: 23, y: 119))
      p.addCurve(to: CGPoint(x: 93, y: 86 - bulge), control1: CGPoint(x: 36, y: 95), control2: CGPoint(x: 62, y: 80 - bulge))
      p.addCurve(to: CGPoint(x: join, y: 110), control1: CGPoint(x: join - 32, y: 88 - bulge), control2: CGPoint(x: join - 22, y: 103))
      p.addQuadCurve(to: CGPoint(x: join, y: 130), control: CGPoint(x: join + 4, y: 119))
      p.addCurve(to: CGPoint(x: 83, y: 154 + bulge), control1: CGPoint(x: join - 23, y: 134), control2: CGPoint(x: join - 35, y: 153 + bulge))
      p.addCurve(to: CGPoint(x: 23, y: 119), control1: CGPoint(x: 54, y: 157 + bulge), control2: CGPoint(x: 33, y: 143)); p.closeSubpath()
    }
    gradient(muscle, 76, 162, 0xF9D1CC, 0xD88D99); stroke(muscle, Self.coral, 1.7)
    for row in -2...2 {
      let spread = Double(row) * (8 + frame.load)
      var detail = Path(); detail.move(to: CGPoint(x: Double(32 + abs(row) * 4), y: 120 + Double(row) * 3))
      detail.addCurve(to: CGPoint(x: join - 4, y: 120 + Double(row) * 3.5), control1: CGPoint(x: 63, y: 117 + 1.65 * spread), control2: CGPoint(x: join - 31, y: 120 + spread))
      stroke(detail, row % 2 == 0 ? 0xBB7482 : 0xFDE5DF, 1.65)
    }
  }
  private func tendonCallout(_ key: String, _ x: Double, _ y: Double, _ progress: Double, _ color: UInt32) {
    label(key, x, 54, 94); line(x, 62, x, y, TendonShapes.leader, 1.25); disc(x, y, 2.8, color, border: Self.cream)
    tendonFocusRing(x, y, progress, color)
  }
  private func tendonFocusRing(_ x: Double, _ y: Double, _ progress: Double, _ color: UInt32) {
    let alpha = TendonFrame.focusAlpha(progress)
    guard alpha > 0 else { return }
    var local = context; local.opacity *= Double(alpha) / 255
    let radius = 5 + 15 * progress
    copy(local).stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), color, 2.4)
  }
  private func tendonCollagen(_ frame: TendonFrame) {
    rounded(18, 189, 342, 334, 8, 0xF3F8EF); rounded(31, 222, 329, 304, 7, 0xDCEFE5)
    label("tendon_story_collagen", 180, 211, 280)
    for row in 0...2 {
      let y = 239 + 24 * Double(row)
      var detail = Path(); detail.move(to: CGPoint(x: frame.first, y: y))
      for half in 0...7 {
        let x = frame.first + Double(half) * frame.halfWave, rise = half % 2 == 0 ? -frame.crimp : frame.crimp
        detail.addCurve(to: CGPoint(x: x + frame.halfWave, y: y), control1: CGPoint(x: x + frame.halfWave / 3, y: y + rise), control2: CGPoint(x: x + 2 * frame.halfWave / 3, y: y + rise))
      }
      stroke(detail, row == 1 ? Self.teal : 0x51867D, row == 1 ? 3.1 : 2.4)
    }
    if frame.load > 0.06 {
      tendonLoadArrow(96, 319, direction: -1, frame: frame); tendonLoadArrow(264, 319, direction: 1, frame: frame)
      label("tendon_story_tension", 180, 324, 144)
    }
  }
  private func tendonLoadArrow(_ x: Double, _ y: Double, direction: Double, frame: TendonFrame) {
    let tip = x + direction * frame.arrowLength, base = tip - direction * frame.arrowBase
    var local = context; local.opacity *= Double(frame.arrowAlpha) / 255
    let art = copy(local)
    art.line(x, y, tip, y, Self.violet, frame.arrowWidth)
    art.line(base, y - frame.arrowWing, tip, y, Self.violet, frame.arrowWidth); art.line(base, y + frame.arrowWing, tip, y, Self.violet, frame.arrowWidth)
  }
}
