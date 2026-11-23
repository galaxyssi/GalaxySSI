import SwiftUI

extension GalaxySSIHealthAtlasLymphImmuneDrawing {
  func lymphScene(_ motion: Motion) {
    switch motion.chapter {
    case 0: tissueFluid(motion.fraction)
    case 1: capillaryEntry(motion.fraction)
    case 2: collectingVessel(motion)
    case 3: lymphSection("lymph-nodes", motion.fraction)
    default: lymphSection("thoracic-duct", motion.fraction)
    }
  }
  private func tissueFluid(_ t: Double) {
    var path = Path(); path.move(to: CGPoint(x: 24, y: 67))
    path.addCurve(to: CGPoint(x: 336, y: 63), control1: CGPoint(x: 122, y: 86), control2: CGPoint(x: 186, y: 51))
    path.addLine(to: CGPoint(x: 336, y: 113))
    path.addCurve(to: CGPoint(x: 24, y: 118), control1: CGPoint(x: 186, y: 102), control2: CGPoint(x: 122, y: 138)); path.closeSubpath()
    shaded(path, top: 64, bottom: 120, from: 0xF4C9CC, to: 0xC98495, edge: Self.rose)
    for i in 0...5 {
      let x = 37 + 286 * Motion.loop(t * 1.04 + Double(i) / 6), y = 91 + 6 * sin(x / 65)
      oval(x, y, 13, 7.5, Self.rose); oval(x - 1, y - 1, 7.1, 3, 0xE4A0A4)
    }
    for i in 0...5 {
      let f = Motion.loop(t * 1.24 + Double(i) / 6), x = Double(58 + 43 * i) + 9 * sin(f * 3)
      tracer(x, 100 + 96 * f, Self.blue, 3.6)
    }
    for i in 0...3 {
      let x = Double(60 + i * 77), y = Double(253 + i % 2 * 31)
      var tissue = Path(); tissue.move(to: CGPoint(x: x - 27, y: y - 5))
      tissue.addCurve(to: CGPoint(x: x + 29, y: y - 7), control1: CGPoint(x: x - 21, y: y - 31), control2: CGPoint(x: x + 21, y: y - 30))
      tissue.addCurve(to: CGPoint(x: x - 27, y: y - 5), control1: CGPoint(x: x + 43, y: y + 22), control2: CGPoint(x: x - 37, y: y + 33)); tissue.closeSubpath()
      shaded(tissue, top: 200, bottom: 300, from: 0xEEE6DC, to: 0xD8C3B4, edge: 0xAD918A)
      oval(x + 4, y, 11, 6, 0xAD8C9D); oval(x + 2, y - 1, 5, 2.8, 0xD5BCC5)
    }
    label(180, 40, "lymph_flow_blood"); leader(169, 219, 185, 177, "lymph_flow_fluid", Self.blue)
  }
  private func capillaryEntry(_ t: Double) {
    let flap = 6 + 7 * sin(.pi * t)
    var path = Path(); path.move(to: CGPoint(x: 337, y: 142)); path.addLine(to: CGPoint(x: 83, y: 142))
    path.addCurve(to: CGPoint(x: 44, y: 196), control1: CGPoint(x: 35, y: 142), control2: CGPoint(x: 24, y: 170))
    path.addQuadCurve(to: CGPoint(x: 94, y: 217), control: CGPoint(x: 57, y: 217)); path.addLine(to: CGPoint(x: 337, y: 217)); path.closeSubpath()
    shaded(path, top: 133, bottom: 222, from: 0xD0EBE6, to: 0x86B8B3, edge: Self.teal)
    for i in 0...15 { oval(55 + Double(i) * 17.5, 210, 4.4, 2.2, 0x568D87) }
    for x in [120.0, 222] {
      line(x - 15, 142, x + 14, 142, 0xD1E9E4, 5)
      var flapPath = Path(); flapPath.move(to: CGPoint(x: x - 17, y: 141))
      flapPath.addQuadCurve(to: CGPoint(x: x + 5, y: 141 + flap), control: CGPoint(x: x - 6, y: 140)); stroke(flapPath, Self.teal, 3.5)
      var lip = Path(); lip.move(to: CGPoint(x: x + 18, y: 141))
      lip.addQuadCurve(to: CGPoint(x: x + 9, y: 145), control: CGPoint(x: x + 12, y: 142)); stroke(lip, Self.teal, 2.8)
      for i in 0...3 {
        let f = Motion.loop(t * 1.5 + Double(i) * 0.25), dx = f < 0.62 ? (f - 0.62) * 9 : (f - 0.62) * 70
        tracer(x + 9 + dx, 72 + min(f, 0.75) * 145, Self.blue, 3)
      }
    }
    for i in 0...4 { tracer(100 + 215 * Motion.loop(t * 1.38 + Double(i) / 5), 190, Self.teal, 4) }
    label(103, 54, "lymph_flow_fluid"); leader(263, 52, 221, 143, "lymph_flow_flaps", Self.teal)
    label(180, 267, "lymph_flow_capillary")
  }
  private func collectingVessel(_ motion: Motion) {
    let center = 176.0, edge = center - 22, bulge = motion.bulge
    var path = Path(); path.move(to: CGPoint(x: 25, y: edge)); path.addLine(to: CGPoint(x: 84, y: edge))
    path.addCurve(to: CGPoint(x: 273, y: edge), control1: CGPoint(x: 124, y: edge - bulge), control2: CGPoint(x: 214, y: edge - bulge))
    path.addLine(to: CGPoint(x: 335, y: edge)); path.addLine(to: CGPoint(x: 335, y: 2 * center - edge)); path.addLine(to: CGPoint(x: 273, y: 2 * center - edge))
    path.addCurve(to: CGPoint(x: 84, y: 2 * center - edge), control1: CGPoint(x: 214, y: 2 * center - edge + bulge), control2: CGPoint(x: 124, y: 2 * center - edge + bulge))
    path.addLine(to: CGPoint(x: 25, y: 2 * center - edge)); path.closeSubpath()
    shaded(path, top: 133, bottom: 222, from: 0xD0EBE6, to: 0x86B8B3, edge: Self.teal, width: 2.8)
    valve(84, center, open: motion.pumpStage.inletOpen); valve(273, center, open: motion.pumpStage.outletOpen)
    for i in 0...3 {
      let fraction = Motion.loop(motion.fraction * 2.6 + Double(i) * 0.25)
      let x: Double
      switch motion.pumpStage {
      case .filling: x = 36 + fraction * 153
      case .holding: x = Double(143 + i * 22)
      case .emptying: x = 160 + fraction * 165
      }
      tracer(x, Double(166 + i % 2 * 20), Self.teal, 3.8)
    }
    let key = motion.pumpStage == .filling ? "lymph_flow_filling" : motion.pumpStage == .holding ? "lymph_flow_holding" : "lymph_flow_contracting"
    label(180, 91, key); label(180, 263, "lymph_flow_capillary_collecting")
  }
  private func valve(_ x: Double, _ y: Double, open: Bool) {
    let gap = open ? 12.0 : 0
    for direction in [-1.0, 1.0] {
      var path = Path(); path.move(to: CGPoint(x: x, y: y + direction * 22))
      path.addQuadCurve(to: CGPoint(x: x + 16, y: y + direction * gap), control: CGPoint(x: x + 11, y: y + direction * 19))
      stroke(path, Self.cream, 6); stroke(path, Self.teal, 2)
    }
  }
  private func lymphSection(_ id: String, _ t: Double) {
    guard let section = Motion.sections[id] else { return }
    var local = context; local.translateBy(x: 0, y: 42); let drawing = copy(local)
    local.draw(local.resolve(Image(section.asset)), in: CGRect(x: 0, y: 0, width: 360, height: 280))
    for i in 0...8 {
      let position = Motion.loop(t * 1.08 + Double(i) / 9)
      guard let sample = GalaxySSIHealthAtlasFunctionPath.sample(section.route, position: position, width: 360, height: 280) else { continue }
      drawing.tracer(sample.point.x, sample.point.y, Self.teal, 3.7)
    }
    if id == "lymph-nodes" {
      leader(81, 54, 94, 85, "lymph_flow_in", Self.teal); leader(281, 274, 299, 230, "lymph_flow_out", Self.teal)
    } else {
      leader(70, 204, 175, 208, "lymph_flow_duct", Self.teal); leader(233, 67, 231, 103, "lymph_flow_vein", Self.teal)
    }
  }
}
