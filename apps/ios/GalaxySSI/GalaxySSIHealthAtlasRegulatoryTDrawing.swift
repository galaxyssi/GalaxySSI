import SwiftUI

extension GalaxySSIHealthAtlasImmuneDrawing {
  func regulatoryScene(_ step: Int, _ t: Double) {
    switch step {
    case 0: regulatoryResponse(t, settling: 0, showRegulator: false, entering: 0)
    case 1: regulatoryResponse(t + 1, settling: 0, showRegulator: true, entering: Self.ease(t))
    case 2: regulatoryResponse(t + 2, settling: Self.ease(t, 0.05, 0.95), showRegulator: true, entering: 1)
    default: regulatoryResponse(t + 3, settling: 1, showRegulator: true, entering: 1)
    }
  }
  private func regulatoryResponse(_ phase: Double, settling: Double, showRegulator: Bool, entering: Double) {
    regulatoryRibbon(phase, settling)
    for i in 0...2 {
      let motion = (5.5 - 3.5 * settling) * art.wave(phase + Double(i) * 0.21)
      lymphocyte(80 + 100 * Double(i) + motion, 117 - 14 * Double(i % 2) - motion * 0.6, 0.75, 0xF5D5A2, 0xD7A47E, 0x97663E)
    }
    art.label("regulatory_t_story_label_responders", 180, 53, 238)
    art.label(settling < 0.5 ? "regulatory_t_story_label_active" : "regulatory_t_story_label_moderated", 180, 223, 246)
    if showRegulator {
      let x = 274 - 92 * entering, y = 296 - 19 * entering
      lymphocyte(x, y, 0.72 + 0.17 * entering, 0xD1E3B7, 0x87AA7C, 0x4C6F55)
      art.label("regulatory_t_story_label_regulator", x, 340, 140)
    }
  }
  private func regulatoryRibbon(_ phase: Double, _ settling: Double) {
    let spread = 23 - 18 * settling, halfWidth = 9 - 6 * settling
    var top = Path(), band = Path()
    for i in 0...40 {
      let f = Double(i) / 40, x = 42 + 276 * f, y = Self.regulatoryY(f, phase, spread)
      if i == 0 { top.move(to: CGPoint(x: x, y: y)); band.move(to: CGPoint(x: x, y: y - halfWidth)) }
      else { top.addLine(to: CGPoint(x: x, y: y)); band.addLine(to: CGPoint(x: x, y: y - halfWidth)) }
    }
    for i in stride(from: 40, through: 0, by: -1) {
      let f = Double(i) / 40
      band.addLine(to: CGPoint(x: 42 + 276 * f, y: Self.regulatoryY(f, phase, spread) + halfWidth))
    }
    band.closeSubpath(); art.fill(band, 0xEFCEAA); art.stroke(top, 0x97663E, 2.1)
  }
  static func regulatoryY(_ f: Double, _ phase: Double, _ spread: Double) -> Double {
    179 + spread * sin((f * 2.25 - 0.48 * phase) * 2 * .pi) * (1 - abs(2 * f - 1) * 0.48)
  }
}
