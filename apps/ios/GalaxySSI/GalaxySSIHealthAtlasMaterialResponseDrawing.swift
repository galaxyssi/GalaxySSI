import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasMaterialResponseDrawing {
  let context: GraphicsContext
  let language: String
  private static let blue: UInt32 = 0x3A778F, teal: UInt32 = 0x3F7770, rose: UInt32 = 0xB6757F
  private func color(_ value: UInt32) -> Color { GalaxySSIHealthAtlasIllustratedDrawing.color(value) }
  func enamelSection(_ model: GalaxySSIHealthAtlasPhysiology) {
    let x = 94.0, y = 70.0, exterior = 9.5 * model.input(1)
    let interior = exterior - 9.5 * model.input(0)
    let enamel: UInt32 = 0xD1E7DF, remainder: UInt32 = 0xDCA989
    oval(x - exterior - 1.5, y - exterior - 1.5, x + exterior + 1.5, y + exterior + 1.5, 0x698E89)
    oval(x - exterior, y - exterior, x + exterior, y + exterior, enamel)
    oval(x - interior, y - interior, x + interior, y + interior, remainder)
    let from = x + interior, to = x + exterior
    line(from, y, to, y, 0x325751, 1.7)
    line(from, y - 4, from, y + 4, 0x325751, 1.7)
    line(to, y - 4, to, y + 4, 0x325751, 1.7)
    rectangle(178, 46, 195, 57, enamel, radius: 3)
    rectangle(178, 82, 195, 93, remainder, radius: 3)
    label("tooth_enamel_section_enamel", 261, 56, 116)
    label("tooth_enamel_section_inside", 261, 92, 116)
    label("tooth_enamel_section_crown", x, 148, 155)
  }
  func tubuleMarker(_ model: GalaxySSIHealthAtlasPhysiology) {
    guard let amounts = GalaxySSIHealthAtlasTubuleRetentionAmounts(segmentA: model.input(0), segmentB: model.input(1)) else { return }
    arrow(86, 78, 136, 78, Self.teal, 1.9); arrow(204, 78, 254, 78, Self.teal, 1.9)
    for (index, node) in [("start", amounts.starting), ("after_a", amounts.afterA), ("after_b", amounts.remaining)].enumerated() {
      let x = 52 + Double(index) * 118, r = 29.0
      oval(x - r, 78 - r, x + r, 78 + r, 0xC9DFDF)
      let marker = r * sqrt(node.1 / amounts.starting)
      oval(x - marker, 78 - marker, x + marker, 78 + marker, 0x659D9D)
      let value = GalaxySSIHealthAtlasPhysiologyText.number(node.1, digits: 1, language: language)
      context.draw(Text(verbatim: value).font(.system(size: 13)).foregroundColor(.primary),
        at: CGPoint(x: x, y: 128 - UIFont.systemFont(ofSize: 13).ascender), anchor: .top)
      label("renal_tubule_retention_" + node.0, x, 147, 102)
    }
  }
  func circadianDial(_ model: GalaxySSIHealthAtlasPhysiology) {
    let cx = 97.0, cy = 75.0, r = 53.0
    let light: UInt32 = 0xEFD19B, dark: UInt32 = 0x91B6BC
    sector(cx, cy, r, -90, 180, light); sector(cx, cy, r, 90, 180, dark)
    for tick in 0..<12 {
      let direction = (Double(tick) * 30 - 90) * .pi / 180, dx = cos(direction), dy = sin(direction)
      line(cx + dx * (r - 7), cy + dy * (r - 7), cx + dx * r, cy + dy * r, 0x3D656B, 1.45)
    }
    let angle = (model.companionValue - 90) * .pi / 180
    let x = cx + cos(angle) * (r - 13), y = cy + sin(angle) * (r - 13)
    line(cx, cy, x, y, 0x1D5558, 3.9)
    oval(cx - 4, cy - 4, cx + 4, cy + 4, 0x1D5558)
    oval(x - 3, y - 3, x + 3, y + 3, 0x1D5558)
    rectangle(178, 45, 193, 55, light, radius: 3)
    rectangle(178, 84, 193, 94, dark, radius: 3)
    label("circadian_light_window_dial_light", 260, 55, 122)
    label("circadian_light_window_dial_dark", 260, 94, 122)
  }
  func adiposeShare(_ model: GalaxySSIHealthAtlasPhysiology) {
    let x = 84.0, y = 70.0, r = 49.0, droplet = model.input(0) * (49 - 3)
    let lipid: UInt32 = 0xE9B967
    oval(x - r, y - r, x + r, y + r, 0x598481)
    oval(x - r + 3, y - r + 3, x + r - 3, y + r - 3, 0xD1E4DC)
    oval(x - droplet, y - droplet, x + droplet, y + droplet, lipid)
    oval(x + 22, y + 23, x + 38, y + 29, 0x72868B)
    let center = 250.0, radius = 48.0
    oval(center - radius, y - radius, center + radius, y + radius, 0xB8D6D0)
    sector(center, y, radius, -90, 360 * model.result / 100, lipid)
    label("adipose_volume_share_cell_view", x, 145, 142)
    label("adipose_volume_share_tissue_view", center, 145, 155)
  }
  private func sector(_ x: Double, _ y: Double, _ radius: Double, _ start: Double, _ sweep: Double, _ tint: UInt32) {
    var path = Path(); path.move(to: CGPoint(x: x, y: y))
    path.addArc(center: CGPoint(x: x, y: y), radius: radius, startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false)
    path.closeSubpath()
    context.fill(path, with: .color(color(tint)))
  }
  func refraction(_ model: GalaxySSIHealthAtlasPhysiology) {
    let x = 170.0, y = 76.0, incidentDegrees = model.input(0), refractedDegrees = model.result
    let incident = incidentDegrees * .pi / 180, refracted = refractedDegrees * .pi / 180
    rectangle(16, y, 324, 151, 0xD5E9ED, radius: 5)
    line(16, y, 324, y, Self.blue, 2)
    var normal = Path()
    normal.move(to: CGPoint(x: x, y: 11)); normal.addLine(to: CGPoint(x: x, y: 144))
    context.stroke(normal, with: .color(color(0x668895)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [4, 4]))
    func ray(_ fromX: Double, _ fromY: Double, _ dx: Double, _ dy: Double, _ tint: UInt32) {
      let toX = fromX + dx * 62, toY = fromY + dy * 62
      line(fromX, fromY, toX, toY, tint, 3)
      let baseX = toX - 8 * dx, baseY = toY - 8 * dy
      var tip = Path()
      tip.move(to: CGPoint(x: toX, y: toY))
      tip.addLine(to: CGPoint(x: baseX - 3.5 * dy, y: baseY + 3.5 * dx))
      tip.addLine(to: CGPoint(x: baseX + 3.5 * dy, y: baseY - 3.5 * dx)); tip.closeSubpath()
      context.fill(tip, with: .color(color(tint)))
    }
    ray(x - sin(incident) * 62, y - cos(incident) * 62, sin(incident), cos(incident), 0xA16629)
    ray(x, y, sin(refracted), cos(refracted), Self.teal)
    for (start, sweep, tint) in [(-90 - incidentDegrees, incidentDegrees, UInt32(0xA16629)),
      (90 - refractedDegrees, refractedDegrees, Self.teal)] {
      var arc = Path()
      arc.addArc(center: CGPoint(x: x, y: y), radius: 25, startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false)
      context.stroke(arc, with: .color(color(tint)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
    }
    label("model_corneal_refraction_incident_ray", 65, 25, 110)
    label("model_corneal_refraction_refracted_ray", 258, 139, 106)
    label("model_corneal_refraction_surface", 253, 65, 128)
  }
  func ciliaTrack(_ model: GalaxySSIHealthAtlasPhysiology) {
    let left = 26.0, right = 314.0, step = (314.0 - 26) / 9
    let marker = left + (right - left) * (model.companionValue / 100)
    rectangle(left - 12, 34, right + 12, 64, 0xD3E8E3, radius: 14)
    for i in 0..<9 {
      let x = left + step * Double(i)
      rectangle(x + 1, 77, x + step - 1, 121, 0xA4D4CB, radius: 8)
      oval(x + 10, 95, x + 23, 112, 0x598788)
      for branch in 0..<4 {
        let base = x + 4 + Double(branch) * 6
        var cilium = Path()
        cilium.move(to: CGPoint(x: base, y: 80))
        cilium.addQuadCurve(to: CGPoint(x: base + 4, y: (i + branch) % 3 == 0 ? 57 : 60),
          control: CGPoint(x: base - 3, y: 69))
        context.stroke(cilium, with: .color(color(Self.teal)), style: StrokeStyle(lineWidth: 1.65, lineCap: .round))
      }
    }
    line(left, 49, right, 49, 0x7FAAA3, 1.6)
    if marker - left >= 8 { arrow(left, 49, marker - 2, 49, Self.teal, 2.1) }
    oval(marker - 6, 43, marker + 6, 55, 0xBC803F)
    oval(marker - 2, 45, marker + 1, 48, 0xFFE0A5)
    label("airway_ciliary_clearance_track", 170, 145, 300)
  }
  func arterialContinuity(_ model: GalaxySSIHealthAtlasPhysiology) {
    let x = 77.0, y = 67.0, radius = model.input(0) * 1.15
    let speed = model.result / model.kind.bounds.upperBound, outer = radius + 8
    oval(x - outer, y - outer, x + outer, y + outer, 0xBA8290)
    oval(x - radius, y - radius, x + radius, y + radius, 0xEFC8CB)
    line(x - radius, y, x + radius, y, 0x775565, 1.7)
    for edge in [x - radius, x + radius] { line(edge, y - 4, edge, y + 4, 0x775565, 1.7) }
    let start = 156.0, end = 315.0
    line(start, y, end, y, 0xBFD6D7, 3)
    for mark in 0...4 {
      let tick = start + (end - start) * Double(mark) / 4
      line(tick, y - 5, tick, y + 5, 0x759397, 1.5)
    }
    if speed > 0 { arrow(start, y, start + max(8, (end - start) * speed), y, Self.teal, 3.3) }
    else { oval(start - 3, y - 3, start + 3, y + 3, Self.teal) }
    label("arterial_continuity_section", x, 145, 134)
    label("arterial_continuity_speed", (start + end) / 2, 145, 172)
  }
  func diaphragm(_ model: GalaxySSIHealthAtlasPhysiology) {
    let halfWidth = 108 * sqrt(model.input(1) / 250)
    let left = 170 - halfWidth, right = 170 + halfWidth
    let rest = 88.0, shift = model.input(0) * 1.1
    let current = rest + shift
    func dome(_ y: Double) -> Path {
      var path = Path()
      path.move(to: CGPoint(x: left, y: y))
      path.addCurve(to: CGPoint(x: right, y: y),
        control1: CGPoint(x: left + halfWidth * 0.58, y: y - 29),
        control2: CGPoint(x: right - halfWidth * 0.58, y: y - 29))
      return path
    }
    var chest = Path()
    chest.move(to: CGPoint(x: left, y: current))
    chest.addCurve(to: CGPoint(x: left + 14, y: 29),
      control1: CGPoint(x: left, y: 77), control2: CGPoint(x: left - 8, y: 37))
    chest.addCurve(to: CGPoint(x: right - 14, y: 29),
      control1: CGPoint(x: 139, y: 1), control2: CGPoint(x: 201, y: 1))
    chest.addCurve(to: CGPoint(x: right, y: current),
      control1: CGPoint(x: right + 8, y: 37), control2: CGPoint(x: right, y: 77))
    func closeAlongDome(_ path: inout Path) {
      path.addCurve(to: CGPoint(x: left, y: current),
        control1: CGPoint(x: right - halfWidth * 0.58, y: current - 29),
        control2: CGPoint(x: left + halfWidth * 0.58, y: current - 29))
      path.closeSubpath()
    }
    var chamber = chest
    closeAlongDome(&chamber)
    context.fill(chamber, with: .color(color(0xDEEEEF)))
    if shift > 0 {
      var gain = dome(rest)
      gain.addLine(to: CGPoint(x: right, y: current))
      closeAlongDome(&gain)
      context.fill(gain, with: .color(color(0xA7D7C9)))
    }
    context.stroke(chest, with: .color(color(Self.blue)), lineWidth: 2.5)
    context.stroke(dome(rest), with: .color(color(Self.blue)), style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
    context.stroke(dome(current), with: .color(color(Self.teal)), lineWidth: 3.5)
    if shift >= 8 { arrow(170, rest - 21, 170, current - 23, Self.teal, 2) }
    var legend = Path()
    legend.move(to: CGPoint(x: 35, y: 143)); legend.addLine(to: CGPoint(x: 57, y: 143))
    context.stroke(legend, with: .color(color(Self.blue)), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
    line(184, 143, 206, 143, Self.teal, 3)
    label("diaphragm_demo_resting", 111, 147, 98)
    label("diaphragm_demo_current", 261, 147, 98)
  }
  func pelvicSupport(_ model: GalaxySSIHealthAtlasPhysiology) {
    let loadX = 170 + 87 * model.input(1) / 100, load = model.input(0)
    rectangle(61, 70, 279, 84, 0xDDC2A7, radius: 6)
    line(83, 77, 257, 77, 0x9E826C, 1.4)
    oval(loadX - 4, 73, loadX + 4, 81, 0x926B55)
    if load > 0 { arrow(loadX, 63 - 42 * load / 800, loadX, 67, 0x996449, 3.3) }
    for (x, force, key, tint) in [(83.0, model.companionValue, "pelvis_model_left_support", Self.blue),
      (257.0, model.result, "pelvis_model_right_support", Self.teal)] {
      rectangle(x - 26, 121, x + 26, 126, 0xCBDFDB, radius: 2)
      if force > 0 { arrow(x, 118, x, 121 - (8 + 23 * force / 800), tint, 3) }
      label(key, x, 147, 130)
    }
  }
  func cushionContact(_ model: GalaxySSIHealthAtlasPhysiology) {
    let force = model.input(0)
    for (x, area, pressure, key) in [(85.0, 40.0, model.companionValue, "cushion_model_standard_pad"),
      (255.0, model.input(1), model.result, "cushion_model_changed_pad")] {
      let halfWidth = 10 + 49 * area / 90
      rectangle(x - 63, 82, x + 63, 117, 0xF5DEB1, radius: 7)
      rectangle(x - 63, 113, x + 63, 124, 0xB3CEC5, radius: 4)
      for i in 0..<7 {
        let cx = x - 51 + 17 * Double(i), cy = i % 2 == 0 ? 97.0 : 103.0
        oval(cx - 7, cy - 7, cx + 7, cy + 7, 0xE5B97D)
      }
      rectangle(x - halfWidth, 67, x + halfWidth, 80, 0xB8D6D5, radius: 4)
      if force > 0 {
        arrow(x, 56 - 30 * force / 80, x, 63, Self.blue, 2.7)
        var local = context
        local.opacity = (60 + 190 * pressure / 80).rounded() / 255
        Self(context: local, language: language).rectangle(x - halfWidth, 80, x + halfWidth, 85, 0xA96459, radius: 2)
      }
      label(key, x, 147, 145)
    }
  }
  func calfPump(_ model: GalaxySSIHealthAtlasPhysiology) {
    let stroke = model.input(0), total = stroke * model.input(1)
    let returning = total * model.input(2) / 100
    rectangle(43, 32, 140, 122, 0xE2EDED, radius: 18)
    rectangle(50, 39, 133, 115, 0xF3F7F5, radius: 14)
    if stroke > 0 {
      let top = 115 - 71 * stroke / 25
      rectangle(53, top, 130, 113, 0x8AC9BA, radius: min((113 - top) * 0.45, 12))
    }
    line(39, 44, 39, 111, Self.rose, 4)
    line(144, 44, 144, 111, Self.rose, 4)
    line(75, 33, 91, 40, Self.teal, 2.5)
    line(92, 40, 108, 33, Self.teal, 2.5)
    line(75, 115, 91, 122, Self.teal, 2.5)
    line(92, 122, 108, 115, Self.teal, 2.5)
    line(196, 54, 314, 54, 0xC5DED9, 7)
    line(196, 111, 314, 111, 0xEEDCCC, 7)
    if total > 0 { arrow(196, 54, 196 + max(6, 118 * total / 750), 54, Self.teal, 3) }
    if returning > 0 { arrow(314, 111, 314 - max(6, 118 * returning / 750), 111, 0xA66C44, 3) }
    label("calf_pump_chamber_label", 91, 145, 132)
    label("calf_pump_forward_label", 255, 72, 145)
    label("calf_pump_return_label", 255, 130, 145)
  }
  func exchange(_ model: GalaxySSIHealthAtlasPhysiology) {
    let halfThickness = 13 * model.input(2), extent = 40 * model.input(1)
    let top = 79 - extent / 2, bottom = 79 + extent / 2
    let left = 170 - halfThickness, right = 170 + halfThickness
    rectangle(20, 36, left, 122, 0xDAEEF4)
    rectangle(right, 36, 320, 122, 0xF5DCDF)
    rectangle(left - 2, top, right + 2, bottom, 0xD4E8DB)
    line(left, top, left, bottom, Self.teal, 3)
    line(right, top, right, bottom, Self.rose, 3)
    for i in 0...5 {
      let y = top + (bottom - top) * (Double(i) + 0.5) / 6
      oval(left + 1, y - 3, left + 6, y + 3, Self.teal)
    }
    for i in 0..<4 {
      let x = 227 + Double(i) * 19, y: Double = i.isMultiple(of: 2) ? 55 : 106
      oval(x - 7, y - 4, x + 7, y + 4, 0xC47F87)
      oval(x - 4, y - 1.5, x + 4, y + 1.5, 0xEFB0AE)
    }
    let transfers = model.result == 0 ? 0 : min(6, max(1, Int((1 + model.result).rounded())))
    for i in 0..<transfers {
      let y = top + Double(i + 1) * extent / Double(transfers + 1)
      let from = left - 32, to = right + 27
      arrow(from, y, to, y, Self.blue, 1.25 + 0.14 * model.result)
      oval(from - 8, y - 2.7, from - 2, y + 2.7, Self.blue)
    }
    label("diffusion_air", 74, 145, 116)
    label("diffusion_barrier", 170, 145, 64)
    label("diffusion_blood", 264, 145, 116)
  }
  func cartilage(_ model: GalaxySSIHealthAtlasPhysiology) {
    section(24, strain: 0)
    section(190, strain: model.result)
    let stress = model.input(0) / 64
    if stress > 0 {
      for x in [211.0, 253, 295] {
        let y = 57 + model.result * 1.85
        arrow(x, y - (10 + 25 * stress), x, y, 0xA8613F, 1.1 + stress * 1.7)
      }
    }
    label("compression_unloaded", 87, 146, 126)
    label("compression_loaded", 253, 146, 126)
  }
  private func section(_ x: Double, strain: Double) {
    let top = 62 + strain * 1.85
    rectangle(x, 106, x + 126, 126, 0xE5C9AE, radius: 4)
    for i in 0...8 {
      let y: Double = i.isMultiple(of: 2) ? 116 : 119
      line(x + 9 + Double(i) * 13, y + 1, x + 17 + Double(i) * 13, y - 3, 0xB7987A, 1.6)
    }
    rectangle(x, top, x + 126, 109, 0xADD6C9, radius: 8)
    line(x + 9, top + 2, x + 117, top + 2, Self.teal, 2.4)
    for i in 0...8 {
      let px = x + 13 + Double(i % 5) * 24 + (i > 4 ? 8 : 0)
      let py = top + (109 - top) * (i < 5 ? 0.34 : 0.73)
      oval(px - 3.2, py - 2.3, px + 3.2, py + 2.3, 0x4C8B82)
    }
  }
  func bone(_ model: GalaxySSIHealthAtlasPhysiology) {
    let centerY = 77.0, centerX = 91.0
    let radius = model.input(1) * 1.3, cavity = radius * model.input(2)
    let strength = model.result / model.kind.bounds.upperBound
    var ring = Path(ellipseIn: CGRect(x: centerX - radius, y: centerY - radius, width: 2 * radius, height: 2 * radius))
    ring.addEllipse(in: CGRect(x: centerX - cavity, y: centerY - cavity, width: 2 * cavity, height: 2 * cavity))
    context.fill(ring, with: .color(color(0xEED6AB)), style: FillStyle(eoFill: true))
    var clipped = context
    clipped.clip(to: ring, style: FillStyle(eoFill: true))
    clipped.opacity = Double(Int((125 * strength).rounded())) / 255
    let local = Self(context: clipped, language: language)
    local.rectangle(centerX - radius, centerY - radius, centerX + radius, centerY, 0xAD6554, radius: 0)
    local.rectangle(centerX - radius, centerY, centerX + radius, centerY + radius, 0x51869F, radius: 0)
    context.stroke(ring, with: .color(color(0xA3896C)), lineWidth: 2)
    for dx in -5...5 {
      let x = centerX + Double(dx) * (radius + 9) / 5
      line(x - 2, centerY, x + 2, centerY, 0x726E73, 1.35)
    }
    let axis = 244.0, span = 65 * strength
    let top = centerY - radius, bottom = centerY + radius
    stressLine(axis: axis, centerY: centerY, y: top, offset: -span, fill: 0xEFD2C2, border: 0xA9614C)
    stressLine(axis: axis, centerY: centerY, y: bottom, offset: span, fill: 0xD7E8EF, border: Self.blue)
    line(axis, top - 4, axis, bottom + 4, 0x7C7476, 1.3)
    label("bone_bending_neutral", centerX, 148, 136)
    label("bone_bending_compression", axis - 43, 16, 125)
    label("bone_bending_tension", axis + 44, 148, 94)
  }
  private func stressLine(axis: Double, centerY: Double, y: Double, offset: Double, fill: UInt32, border: UInt32) {
    var path = Path()
    path.move(to: CGPoint(x: axis, y: centerY))
    path.addLine(to: CGPoint(x: axis + offset, y: y))
    path.addLine(to: CGPoint(x: axis, y: y))
    path.closeSubpath()
    context.fill(path, with: .color(color(fill)))
    line(axis, centerY, axis + offset, y, border, 2.1)
  }
  private func rectangle(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double, _ value: UInt32, radius: Double = 10) {
    context.fill(Path(roundedRect: CGRect(x: left, y: top, width: right - left, height: bottom - top), cornerRadius: radius),
      with: .color(color(value)))
  }
  private func oval(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double, _ value: UInt32) {
    context.fill(Path(ellipseIn: CGRect(x: left, y: top, width: right - left, height: bottom - top)), with: .color(color(value)))
  }
  private func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ value: UInt32, _ width: Double) {
    var path = Path()
    path.move(to: CGPoint(x: x1, y: y1)); path.addLine(to: CGPoint(x: x2, y: y2))
    context.stroke(path, with: .color(color(value)), style: StrokeStyle(lineWidth: width, lineCap: .round))
  }
  private func arrow(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ value: UInt32, _ width: Double) {
    line(x1, y1, x2, y2, value, width)
    var tip = Path()
    if y1 == y2 {
      let direction: Double = x2 >= x1 ? 1 : -1
      tip.move(to: CGPoint(x: x2 + 2 * direction, y: y2))
      tip.addLine(to: CGPoint(x: x2 - 6 * direction, y: y2 - 4)); tip.addLine(to: CGPoint(x: x2 - 6 * direction, y: y2 + 4))
    } else {
      let direction: Double = y2 >= y1 ? 1 : -1
      tip.move(to: CGPoint(x: x2, y: y2 + 2 * direction))
      tip.addLine(to: CGPoint(x: x2 - 4, y: y2 - 6 * direction)); tip.addLine(to: CGPoint(x: x2 + 4, y: y2 - 6 * direction))
    }
    tip.closeSubpath()
    context.fill(tip, with: .color(color(value)))
  }
  private func label(_ key: String, _ x: Double, _ baseline: Double, _ available: Double) {
    let value = GalaxySSIHealthAtlasText.get("health_atlas_" + key, language)
    let font = UIFont.systemFont(ofSize: 13)
    let natural = (value as NSString).size(withAttributes: [.font: font]).width
    let fitted = UIFont.systemFont(ofSize: 13 * min(1, available / max(1, natural)))
    context.draw(Text(verbatim: value).font(.system(size: fitted.pointSize)).foregroundColor(.primary),
      at: CGPoint(x: x, y: baseline - fitted.ascender), anchor: .top)
  }
}
