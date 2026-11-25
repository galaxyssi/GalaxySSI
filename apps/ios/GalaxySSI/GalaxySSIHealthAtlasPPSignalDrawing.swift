import SwiftUI

enum GalaxySSIHealthAtlasPPGeometry {
  static let pancreas: Path = {
    var p = Path(); p.move(to: CGPoint(x: 57, y: 152))
    for (a, b, c, d, x, y) in [(68.0, 113.0, 108.0, 133.0, 143.0, 134.0), (208, 135, 249, 122, 289, 112),
      (320, 107, 332, 131, 305, 148), (275, 160, 252, 156, 225, 166), (193, 176, 147, 173, 120, 185),
      (114, 208, 96, 226, 73, 218), (49, 209, 47, 180, 57, 152)] {
      p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: a, y: b), control2: CGPoint(x: c, y: d))
    }
    p.closeSubpath(); return p
  }()
  static let uncinate: Path = {
    var p = Path(); p.move(to: CGPoint(x: 73, y: 202))
    p.addQuadCurve(to: CGPoint(x: 121, y: 184), control: CGPoint(x: 97, y: 205))
    p.addQuadCurve(to: CGPoint(x: 130, y: 202), control: CGPoint(x: 139, y: 189))
    p.addQuadCurve(to: CGPoint(x: 73, y: 217), control: CGPoint(x: 110, y: 222)); p.closeSubpath(); return p
  }()
  static let stomach: Path = {
    var p = Path(); p.move(to: CGPoint(x: 89, y: 108))
    p.addQuadCurve(to: CGPoint(x: 112, y: 137), control: CGPoint(x: 88, y: 141))
    p.addCurve(to: CGPoint(x: 146, y: 202), control1: CGPoint(x: 151, y: 118), control2: CGPoint(x: 171, y: 165))
    p.addCurve(to: CGPoint(x: 75, y: 211), control1: CGPoint(x: 129, y: 231), control2: CGPoint(x: 95, y: 233))
    p.addQuadCurve(to: CGPoint(x: 44, y: 211), control: CGPoint(x: 61, y: 198)); p.addLine(to: CGPoint(x: 36, y: 194))
    p.addQuadCurve(to: CGPoint(x: 85, y: 188), control: CGPoint(x: 59, y: 173))
    p.addQuadCurve(to: CGPoint(x: 116, y: 182), control: CGPoint(x: 107, y: 203))
    p.addQuadCurve(to: CGPoint(x: 102, y: 167), control: CGPoint(x: 123, y: 166))
    p.addQuadCurve(to: CGPoint(x: 67, y: 108), control: CGPoint(x: 68, y: 167)); p.closeSubpath(); return p
  }()
  static let blood = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 40, y: 222), commands: [
    .init(kind: .cubic, points: [.init(x: 105, y: 235), .init(x: 115, y: 130), .init(x: 183, y: 155)]),
    .init(kind: .cubic, points: [.init(x: 247, y: 178), .init(x: 237, y: 224), .init(x: 323, y: 186)])])
  static let digestive = GalaxySSIHealthAtlasSectionLesson.Route(start: .init(x: 38, y: 139), commands: [
    .init(kind: .cubic, points: [.init(x: 110, y: 104), .init(x: 250, y: 158), .init(x: 322, y: 123)])])
}

