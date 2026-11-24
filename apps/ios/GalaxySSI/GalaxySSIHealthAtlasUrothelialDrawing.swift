import SwiftUI

struct GalaxySSIHealthAtlasUrothelialGeometry {
  let stretch: Double
  let x: [Double]
  let fold: [Double]
  let surface: [Double]
  var topDepth: Double { 34 - 17 * stretch }
  var middleDepth: Double { topDepth + 30 - 12 * stretch }
  var basalDepth: Double { middleDepth + 18 - 6 * stretch }
  init(step: Int, fraction t: Double) {
    let s = t * t * (3 - 2 * t)
    let stretch = step == 0 ? 0.12 * s : step == 1 ? 0.12 + 0.68 * s : step == 2 ? 0.80 + 0.20 * s : 1 - s
    self.stretch = stretch
    let width = 252 + 62 * stretch
    x = (0...48).map { 180 + width * (Double($0) / 48 - 0.5) }
    let fold = (0...48).map { 174 + 19 * stretch + 27 * (1 - stretch) * cos(Double($0) * 4 * .pi / 48) }
    self.fold = fold
    surface = (0...48).map { fold[$0] - (13 - 10 * stretch) * sin(Double($0 % 8) * .pi / 8) }
  }
}

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func urothelialBarrier(_ step: Int, _ t: Double) {
    let g = GalaxySSIHealthAtlasUrothelialGeometry(step: step, fraction: t)
    var lumen = Path(); lumen.move(to: CGPoint(x: g.x[0], y: 56)); lumen.addLine(to: CGPoint(x: g.x[48], y: 56))
    for i in stride(from: 48, through: 0, by: -1) { lumen.addLine(to: CGPoint(x: g.x[i], y: g.surface[i])) }
    lumen.closeSubpath(); gradient(lumen, 57, 211, 0xE8F6F4, 0xC4E3DF)
    var support = Path(); support.move(to: CGPoint(x: g.x[0], y: g.fold[0] + g.basalDepth))
    for i in 1...48 { support.addLine(to: CGPoint(x: g.x[i], y: g.fold[i] + g.basalDepth)) }
    for i in stride(from: 48, through: 0, by: -1) { support.addLine(to: CGPoint(x: g.x[i], y: g.fold[i] + g.basalDepth + 23)) }
    support.closeSubpath(); fill(support, 0xE6CBC0)
    for i in stride(from: 2, to: 48, by: 4) { let y = g.fold[i] + g.basalDepth + 12; line(g.x[i] - 4, y - 1, g.x[i] + 4, y + 1, 0xB88580, 1.3) }
    for i in stride(from: 0, to: 48, by: 4) { urothelialCell(g, i, i + 4, g.middleDepth, g.basalDepth, 213, 310, 0xEEB4AB, 0xAD788D, 5, 4 - g.stretch) }
    for i in stride(from: 0, to: 48, by: 6) { urothelialCell(g, i, i + 6, g.topDepth, g.middleDepth, 165, 280, 0xF5CCBA, 0xCB8D9A, 7 + 2 * g.stretch, 6 - 2 * g.stretch) }
    for i in stride(from: 0, to: 48, by: 8) { urothelialCell(g, i, i + 8, 0, g.topDepth, 123, 241, 0xFFDFC6, 0xDD9791, 9 + 3 * g.stretch, 6 - 3 * g.stretch) }
    var barrier = Path(); barrier.move(to: CGPoint(x: g.x[0], y: g.surface[0]))
    for i in 1...48 { barrier.addLine(to: CGPoint(x: g.x[i], y: g.surface[i])) }
    stroke(barrier, 0x287565, 2.4)
    for i in stride(from: 8, to: 48, by: 8) {
      let y = g.surface[i] + 3
      if step == 2 { disc(g.x[i], y, 6, 0xFFE7AE) }
      line(g.x[i] - 3, y, g.x[i] + 3, y, 0x287565, 2.9); line(g.x[i], y - 2, g.x[i], y + 4, 0x287565, 2.2)
    }
    label("urothelial_geometry_lumen", 180, 40, 222); label("urothelial_geometry_support", 180, 326, 236)
    switch step {
    case 1:
      label("urothelial_geometry_umbrella", 190, 88, 185); line(190, 97, g.x[28], g.surface[28] - 3, 0x287565, 1.25)
      urothelialSpan(114, false, t); urothelialSpan(246, true, t)
    case 2:
      for i in stride(from: 5, to: 48, by: 7) {
        let approach = min(1, max(0, t * 1.36 - Double(i % 3) * 0.10)), gap = 67 - 51 * approach
        let cx = min(g.x[48] - 12, max(g.x[0] + 5, g.x[i] + 3 * wave(t + Double(i) / 11)))
        disc(cx, g.surface[i] - gap, 3.5, 0x508594); disc(cx + 7, g.surface[i] - gap - 12, 2.3, 0x7CA8AD)
      }
      label("urothelial_geometry_junction", 180, 85, 150); line(180, 94, g.x[24], g.surface[24] - 4, 0x287565, 1.4)
    default:
      label("urothelial_geometry_fold", 117, 88, 134); line(117, 97, g.x[10], g.surface[10] - 3, 0x287565, 1.25)
      if step > 2 { urothelialSpan(57, true, t); urothelialSpan(303, false, t) }
    }
  }
  private func urothelialCell(_ g: GalaxySSIHealthAtlasUrothelialGeometry, _ left: Int, _ right: Int,
    _ top: Double, _ bottom: Double, _ shadeTop: Double, _ shadeBottom: Double, _ from: UInt32, _ to: UInt32,
    _ nucleusW: Double, _ nucleusH: Double) {
    let upper = top == 0 ? g.surface : g.fold
    var path = Path(); path.move(to: CGPoint(x: g.x[left], y: upper[left] + top))
    for i in (left + 1)...right { path.addLine(to: CGPoint(x: g.x[i], y: upper[i] + top)) }
    for i in stride(from: right, through: left, by: -1) { path.addLine(to: CGPoint(x: g.x[i], y: g.fold[i] + bottom)) }
    path.closeSubpath(); gradient(path, shadeTop, shadeBottom, from, to); stroke(path, 0x995B6E, 1.15)
    let i = (left + right) / 2, y = (upper[i] + top + g.fold[i] + bottom) / 2
    oval(g.x[i] - nucleusW, y - nucleusH, g.x[i] + nucleusW, y + nucleusH, fill: 0xAC7594, border: 0x925D80)
  }
  private func urothelialSpan(_ start: Double, _ right: Bool, _ t: Double) {
    let direction = right ? 1.0 : -1.0, tip = start + direction * (16 + 18 * t)
    line(start, 119, tip, 119, 0x287565, 1.7)
    line(tip, 119, tip - direction * 6, 115, 0x287565, 1.7); line(tip, 119, tip - direction * 6, 123, 0x287565, 1.7)
  }
}
