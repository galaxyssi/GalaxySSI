import SwiftUI
import UIKit

enum GalaxySSIHealthAtlasVocalCycle {
  static func relativeOpening(cycles: Double, phase: Double) -> Double? {
    guard cycles.isFinite, (0...7.2).contains(cycles), phase.isFinite, (0...1).contains(phase) else { return nil }
    return 0.5 - 0.5 * cos(2 * .pi * cycles * phase)
  }
}

struct GalaxySSIHealthAtlasVocalCycleView: View {
  let model: GalaxySSIHealthAtlasPhysiology
  let language: String
  var resetToken: Int = 0
  private func t(_ suffix: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_vocal_cycles_" + suffix, language) }
  var body: some View {
    GalaxySSIHealthAtlasTeachingPlayback(caption: t("caption"), playLabel: t("play"), pauseLabel: t("pause"),
      duration: 2.4, modelKey: model.inputs, resetToken: resetToken,
      playIdentifier: "atlas-vocal-cycle-play", diagramIdentifier: "atlas-vocal-cycle-diagram",
      diagramDescription: String(format: t("diagram"),
        GalaxySSIHealthAtlasPhysiologyText.resultNumber(model.result, kind: model.kind, language: language)),
      heightRatio: 0.49, maximumHeight: 175, positionLabel: t("position"), positionIdentifier: "atlas-vocal-cycle-position") { fraction in
        Canvas { context, size in
          let scale = min(size.width / 340, size.height / 152)
          guard scale > 0, let opening = GalaxySSIHealthAtlasVocalCycle.relativeOpening(cycles: model.result, phase: fraction) else { return }
          var local = context
          local.translateBy(x: (size.width - 340 * scale) / 2, y: (size.height - 152 * scale) / 2)
          local.scaleBy(x: scale, y: scale)
          GalaxySSIHealthAtlasVocalCycleDrawing(context: local, language: language)
            .draw(cycles: model.result, phase: fraction, opening: opening, timeMs: model.input(1))
        }
      }
  }
}

private struct GalaxySSIHealthAtlasVocalCycleDrawing {
  let context: GraphicsContext
  let language: String
  private func color(_ value: UInt32) -> Color { GalaxySSIHealthAtlasIllustratedDrawing.color(value) }
  func draw(cycles: Double, phase: Double, opening: Double, timeMs: Double) {
    let x = 76.0, gap = 21 * sqrt(opening)
    oval(20, 20, 132, 132, 0xB4767C); oval(28, 30, 124, 124, 0x46505D)
    for side in [-1.0, 1.0] {
      var path = Path()
      path.move(to: CGPoint(x: x, y: 33))
      path.addCurve(to: CGPoint(x: x + side * gap * 0.62, y: 114),
        control1: CGPoint(x: x + side * gap, y: 55), control2: CGPoint(x: x + side * gap, y: 87))
      path.addCurve(to: CGPoint(x: x, y: 33),
        control1: CGPoint(x: x + side * 44, y: 115), control2: CGPoint(x: x + side * 45, y: 53))
      path.closeSubpath()
      context.fill(path, with: .color(color(0xEBB9AA)))
      context.stroke(path, with: .color(color(0xFFE5D2)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    }
    label(t("top_view"), x, 148, 135)
    let left = 160.0, right = 319.0, top = 46.0, bottom = 112.0
    func graphY(_ value: Double) -> Double { bottom - (bottom - top) * value }
    let chart = Path(roundedRect: CGRect(x: left - 6, y: top - 4, width: right - left + 12, height: bottom - top + 10), cornerRadius: 6)
    context.fill(chart, with: .color(color(0xDBE9EB)))
    for value in [0.0, 0.5, 1.0] { line(left, graphY(value), right, graphY(value), 0x87A3A8, 1) }
    var curve = Path()
    for i in 0...144 {
      let fraction = Double(i) / 144
      guard let relative = GalaxySSIHealthAtlasVocalCycle.relativeOpening(cycles: cycles, phase: fraction) else { continue }
      let point = CGPoint(x: left + fraction * (right - left), y: graphY(relative))
      if i == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
    }
    context.stroke(curve, with: .color(color(0x297C79)), style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
    let cursor = left + phase * (right - left), markerY = graphY(opening)
    line(cursor, top - 4, cursor, bottom + 6, 0xA86F32, 1.3)
    oval(cursor - 3.3, markerY - 3.3, cursor + 3.3, markerY + 3.3, 0xA86F32)
    label(t("opening"), 239, 30, 171)
    label("0", left, 137, 30)
    label(GalaxySSIHealthAtlasPhysiologyText.number(timeMs, digits: 0, language: language) + " ms", 304, 137, 65)
  }
  private func t(_ suffix: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_vocal_cycles_" + suffix, language) }
  private func oval(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double, _ tint: UInt32) {
    context.fill(Path(ellipseIn: CGRect(x: left, y: top, width: right - left, height: bottom - top)), with: .color(color(tint)))
  }
  private func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ tint: UInt32, _ width: Double) {
    var path = Path(); path.move(to: CGPoint(x: x1, y: y1)); path.addLine(to: CGPoint(x: x2, y: y2))
    context.stroke(path, with: .color(color(tint)), style: StrokeStyle(lineWidth: width, lineCap: .round))
  }
  private func label(_ text: String, _ x: Double, _ baseline: Double, _ available: Double) {
    let natural = (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 12)]).width
    let size = 12 * min(1, available / max(1, natural))
    context.draw(Text(verbatim: text).font(.system(size: size)).foregroundColor(.primary),
      at: CGPoint(x: x, y: baseline - UIFont.systemFont(ofSize: size).ascender), anchor: .top)
  }
}
