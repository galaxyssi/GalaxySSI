import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func deltaLocalSignal(_ step: Int, _ t: Double) {
    let signal: UInt32 = 0x8365A0, alpha: UInt32 = 0xA45550, beta: UInt32 = 0x357C79
    if step == 3 {
      label("delta_local_art_output", 180, 52, 270); label("delta_local_art_glucagon", 180, 106, 160)
      deltaOutputTrace(149, t, alpha); label("delta_local_art_insulin", 180, 201, 160); deltaOutputTrace(244, t, beta)
      let sweep = 39 + 282 * t
      line(sweep, 121, sweep, 177, signal, 1.2); line(sweep, 216, sweep, 270, signal, 1.2)
      endocrineDiamond(sweep, 272, 4.5, signal); label("delta_local_art_lower", 180, 315, 250); return
    }
    var islet = Path(); islet.move(to: CGPoint(x: 29, y: 168))
    for (a, b, c, d, x, y) in [(38.0, 116.0, 82.0, 82.0, 140.0, 67.0), (208, 49, 287, 77, 321, 129),
      (359, 186, 334, 247, 291, 271), (236, 297, 160, 292, 102, 280), (55, 269, 19, 225, 29, 168)] {
      islet.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: a, y: b), control2: CGPoint(x: c, y: d))
    }
    islet.closeSubpath(); fill(islet, 0xF5EADF); stroke(islet, 0xC29B92, 1.5)
    for (x, y) in [(61.0, 173.0), (91, 132), (121, 90), (128, 160), (163, 210), (180, 254),
      (224, 176), (252, 103), (282, 128), (313, 175), (225, 248), (139, 253)] {
      oval(x - 15, y - 12, x + 15, y + 12, fill: 0xECDBD2, border: 0xD7BEB6); disc(x + 1, y, 4, 0xC8A7AF)
    }
    label("delta_local_art_islet", 180, 32, 210)
    if step == 0 { let r = 42 + 8 * wave(t); endocrineArc(180, 121, r, r, -124, 70 + 264 * t, signal, 2) }
    else {
      deltaSpread(step == 1 ? t : 0.65 + 0.20 * t)
      if step > 1 { deltaShortOutput(86, -1, t, alpha); deltaShortOutput(274, 1, t, beta) }
    }
    oval(146, 91, 214, 151, top: 88, bottom: 157, from: 0xEADCF1, to: 0xC3A7D9, border: signal)
    disc(178, 121, 10, signal, border: Self.cream)
    oval(57, 185, 118, 233, fill: 0xEDBEB0, border: alpha); disc(86, 211, 8, alpha, border: Self.cream)
    oval(242, 185, 303, 233, fill: 0xACD4C9, border: beta); disc(274, 211, 8, beta, border: Self.cream)
    label("delta_local_art_delta", 180, 55, 142); label("delta_local_art_alpha", 86, 254, 104); label("delta_local_art_beta", 274, 254, 104)
    if step > 0 { label("delta_local_art_somatostatin", 180, 315, 236) }
  }
  private func deltaSpread(_ t: Double) {
    for i in 0...2 {
      let f = min(1, max(0, t * 1.22 - Double(i) * 0.14)), r = 36 + 63 * f
      endocrineArc(180, 113, r, r, 33 + 9 * Double(i), 114 - 18 * Double(i), i == 0 ? 0x8365A0 : 0xB59BC4, 2.1 - Double(i) * 0.35)
    }
  }
  private func deltaShortOutput(_ x: Double, _ direction: Double, _ t: Double, _ tint: UInt32) {
    for i in 0...2 {
      let f = (t * 0.8 + Double(i) * 0.31).truncatingRemainder(dividingBy: 1)
      disc(x + direction * (30 + (24 - 12 * t) * f), 207 + Double(i - 1) * 9, 2.7 - f, tint)
    }
  }
  private func deltaOutputTrace(_ y: Double, _ t: Double, _ tint: UInt32) {
    line(39, y, 321, y, 0xA4B7B4, 1)
    var path = Path()
    for i in 0...56 {
      let x = Double(i) / 56, point = CGPoint(x: 39 + 282 * x, y: y - (15 - 10 * x) * wave(x * 4 - 0.6 * t))
      if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    stroke(path, tint, 2.5)
  }
}
