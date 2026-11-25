import SwiftUI

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func tenocyteTendonScene(_ step: Int, _ t: Double) {
    let amount = GalaxySSIHealthAtlasTenocyteTendonGeometry.deformation(step: step, fraction: t)
    tenocyteTendonAxis(step, amount, t)
    tenocyteTendonMatrix(amount)
    tenocyteTendonCallout("fibers", 94, 84, 196, 0x406F67)
    tenocyteTendonCallout("nucleus", 251, 196, 143 - 2 * amount, 0x584051)
    tenocyteTendonProfile(amount)
  }
  private func tenocyteTendonAxis(_ step: Int, _ amount: Double, _ phase: Double) {
    label("tenocyte_tendon_matrix_art_" + (step == 0 ? "axis" : step == 3 ? "release" : "pull"), 180, 33, 152)
    let reach = 18 + 36 * amount, color: UInt32 = step == 0 ? 0x586F68 : 0x80513B
    arrow(125, 49, 125 - reach, 49, color); arrow(235, 49, 235 + reach, 49, color)
    if step == 0 {
      disc(125 - reach * phase, 49, 3.1, Self.cream, border: 0x6B8F87)
      disc(235 + reach * phase, 49, 3.1, Self.cream, border: 0x6B8F87)
    }
  }
  private func tenocyteTendonMatrix(_ amount: Double) {
    let g = GalaxySSIHealthAtlasTenocyteTendonGeometry.self
    fill(g.field, 0xE9F1EC)
    var local = context; local.clip(to: g.field)
    let art = copy(local)
    for (row, y) in g.fiberYs.enumerated() {
      let adjacent = row == 3 || row == 4, shift = (3.5 - Double(row)) * 5 * amount
      let spread = 1 + 0.13 * amount, x = 180 + shift
      let rise = (row.isMultiple(of: 2) ? 3.1 : 4.6) * (1 - 0.74 * amount)
      let path = g.fiber(x: x, y: y, spread: spread, rise: rise)
      art.stroke(path, adjacent ? 0xB7D2C7 : 0xCFDFD8, adjacent ? 8 : 6)
      art.stroke(path, adjacent ? 0x406F67 : 0x6B8F87, adjacent ? 1.8 : 1.1)
      if adjacent { art.tenocyteTendonMarks(x - 46 * spread, x + 46 * spread, y) }
    }
    art.tenocyteTendonCell(85 - 4 * amount, 97, 31, 4.5, 0, secondary: true)
    art.tenocyteTendonCell(274 + 3 * amount, 187, 37, 4.8, 0, secondary: true)
    art.tenocyteTendonCell(180, 143, 57, 12, amount)
    stroke(g.field, 0x9CB5AE, 1.1)
  }
  private func tenocyteTendonMarks(_ left: Double, _ right: Double, _ y: Double) {
    let diamond = Path { p in
      p.move(to: CGPoint(x: left, y: y - 4.5)); p.addLine(to: CGPoint(x: left + 4.5, y: y))
      p.addLine(to: CGPoint(x: left, y: y + 4.5)); p.addLine(to: CGPoint(x: left - 4.5, y: y)); p.closeSubpath()
    }
    fill(diamond, Self.cream); stroke(diamond, 0x80513B, 1.5)
    disc(right, y, 3.8, Self.cream, border: 0x80513B)
  }
  private func tenocyteTendonCell(_ x: Double, _ y: Double, _ length: Double, _ height: Double, _ amount: Double, secondary: Bool = false) {
    let g = GalaxySSIHealthAtlasTenocyteTendonGeometry.self
    let path = g.cell(x: x, y: y, length: length, height: height, amount: amount)
    fill(path, secondary ? 0xC6AFB9 : 0xE2BDC8); stroke(path, 0x715163, secondary ? 1 : 1.55)
    fill(g.cell(x: x + 2, y: y, length: length * 0.40, height: height * 0.56, amount: amount), 0x584051)
    if !secondary { line(x - length * 0.22, y - 1.4, x + length * 0.25, y - 2.4 * amount, 0xB68E9D, 1.15) }
  }
  private func tenocyteTendonCallout(_ key: String, _ x: Double, _ targetX: Double, _ targetY: Double, _ color: UInt32) {
    line(targetX, targetY, x, 224, 0xF6F6E9, 3.1); line(targetX, targetY, x, 224, 0x586F68, 1.1)
    disc(targetX, targetY, 2.8, Self.cream, border: color)
    label("tenocyte_tendon_matrix_art_" + key, x, 241, 139)
  }
  private func tenocyteTendonProfile(_ amount: Double) {
    line(30, 254, 330, 254, 0xB3C2B7, 1); label("tenocyte_tendon_matrix_art_profile", 180, 275, 220)
    tenocyteTendonCell(180, 298, 73, 16, amount)
    let resting = GalaxySSIHealthAtlasTenocyteTendonGeometry.cell(x: 180, y: 298, length: 73, height: 16, amount: 0)
    let style = StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round, dash: [4, 3])
    context.stroke(resting, with: .color(Self.color(0x526267)), style: style)
    context.stroke(Path { p in p.move(to: CGPoint(x: 100, y: 332)); p.addLine(to: CGPoint(x: 124, y: 332)) }, with: .color(Self.color(0x526267)), style: style)
    label("tenocyte_tendon_matrix_art_rest", 190, 337, 116)
  }
}
