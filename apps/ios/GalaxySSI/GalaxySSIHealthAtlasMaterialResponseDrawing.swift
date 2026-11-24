import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasMaterialResponseDrawing {
  let context: GraphicsContext
  let language: String
  private static let blue: UInt32 = 0x3A778F, teal: UInt32 = 0x3F7770, rose: UInt32 = 0xB6757F
  private func color(_ value: UInt32) -> Color { GalaxySSIHealthAtlasIllustratedDrawing.color(value) }
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
      tip.move(to: CGPoint(x: x2, y: y2 + 2))
      tip.addLine(to: CGPoint(x: x2 - 4, y: y2 - 6)); tip.addLine(to: CGPoint(x: x2 + 4, y: y2 - 6))
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