extension GalaxySSIHealthAtlasIllustratedDrawing {
  private static let ppInk: UInt32 = 0x236B64, ppDuct: UInt32 = 0xA16D46
  func pancreaticPPSignal(_ step: Int, _ t: Double) {
    switch step {
    case 0:
      gradient(GalaxySSIHealthAtlasPPGeometry.pancreas, 108, 221, 0xF4D6A0, 0xDF9B77)
      stroke(GalaxySSIHealthAtlasPPGeometry.pancreas, Self.ppDuct, 1.8)
      fill(GalaxySSIHealthAtlasPPGeometry.uncinate, 0xC9DFC7); stroke(GalaxySSIHealthAtlasPPGeometry.uncinate, Self.ppInk, 1.6)
      label("pp_signal_art_pancreas", 181, 92, 220); line(110, 211, 159 + 45 * t, 255, Self.ppInk, 1.4)
      let r = 10 + 5 * wave(t)
      stroke(Path(ellipseIn: CGRect(x: 110 - r, y: 208 - r, width: 2 * r, height: 2 * r)), Self.ppInk, 1.9)
      endocrineDiamond(159 + 45 * t, 255, 4, Self.ppInk); label("pp_signal_art_uncinate", 180, 283, 240)
    case 1: ppMeal(t)
    case 2:
      let route = GalaxySSIHealthAtlasPPGeometry.blood
      endocrineVessel(GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360), 28)
      oval(28, 124, 101, 181, fill: 0xB9D9C8, border: Self.ppInk); disc(63, 151, 9, Self.ppInk, border: Self.cream)
      for i in 0...2 {
        let f = min(1, max(0, t * 1.2 - Double(i) * 0.16))
        endocrineDiamond(54 + Double(i) * 9 + 9 * f, 182 + 32 * f, 3.6, Self.ppInk)
      }
      for i in 0...5 { at(route, (t * 0.83 + Double(i) * 0.16).truncatingRemainder(dividingBy: 1)) { endocrineDiamond($0, $1, 4.5, Self.ppInk) } }
      label("pp_signal_art_blood", 180, 77, 240); endocrineDiamond(97, 282, 5, Self.ppInk); label("pp_signal_art_pp", 196, 287, 182)
    default: ppDigestiveContext(t)
    }
  }
  private func ppMeal(_ t: Double) {
    let stomach = GalaxySSIHealthAtlasPPGeometry.stomach
    fill(stomach, 0xEDBEA9); stroke(stomach, Self.ppDuct, 1.8)
    var clipped = context; clipped.clip(to: stomach)
    let inside = copy(clipped)
    for i in 0...4 {
      let y = 103 + 85 * (t + Double(i) * 0.17).truncatingRemainder(dividingBy: 1)
      inside.disc(80 + Double(i % 3) * 5 + (y - 103) * 0.46, y, 3.3, Self.ppDuct)
    }
    oval(216, 139, 318, 211, fill: 0xB9D9C8, border: Self.ppInk); disc(267, 173, 12, Self.ppInk, border: Self.cream)
    for i in 0...2 {
      let f = min(1, max(0, t * 1.2 - 0.18 * Double(i))), x = 172 + 37 * f
      endocrineArc(x, 176, 13, 25, -61, 122, 0x947639, 2)
    }
    label("pp_signal_art_meal", 92, 265, 140); label("pp_signal_art_cell", 267, 265, 138)
  }
  private func ppDigestiveContext(_ t: Double) {
    label("pp_signal_art_pp", 180, 91, 270)
    let route = GalaxySSIHealthAtlasPPGeometry.digestive
    endocrineVessel(GalaxySSIHealthAtlasSectionLessonView.path(route, width: 360, height: 360), 19)
    for i in 0...5 { at(route, (t * 0.69 + 0.17 * Double(i)).truncatingRemainder(dividingBy: 1)) { endocrineDiamond($0, $1, 4, Self.ppInk) } }
    label("pp_signal_art_regulators", 87, 195, 131)
    for i in 0...2 {
      let f = (t + Double(i) * 0.25).truncatingRemainder(dividingBy: 1), x = 47 + 83 * f
      line(x, 223 - 7 * Double(i), x + 8, 223 - 7 * Double(i), Self.violet, 2.2)
    }
    for i in 0...4 {
      let x = 176 + 17 * Double(i), y = 213 - 13 * wave(Double(i) / 8)
      oval(x - 13, y - 16, x + 13, y + 16, fill: 0xF0C6A4, border: Self.ppDuct); disc(x, y - 5, 4, Self.ppDuct)
    }
    rounded(158, 225, 325, 248, 8, 0xFAE2BE); line(170, 226, 325, 226, Self.ppDuct, 1.2); line(170, 247, 325, 247, Self.ppDuct, 1.2)
    for i in 0...3 {
      let f = (t * 0.64 + 0.23 * Double(i)).truncatingRemainder(dividingBy: 1)
      disc(184 + 138 * f, 236, 2.6, Self.ppDuct)
    }
    label("pp_signal_art_exocrine", 240, 276, 194)
  }
}
