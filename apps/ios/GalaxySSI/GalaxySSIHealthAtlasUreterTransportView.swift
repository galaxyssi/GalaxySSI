import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasUreterFrame: Equatable {
  let arrived: Int
  let inTransit: Double?
  init?(selected: Int, phase: Double) {
    guard (0...6).contains(selected), phase.isFinite, (0...1).contains(phase) else { return nil }
    let position = Double(selected) * phase, whole = Int(floor(position))
    arrived = whole
    inTransit = whole < selected ? position - Double(whole) : nil
  }
}

struct GalaxySSIHealthAtlasUreterTransportView: View {
  let model: GalaxySSIHealthAtlasPhysiology
  let language: String
  var resetToken: Int = 0
  private func t(_ suffix: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_ureter_delivery_" + suffix, language) }
  var body: some View {
    GalaxySSIHealthAtlasTeachingPlayback(caption: t("caption"), playLabel: t("play"), pauseLabel: t("pause"),
      duration: 1.1 * Double(model.inputs[0]), modelKey: model.inputs, resetToken: resetToken,
      playIdentifier: "atlas-ureter-transport-play", diagramIdentifier: "atlas-ureter-transport-diagram",
      diagramDescription: String(format: t("diagram"),
        GalaxySSIHealthAtlasPhysiologyText.resultNumber(model.result, kind: model.kind, language: language)),
      heightRatio: 0.51) { fraction in
        Canvas { context, size in
          let scale = min(size.width / 340, size.height / 162)
          guard scale > 0, let frame = GalaxySSIHealthAtlasUreterFrame(selected: model.inputs[0], phase: fraction) else { return }
          var local = context
          local.translateBy(x: (size.width - 340 * scale) / 2, y: (size.height - 162 * scale) / 2)
          local.scaleBy(x: scale, y: scale)
          GalaxySSIHealthAtlasUreterTransportDrawing(context: local, language: language)
            .draw(frame: frame, packetVolume: model.input(1))
        }
      }
  }
}

private struct GalaxySSIHealthAtlasUreterTransportDrawing {
  let context: GraphicsContext
  let language: String
  private func color(_ value: UInt32) -> Color { GalaxySSIHealthAtlasIllustratedDrawing.color(value) }
  private func center(_ at: Double) -> Double { 82 - 27 * sin(.pi * at) }
  private func tubeRadius(_ at: Double, contraction: Double?) -> Double {
    guard let contraction else { return 10 }
    let fromWave = (at - contraction) / 0.045
    return 10 - 7 * exp(-fromWave * fromWave)
  }
  func draw(frame: GalaxySSIHealthAtlasUreterFrame, packetVolume: Double) {
    let packetRadius = sqrt(packetVolume / 3)
    endpoint(19, 63, 64, 103); endpoint(273, 63, 321, 103)
    let contraction = frame.inTransit.map { $0 - 0.075 }
    var tube = Path()
    for direction in [-1.0, 1.0] {
      for index in 0...52 {
        let step = direction < 0 ? index : 52 - index, at = Double(step) / 52
        let point = CGPoint(x: 59 + at * 222, y: center(at) + direction * tubeRadius(at, contraction: contraction))
        if direction < 0 && index == 0 { tube.move(to: point) } else { tube.addLine(to: point) }
      }
    }
    tube.closeSubpath()
    context.fill(tube, with: .color(color(0xF5D0C7)))
    context.stroke(tube, with: .color(color(0xAC7783)), style: StrokeStyle(lineWidth: 2.7, lineCap: .round))
    if let transit = frame.inTransit {
      let x = 59 + transit * 222, y = center(transit), radius = 3.8 + packetRadius * 2.1
      oval(x - radius * 1.5, y - radius, x + radius * 1.5, y + radius, 0xB57839)
    }
    label(t("pelvis"), 43, 43); label(t("tube"), 170, 26); label(t("bladder"), 297, 43)
    for i in 0..<6 {
      let r = 3.3 + 3 * packetRadius
      let dot = Path(ellipseIn: CGRect(x: 107 + Double(i) * 25 - r, y: 126 - r, width: 2 * r, height: 2 * r))
      if i < frame.arrived { context.fill(dot, with: .color(color(0x508679))) }
      else { context.stroke(dot, with: .color(color(0x9A8785)), lineWidth: 1.4) }
    }
    label(String(format: t("counter"), Int64(frame.arrived), Int64(6)), 170, 151)
  }
  private func endpoint(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double) {
    oval(left, top, right, bottom, 0xAC7783)
    oval(left + 4, top + 4, right - 4, bottom - 4, 0xF5D0C7)
  }
  private func oval(_ left: Double, _ top: Double, _ right: Double, _ bottom: Double, _ tint: UInt32) {
    context.fill(Path(ellipseIn: CGRect(x: left, y: top, width: right - left, height: bottom - top)), with: .color(color(tint)))
  }
  private func t(_ suffix: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_ureter_delivery_" + suffix, language) }
  private func label(_ text: String, _ x: Double, _ baseline: Double) {
    let font = UIFont.systemFont(ofSize: 12)
    context.draw(Text(verbatim: text).font(.system(size: 12)).foregroundColor(.primary),
      at: CGPoint(x: x, y: baseline - font.ascender), anchor: .top)
  }
}
