import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func corneaScene(step: Int, t: Double) {
    if step == 1 || step == 2 { corneaFromFront(migrating: step == 2, t: t) }
    else { corneaSection(step: step, t: t) }
  }
  private func corneaFromFront(migrating: Bool, t: Double) {
    oval(55, 56, 305, 306, fill: 0xE6ECE5, border: 0xA9B8B5)
    oval(73, 74, 287, 288, top: 57, bottom: 295, from: 0xD3EAE7, to: 0x97C4CB, border: Self.blue)
    stroke(Path(ellipseIn: CGRect(x: 75, y: 76, width: 210, height: 210)), GalaxySSIHealthAtlasOcularInk.transmit, 7)
    let colors = GalaxySSIHealthAtlasOcularInk.rays
    for i in 0..<8 {
      let angle = Double(i) * .pi / 4, x = cos(angle), y = sin(angle), color = colors[i % colors.count]
      if migrating {
        let radius = GalaxySSIHealthAtlasOcularMotion.limbalRadius(max(0, t - Double(i) * 0.029))
        line(180 + x * 100, 181 + y * 100, 180 + x * radius, 181 + y * radius, color, 7)
        disc(180 + x * radius, 181 + y * radius, 5.8, color, border: Self.cream)
      } else {
        let r = 4 + 2 * wave(t + Double(i) * 0.095)
        disc(180 + x * 104, 181 + y * 104, r, color, border: Self.cream)
      }
    }
    label("ocular_cornea_limbal_ring", 86, 37, 121); line(100, 47, 122, 88, Self.teal, 1.2); label("ocular_cornea_center", 183, 333, 167)
  }
  private func corneaSection(step: Int, t: Double) {
    let tearRipple = step == 0 ? wave(t) * 6 : 0
    rounded(26, 110, 334, 276, 16, 0xDCE9DD)
    for i in 0...7 {
      let x = Double(44 + 38 * i)
      oval(x - 16, 193, x + 16, 253, top: 130, bottom: 303, from: 0xF7D8C5, to: 0xD39C9E, border: Self.coral); disc(x, 224, 5.3, Self.violet, border: Self.cream)
    }
    for i in 0...6 {
      let x = Double(52 + 41 * i)
      oval(x - 18, 155, x + 18, 193, fill: 0xECC1AC, border: Self.coral); disc(x, 174, 3.9, Self.violet, border: Self.cream)
    }
    for i in 0...7 {
      let x = Double(45 + 38 * i), leaving = step == 4 && (2...4).contains(i) ? t * Double(35 + i * 4) : 0
      oval(x - 17, 128 - leaving, x + 17, 152 - leaving, fill: 0xE7BEB0, border: Self.coral)
      if step == 4 && (2...4).contains(i) { oval(x - 17, 155 - 21 * t, x + 17, 163 - 13 * t, fill: 0xEDC5B3, border: Self.coral) }
    }
    if step == 3 {
      let y = 219 - t * 77, r = 16 - t * 9
      oval(164 - t * 4, y - r, 196 + t * 4, y + r, fill: 0x89BDB1, border: GalaxySSIHealthAtlasOcularInk.transmit)
      disc(180, y, 4.3, Self.teal, border: Self.cream); arrow(211, 220, 211, y - 4, Self.teal)
    }
    var surface = Path(); surface.move(to: CGPoint(x: 34, y: 118))
    surface.addCurve(to: CGPoint(x: 325, y: 118), control1: CGPoint(x: 100, y: 111 + tearRipple), control2: CGPoint(x: 214, y: 127 - tearRipple))
    if step != 4 { stroke(surface, 0x6DA7B9, 4) }
    if step == 0 {
      label("ocular_cornea_tear", 105, 72, 130); line(106, 83, 106, 118, Self.blue, 1.2); label("ocular_cornea_epithelium", 176, 318, 248)
    } else {
      label("ocular_cornea_flat", 277, 67, 141); line(294, 77, 309, 128, Self.coral, 1.2)
      label("ocular_cornea_basal", 100, 318, 150); line(100, 298, 100, 252, Self.coral, 1.2)
    }
  }
}
