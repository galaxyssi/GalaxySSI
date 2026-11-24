import SwiftUI

struct GalaxySSIHealthAtlasSatelliteDrawing {
  let art: GalaxySSIHealthAtlasIllustratedDrawing
  private typealias G = GalaxySSIHealthAtlasSatelliteGeometry
  func scene(_ step: Int, _ t: Double) {
    switch step {
    case 0:
      fiber(); lamina(G.lamina(180, 41)); satellite(180, 184, 36, 13, 0x9CCEC1)
      trace(G.lamina(180, 41), G.progress(t, 0, 0.65), 0x336B5B); trace(G.sarcolemma(0), G.progress(t, 0.23, 1), 0xA64C59)
      lead("lamina", 87, 111, 180, 147, 0x5E766B); lead("cell", 265, 111, 202, 177, 0x28675D); lead("sarcolemma", 92, 326, 86, 294, 0x8F4E59); fiberLabel(261)
    case 1:
      let state = G.progress(t, 0.22, 0.88), y = 184 - 9 * state
      fiber(); lamina(G.lamina(180, 41 + 12 * state)); satellite(180, y, 36 + 3 * state, 13 + 11 * state, G.mix(0x9CCEC1, 0xC9E4D7, state))
      art.stroke(GalaxySSIHealthAtlasSectionLessonView.path(G.signal, width: 360, height: 360), 0x966237, 0.85)
      for i in 0...2 {
        let signal = (t - Double(i) * 0.13) / 0.58
        if (0...1).contains(signal) { art.at(G.signal, signal) { x, yy in
          let r = 3 + 2.8 * (1 - signal)
          var p = Path(); p.move(to: CGPoint(x: x, y: yy - r)); p.addLine(to: CGPoint(x: x + r, y: yy)); p.addLine(to: CGPoint(x: x, y: yy + r)); p.addLine(to: CGPoint(x: x - r, y: yy)); p.closeSubpath()
          art.fill(p, 0xF5D39A); art.stroke(p, 0x966237, 1.15)
        } }
      }
      art.label("muscle_satellite_renewal_art_signals", 101, 95, 150); lead(state < 0.45 ? "cell" : "active", 263, 95, 200, y - 8, 0x28675D); fiberLabel(180)
    case 2:
      let y = 175 - 11 * G.progress(t, 0, 0.66), pinch = G.progress(t, 0.12, 0.75), apart = G.progress(t, 0.75, 0.97)
      fiber(); lamina(G.lamina(180, 53 + 14 * pinch, span: 65 + 42 * pinch))
      if t < 0.75 {
        paintCell(G.dividing(y, pinch), 0xC9E4D7, 0x28675D)
        let separation = 30 * G.progress(t, 0.12, 0.7)
        nucleus(180 - separation, y, 10, 8, 0x444265)
        if separation > 0 { nucleus(180 + separation, y, 10, 8, 0x444265) }
      } else {
        let offset = 30 + 8 * apart
        satellite(180 - offset, y, 30 - 3 * apart, 22 - apart, 0xC9E4D7); satellite(180 + offset, y, 30 - 3 * apart, 22 - apart, 0xC9E4D7)
      }
      art.label("muscle_satellite_renewal_art_" + (t < 0.75 ? "division" : "daughters"), 180, 100, 170); fiberLabel(180)
    case 3:
      let settle = G.progress(t, 0.06, 0.88), left = 142 - 35 * settle, right = 218 + 29 * settle, leftY = 164 + 20 * settle, rightY = 164 + 9 * settle
      fiber(); lamina(G.branchLamina(left, right, 127 + 18 * settle, 127 + 12 * settle))
      satellite(left, leftY, 27 + 7 * settle, 21 - 8 * settle, G.mix(0xC9E4D7, 0x9CCEC1, settle)); myoblast(right, rightY, settle)
      lead("reserve", 91, 96, left, leftY - 10, 0x28675D); lead("myoblast", 266, 96, right, rightY - 11, 0x966237); fiberLabel(180)
    default:
      let approach = G.progress(t, 0, 0.43), merge = G.progress(t, 0.43, 0.93), rise = t < 0.43 ? 0 : 30 * (1 - merge)
      fiber(rise); lamina(G.lamina(107, 43, 247, 54 * (1 - merge), span: 54)); satellite(107, 184, 34, 13, 0x9CCEC1)
      if t < 0.43 { myoblast(247, 173 + 15 * approach, 1) }
      else { let y = 188 + 34 * merge; nucleus(247, y, 12, 5.5, 0x754049, rim: 0xF5D39A); lead("nucleus", 265, 326, 247, y + 7, 0x966237) }
      lead("reserve", 89, 96, 107, 174, 0x28675D); lead("fusion", 267, 96, 272, t < 0.43 ? 169 + 22 * approach : 202 - 0.45 * rise, 0x966237); fiberLabel(90)
    }
  }
  private func fiber(_ rise: Double = 0) {
    let path = G.fiber(rise); art.gradient(path, 202, 296, 0xF5C8AD, 0xD99B94)
    var clipped = art.context; clipped.clip(to: path); let inside = GalaxySSIHealthAtlasSatelliteDrawing(art: art.copy(clipped))
    for row in 0...3 {
      let y = 220 + 18 * Double(row)
      inside.art.line(33, y, 327, y, 0x72FFF0D5, 7); inside.art.line(37, y + 7, 323, y + 7, 0x62A5656B, 1)
    }
    for i in 0...21 {
      let x = 28 + 15 * Double(i)
      inside.art.line(x, 210, x, 286, 0x46AA626B, 3.1); inside.art.line(x + 4, 213, x + 4, 283, 0x6DFFE8C6, 1.3)
    }
    inside.nucleus(67, 218, 12, 4.4, 0x8B5B75); inside.nucleus(155, 280, 13, 4.5, 0x8B5B75); inside.nucleus(310, 278, 11, 4.4, 0x8B5B75)
    art.stroke(path, 0x8F4E59, 2)
  }
  private func lamina(_ path: Path) { art.stroke(path, 0x5E766B, 5.4); art.stroke(path, 0xD7E3C6, 2.9) }
  private func satellite(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ tint: UInt32) {
    paintCell(G.cell(x, y, rx, ry), tint, 0x28675D); nucleus(x, y, min(13, rx * 0.39), ry * 0.46, 0x444265)
  }
  private func myoblast(_ x: Double, _ y: Double, _ d: Double) {
    paintCell(G.cell(x, y, 27 + 11 * d, 21 - 7 * d), G.mix(0xC9E4D7, 0xF5D39A, d), G.mix(0x28675D, 0x966237, d))
    nucleus(x, y, 10.5 + 1.5 * d, 8 - 2.5 * d, G.mix(0x444265, 0x754049, d))
  }
  private func paintCell(_ path: Path, _ tint: UInt32, _ edge: UInt32) { art.fill(path, tint); art.stroke(path, edge, 1.8) }
  private func nucleus(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ tint: UInt32, rim: UInt32? = nil) {
    art.oval(x - rx, y - ry, x + rx, y + ry, fill: tint, border: rim ?? tint)
    if ry > 5 { art.disc(x - rx * 0.26, y - ry * 0.22, 1.35, 0xE0C7BA) }
  }
  private func trace(_ path: Path, _ fraction: Double, _ tint: UInt32) {
    let head = fraction * 1.31, tail = max(0, head - 0.31), end = min(1, head)
    guard end > tail else { return }
    let segment = path.trimmedPath(from: tail, to: end); art.stroke(segment, GalaxySSIHealthAtlasIllustratedDrawing.cream, 7.4); art.stroke(segment, tint, 3.6)
  }
  private func fiberLabel(_ x: Double) { lead("fiber", x, 326, x, 268, 0x8F4E59) }
  private func lead(_ key: String, _ x: Double, _ y: Double, _ tx: Double, _ ty: Double, _ tint: UInt32) {
    let start = ty > y ? y + 8 : y - 17, elbow = ty > y ? ty - 12 : ty + 12
    for (color, width) in [(GalaxySSIHealthAtlasIllustratedDrawing.cream, 3.2), (UInt32(0x52686B), 1.05)] {
      art.line(x, start, tx, elbow, color, width); art.line(tx, elbow, tx, ty, color, width)
    }
    art.disc(tx, ty, 2.15, tint, border: GalaxySSIHealthAtlasIllustratedDrawing.cream); art.label("muscle_satellite_renewal_art_" + key, x, y, 146)
  }
}
