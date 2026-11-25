import SwiftUI
import UIKit

enum GalaxySSIHealthAtlasPleuralSlide {
  static func relativeVelocity(surfaceSpeed: Double, fractionFromReference: Double) -> Double? {
    guard surfaceSpeed.isFinite, (0...24).contains(surfaceSpeed), fractionFromReference.isFinite,
      (0...1).contains(fractionFromReference) else { return nil }
    return surfaceSpeed * fractionFromReference
  }
  static func offset(surfaceSpeed: Double, fractionFromReference: Double, phase: Double) -> Double? {
    guard phase.isFinite, (0...1).contains(phase),
      let velocity = relativeVelocity(surfaceSpeed: surfaceSpeed, fractionFromReference: fractionFromReference) else { return nil }
    return velocity * phase * 5
  }
}

struct GalaxySSIHealthAtlasPleuralSlideView: View {
  let model: GalaxySSIHealthAtlasPhysiology
  let language: String
  var resetToken: Int = 0
  private func t(_ suffix: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_pleural_slide_" + suffix, language) }
  var body: some View {
    GalaxySSIHealthAtlasTeachingPlayback(caption: t("caption"), playLabel: t("play"), pauseLabel: t("pause"),
      duration: model.input(0) > 0 ? 2.3 : 0, modelKey: model.inputs, resetToken: resetToken,
      playIdentifier: "atlas-pleural-slide-play", diagramIdentifier: "atlas-pleural-slide-diagram",
      diagramDescription: String(format: t("diagram"),
        GalaxySSIHealthAtlasPhysiologyText.resultNumber(model.result, kind: model.kind, language: language)),
      heightRatio: 0.5, maximumHeight: 178) { fraction in
        Canvas { context, size in
          let scale = min(size.width / 340, size.height / 163)
          guard scale > 0 else { return }
          var local = context
          local.translateBy(x: (size.width - 340 * scale) / 2, y: (size.height - 163 * scale) / 2)
          local.scaleBy(x: scale, y: scale)
          GalaxySSIHealthAtlasPleuralSlideDrawing(context: local, language: language)
            .draw(speed: model.input(0), thickness: model.input(1), phase: fraction)
        }
      }
  }
}

private struct GalaxySSIHealthAtlasPleuralSlideDrawing {
  let context: GraphicsContext
  let language: String
  private func color(_ value: UInt32) -> Color { GalaxySSIHealthAtlasIllustratedDrawing.color(value) }
  func draw(speed: Double, thickness: Double, phase: Double) {
    let gap = 16 + 24 * thickness, center = 81.0, upper = center - gap / 2, lower = center + gap / 2
    fill(upper - 21, upper, 0xE9C4B8, 8)
    fill(upper - 4, upper + 1, 0xA76A65, 2)
    fill(upper + 1, lower - 1, 0xCFE4EA, 0)
    fill(lower - 1, lower + 4, 0x61948E, 2)
    fill(lower + 4, lower + 24, 0xABD0C6, 8)
    var clipped = context
    clipped.clip(to: Path(CGRect(x: 23, y: upper - 20, width: 286, height: lower - (upper - 20))))
    let tracers = Self(context: clipped, language: language)
    let surfaceOffset = GalaxySSIHealthAtlasPleuralSlide.offset(surfaceSpeed: speed, fractionFromReference: 1, phase: phase)!
    for i in -7...12 {
      let x = 24 + Double(i) * 28 + surfaceOffset
      tracers.line(x, upper - 14, x + 9, upper - 14, 0xA66E63, 2)
    }
    for row in 1...4 {
      let fraction = Double(row) / 5, y = lower - gap * fraction
      let dx = GalaxySSIHealthAtlasPleuralSlide.offset(surfaceSpeed: speed, fractionFromReference: fraction, phase: phase)!
      for i in -3...7 {
        let x = 28 + 44 * Double(i) + dx
        tracers.context.fill(Path(ellipseIn: CGRect(x: x - 2.1, y: y - 2.1, width: 4.2, height: 4.2)), with: .color(color(0x477F89)))
      }
    }
    line(322, upper, 322, lower, 0x477F89, 1.6)
    line(317, upper, 327, upper, 0x477F89, 1.6); line(317, lower, 327, lower, 0x477F89, 1.6)
    label("wall", 15); label("lung", 151)
  }
  private func fill(_ top: Double, _ bottom: Double, _ tint: UInt32, _ radius: Double) {
    context.fill(Path(roundedRect: CGRect(x: 23, y: top, width: 286, height: bottom - top), cornerRadius: radius), with: .color(color(tint)))
  }
  private func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ tint: UInt32, _ width: Double) {
    var path = Path(); path.move(to: CGPoint(x: x1, y: y1)); path.addLine(to: CGPoint(x: x2, y: y2))
    context.stroke(path, with: .color(color(tint)), style: StrokeStyle(lineWidth: width, lineCap: .round))
  }
  private func label(_ suffix: String, _ baseline: Double) {
    let text = GalaxySSIHealthAtlasText.get("health_atlas_pleural_slide_" + suffix, language)
    context.draw(Text(verbatim: text).font(.system(size: 12.5)).foregroundColor(.primary),
      at: CGPoint(x: 166, y: baseline - UIFont.systemFont(ofSize: 12.5).ascender), anchor: .top)
  }
}
