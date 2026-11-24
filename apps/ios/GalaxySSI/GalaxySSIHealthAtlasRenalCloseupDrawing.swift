import SwiftUI

extension GalaxySSIHealthAtlasNephronView {
  func filtrationBarrier(in context: GraphicsContext, time: Double) {
    typealias Ink = GalaxySSIHealthAtlasNephronMotion.Ink
    renalRounded(in: context, 10, 178, 334, 336, 0xFDFBF7)
    renalRounded(in: context, 121, 189, 321, 229, 0xF0CECE)
    renalRounded(in: context, 121, 276, 321, 319, 0xD9EEE9)
    for index in 0...6 {
      let x = 123 + 29 * Double(index)
      renalRounded(in: context, x, 232, x + 23, 243, 0xC57E81)
      renalRounded(in: context, x + 1, 253, x + 24, 272, 0x80B9AD)
      if index < 6 {
        var slit = Path(); slit.move(to: CGPoint(x: x + 24, y: 260)); slit.addLine(to: CGPoint(x: x + 30, y: 260))
        context.stroke(slit, with: .color(Self.color(Ink.fluid.rawValue)), lineWidth: 1.4)
      }
    }
    renalRounded(in: context, 121, 245, 321, 251, 0xDFBB89)
    let cell = 137 + 109 * time
    context.fill(Path(ellipseIn: CGRect(x: cell - 12, y: 199, width: 24, height: 16)), with: .color(Self.color(Ink.blood.rawValue)))
    context.stroke(Path(ellipseIn: CGRect(x: cell - 6, y: 204, width: 12, height: 6)), with: .color(Self.color(0xEE8D94)), lineWidth: 2)
    for index in 0...2 {
      context.fill(Path(ellipseIn: CGRect(x: 270 + Double(index) * 10 - 4, y: 206 + Double(index % 2) * 7 - 4, width: 8, height: 8)), with: .color(Self.color(Ink.secreted.rawValue)))
      let x = 148 + Double(index) * 58
      transfer(in: context, x, 220, x, 297, Ink.crosses.rawValue, time + Double(index) * 0.12)
    }
    label(in: context, key: "blood", center: 64, baseline: 211)
    label(in: context, key: "health_atlas_nephron_barrier_endothelium", center: 64, baseline: 241, color: Self.color(Ink.blood.rawValue))
    label(in: context, key: "health_atlas_nephron_barrier_basement", center: 64, baseline: 254, color: Self.color(Ink.salt.rawValue))
    label(in: context, key: "health_atlas_nephron_barrier_slits", center: 64, baseline: 269, color: Self.color(Ink.fluid.rawValue))
    label(in: context, key: "filtrate", center: 64, baseline: 302)
  }
  func loopCutaway(in context: GraphicsContext, time: Double) {
    typealias Ink = GalaxySSIHealthAtlasNephronMotion.Ink
    renalRounded(in: context, 10, 178, 334, 336, 0xFDFBF7)
    for index in 0...3 {
      context.fill(Path(CGRect(x: 31, y: 204 + Double(index) * 23, width: 282, height: 23)),
        with: .color(Self.color(0xBDA176).opacity(Double(24 + index * 22) / 255)))
    }
    var loop = Path(); loop.move(to: CGPoint(x: 128, y: 208)); loop.addLine(to: CGPoint(x: 128, y: 276))
    loop.addCurve(to: CGPoint(x: 215, y: 276), control1: CGPoint(x: 128, y: 313), control2: CGPoint(x: 215, y: 313))
    loop.addLine(to: CGPoint(x: 215, y: 208))
    context.stroke(loop, with: .color(Self.color(0x84B7AB)), style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
    context.stroke(loop, with: .color(Self.color(0xEAF5F3)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
    for index in 0...1 {
      let y = 230 + Double(index) * 31
      transfer(in: context, 121, y, 74, y, Ink.crosses.rawValue, time + Double(index) * 0.25)
      transfer(in: context, 223, y, 269, y, Ink.salt.rawValue, time + Double(index) * 0.25)
    }
    label(in: context, key: "health_atlas_nephron_loop_descending", center: 87, baseline: 197)
    label(in: context, key: "health_atlas_nephron_loop_ascending", center: 254, baseline: 197)
    label(in: context, key: "water", center: 82, baseline: 321, color: Self.color(Ink.crosses.rawValue))
    label(in: context, key: "salt", center: 263, baseline: 321, color: Self.color(Ink.salt.rawValue))
    label(in: context, key: "health_atlas_nephron_loop_gradient", center: 172, baseline: 273, color: Self.color(Ink.salt.rawValue))
  }
  private func renalRounded(in context: GraphicsContext, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ color: UInt32) {
    context.fill(Path(roundedRect: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1), cornerRadius: 3), with: .color(Self.color(color)))
  }
  private func transfer(in context: GraphicsContext, _ x: Double, _ y: Double, _ endX: Double, _ endY: Double, _ color: UInt32, _ time: Double) {
    let horizontal = y == endY, direction = endX >= x ? 1.0 : -1
    let end = horizontal ? endX - 6 * direction : endY - 6
    var arrow = Path(); arrow.move(to: CGPoint(x: x, y: y)); arrow.addLine(to: CGPoint(x: endX, y: endY))
    arrow.move(to: CGPoint(x: endX, y: endY)); arrow.addLine(to: CGPoint(x: horizontal ? end : endX - 4, y: horizontal ? endY - 4 : end))
    arrow.move(to: CGPoint(x: endX, y: endY)); arrow.addLine(to: CGPoint(x: horizontal ? end : endX + 4, y: horizontal ? endY + 4 : end))
    context.stroke(arrow, with: .color(Self.color(color)), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
    let t = GalaxySSIHealthAtlasSignalMotion.loop(time * 1.27), px = x + (endX - x) * t, py = y + (endY - y) * t
    context.fill(Path(ellipseIn: CGRect(x: px - 4.2, y: py - 4.2, width: 8.4, height: 8.4)), with: .color(.white))
    context.fill(Path(ellipseIn: CGRect(x: px - 3, y: py - 3, width: 6, height: 6)), with: .color(Self.color(color)))
  }
}
