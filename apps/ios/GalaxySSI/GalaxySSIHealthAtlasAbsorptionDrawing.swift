import SwiftUI

private typealias AbsorptionMotion = GalaxySSIHealthAtlasAbsorptionMotion
private typealias AbsorptionShapes = GalaxySSIHealthAtlasAbsorptionShapes

extension GalaxySSIHealthAtlasIllustratedDrawing {
  func absorptionScene(step: Int, t: Double) {
    absorptionVillus(highlight: step == 1, progress: step == 0 ? t : nil)
    absorptionInset(progress: step == 1 ? t : nil)
    if step == 2 || step == 4 {
      absorptionFlow(AbsorptionMotion.bloodRoute, t); absorptionFlow(AbsorptionMotion.cellSolutes, t)
      absorptionLegend(.solute, 26, 107, 144, "absorption_story_label_solutes")
    }
    if step == 3 {
      absorptionFlow(AbsorptionMotion.lipidIntake, t, count: 1); absorptionFlow(AbsorptionMotion.cellLipids, t, count: 2)
      absorptionCargo(.chylomicron, 309, 164, radius: 3 + 2 * t)
      absorptionLegend(.lipid, 26, 107, 144, "absorption_story_label_lipid")
    }
    if step == 4 { absorptionFlow(AbsorptionMotion.lymphRoute, t); absorptionFlow(AbsorptionMotion.cellExport, t, count: 2) }
    if step >= 3 { absorptionLegend(.chylomicron, 218, 283, 116, "absorption_story_label_chylomicrons") }
  }
  private func absorptionVillus(highlight: Bool, progress: Double?) {
    gradient(AbsorptionShapes.villus, 60, 294, 0xFFEEE0, 0xE9B7A6)
    var local = context; local.clip(to: AbsorptionShapes.villus)
    let art = copy(local)
    art.stroke(AbsorptionShapes.surface, Self.coral, 29)
    local.stroke(AbsorptionShapes.surface, with: .linearGradient(Gradient(colors: [Self.color(0xFFD7BA), Self.color(0xD7918C)]),
      startPoint: CGPoint(x: 0, y: 60), endPoint: CGPoint(x: 0, y: 294)), style: StrokeStyle(lineWidth: 27, lineCap: .round, lineJoin: .round))
    art.stroke(AbsorptionShapes.features.cellBoundaries, 0xBA7C78, 0.8); art.fill(AbsorptionShapes.features.nuclei, Self.violet)
    art.stroke(AbsorptionShapes.capillaries, 0xAD5264, 10); art.stroke(AbsorptionShapes.capillaries, 0xF6A1A0, 6.5)
    art.stroke(AbsorptionShapes.lacteal, Self.teal, 18); art.stroke(AbsorptionShapes.lacteal, 0xB8DDD0, 13)
    stroke(AbsorptionShapes.surface, Self.coral, 1.4)
    stroke(AbsorptionShapes.features.microvilli, highlight ? Self.teal : AbsorptionShapes.brush, highlight ? 1.45 : 0.9)
    if let progress { stroke(AbsorptionShapes.surface.trimmedPath(from: 0, to: CGFloat(progress)), Self.teal, 2.2) }
    line(29, 294, 198, 294, Self.coral, 1.2)
    label("absorption_story_label_lumen", 118, 38, 112); label("absorption_story_label_villus", 44, 77, 67)
    line(57, 82, 70, 88, AbsorptionShapes.leader, 1)
    label("absorption_story_label_capillaries", 68, 319, 116); line(68, 305, 69, 287, 0xAD5264, 1)
    label("absorption_story_label_lacteal", 162, 319, 64); line(152, 305, 137, 288, Self.teal, 1)
  }
  private func absorptionInset(progress: Double?) {
    let highlight = progress != nil, accent = highlight ? Self.teal : AbsorptionShapes.leader
    oval(162, 114, 179, 132, fill: 0x22FFF8EB, border: accent)
    line(180, 122, 208, 91, accent, 1); line(208, 91, 218, 91, accent, 1)
    rounded(218, 84, 346, 253, 7, 0xDCEEED); rounded(218, 108, 346, 253, 7, 0xF5D0B9); rounded(218, 108, 346, 223, 4, 0xE7B5A5)
    gradient(AbsorptionShapes.enterocyte, 108, 225, 0xFFE3C9, 0xE9AD9E); stroke(AbsorptionShapes.enterocyte, highlight ? Self.teal : Self.coral, 1.4)
    stroke(AbsorptionShapes.insetBrush, AbsorptionShapes.brush, 1.8)
    if let progress {
      var brush = context; brush.clip(to: Path(CGRect(x: 218, y: 94, width: 128 * progress, height: 16)))
      copy(brush).stroke(AbsorptionShapes.insetBrush, Self.teal, 2.35)
    }
    oval(270, 177, 292, 199, fill: 0xBD90AD, border: Self.violet); oval(223, 181, 236, 199, fill: 0xBD90AD, border: Self.violet); oval(326, 181, 340, 199, fill: 0xBD90AD, border: Self.violet)
    label("absorption_story_label_brush_border", 281, 68, 128); line(281, 74, 281, 97, accent, 1)
    line(281, 226, 281, 265, AbsorptionShapes.leader, 1); label("absorption_story_label_enterocyte", 281, 280, 128)
  }
  private func absorptionFlow(_ route: AbsorptionMotion.Transport, _ t: Double, count: Int = 3) {
    let color = route.cargo == .solute ? Self.blue : AbsorptionShapes.lipid
    stroke(GalaxySSIHealthAtlasSectionLessonView.path(route.path, width: 360, height: 360), color, 1.2)
    at(route.path, 0.8) { sx, sy in at(route.path, 1) { x, y in arrow(sx, sy, x, y, color) } }
    for index in 0..<count {
      at(route.path, AbsorptionMotion.fraction(t, index: index, count: count)) { x, y in absorptionCargo(route.cargo, x, y) }
    }
  }
  private func absorptionCargo(_ kind: AbsorptionMotion.Cargo, _ x: Double, _ y: Double, radius: Double = 4.2) {
    switch kind {
    case .solute: disc(x, y, radius * 0.83, Self.blue, border: Self.cream)
    case .lipid:
      var local = context; local.translateBy(x: x, y: y); local.rotate(by: .degrees(45)); local.translateBy(x: -x, y: -y)
      copy(local).rounded(x - 2.5, y - 2.5, x + 2.5, y + 2.5, 0.7, AbsorptionShapes.lipid)
    case .chylomicron: disc(x, y, radius, 0xFFDD90, border: AbsorptionShapes.lipid); disc(x, y, radius * 0.36, AbsorptionShapes.lipid)
    }
  }
  private func absorptionLegend(_ kind: AbsorptionMotion.Cargo, _ marker: Double, _ x: Double, _ width: Double, _ key: String) {
    absorptionCargo(kind, marker, 340); label(key, x, 344, width)
  }
}
