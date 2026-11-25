import SwiftUI
import UIKit

struct GalaxySSIHealthAtlasBladderFillingView: View {
  let model: GalaxySSIHealthAtlasPhysiology
  let language: String
  var resetToken: Int = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var startedAt = Date()
  @State private var offset = 1.0
  @State private var playing = false
  @State private var measuredWidth: CGFloat = 340
  private var canPlay: Bool { model.input(1) > 0 && !reduceMotion && scenePhase == .active }
  private func phase(at date: Date) -> Double {
    min(1, max(0, offset + (playing ? date.timeIntervalSince(startedAt) / 1.8 : 0)))
  }
  private func pause(at date: Date = Date()) {
    offset = phase(at: date)
    playing = false
  }
  private func reset() { playing = false; offset = 1 }
  private func t(_ suffix: String) -> String {
    GalaxySSIHealthAtlasText.get("health_atlas_bladder_expansion_" + suffix, language)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(t("caption")).font(.subheadline).bold().fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 8)
        Button {
          if playing { pause() }
          else if canPlay {
            if offset >= 1 { offset = 0 }
            startedAt = Date(); playing = true
          }
        } label: {
          Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 44, height: 44)
        }.disabled(!canPlay).opacity(canPlay ? 1 : 0.4)
          .accessibilityIdentifier("atlas-bladder-filling-play")
          .accessibilityLabel(t(playing ? "pause" : "play")).help(t(playing ? "pause" : "play"))
      }
      TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { timeline in
        let fraction = phase(at: timeline.date)
        Canvas { context, size in
          let scale = min(size.width / 340, size.height / 156)
          guard scale > 0 else { return }
          var local = context
          local.translateBy(x: (size.width - 340 * scale) / 2, y: (size.height - 156 * scale) / 2)
          local.scaleBy(x: scale, y: scale)
          GalaxySSIHealthAtlasBladderFillingDrawing(context: local, language: language)
            .draw(start: model.input(0), finish: model.input(0) + model.input(1), phase: fraction)
        }.onChange(of: fraction) { value in if value >= 1, playing { pause(at: timeline.date) } }
      }.frame(height: min(measuredWidth * 0.5, 180))
        .background(GeometryReader { proxy in
          Color.clear.preference(key: GalaxySSIHealthAtlasBladderWidth.self, value: proxy.size.width)
        })
        .onPreferenceChange(GalaxySSIHealthAtlasBladderWidth.self) { width in
          if width.isFinite, width > 0, width != measuredWidth { measuredWidth = width }
        }
        .clipped().accessibilityElement(children: .ignore)
        .accessibilityIdentifier("atlas-bladder-filling-diagram")
        .accessibilityLabel(String(format: t("description"),
          GalaxySSIHealthAtlasPhysiologyText.number(model.input(0), digits: 0, language: language),
          GalaxySSIHealthAtlasPhysiologyText.number(model.input(0) + model.input(1), digits: 0, language: language)))
    }.onChange(of: model) { _ in reset() }
      .onChange(of: resetToken) { _ in reset() }
      .onChange(of: reduceMotion) { value in if value { pause() } }
      .onChange(of: scenePhase) { value in if value != .active { pause() } }
      .onDisappear { pause() }
  }
}

private struct GalaxySSIHealthAtlasBladderWidth: PreferenceKey {
  static let defaultValue: CGFloat = 340
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct GalaxySSIHealthAtlasBladderFillingDrawing {
  let context: GraphicsContext
  let language: String
  private func color(_ value: UInt32) -> Color { GalaxySSIHealthAtlasIllustratedDrawing.color(value) }
  func draw(start: Double, finish: Double, phase: Double) {
    let current = start + (finish - start) * phase
    chamber(x: 83, volume: start); chamber(x: 257, volume: current)
    var arrow = Path()
    arrow.move(to: CGPoint(x: 155, y: 67)); arrow.addLine(to: CGPoint(x: 183, y: 67))
    arrow.move(to: CGPoint(x: 183, y: 67)); arrow.addLine(to: CGPoint(x: 176, y: 62))
    arrow.move(to: CGPoint(x: 183, y: 67)); arrow.addLine(to: CGPoint(x: 176, y: 72))
    context.stroke(arrow, with: .color(color(0xBE8A47)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    label("before", x: 83, volume: start); label("current", x: 257, volume: current)
  }
  private func chamber(x: Double, volume: Double) {
    let relativeRadius = cbrt(volume / 450)
    let halfWidth = 61 * relativeRadius, top = 102 - 92 * relativeRadius
    var path = Path()
    path.move(to: CGPoint(x: x - 5, y: 118)); path.addLine(to: CGPoint(x: x - 6, y: 105))
    path.addCurve(to: CGPoint(x: x - halfWidth, y: 58),
      control1: CGPoint(x: x - halfWidth * 0.47, y: 99), control2: CGPoint(x: x - halfWidth, y: 86))
    path.addCurve(to: CGPoint(x: x + halfWidth, y: 58),
      control1: CGPoint(x: x - halfWidth, y: top - 2), control2: CGPoint(x: x + halfWidth, y: top - 2))
    path.addCurve(to: CGPoint(x: x + 6, y: 105),
      control1: CGPoint(x: x + halfWidth, y: 86), control2: CGPoint(x: x + halfWidth * 0.47, y: 99))
    path.addLine(to: CGPoint(x: x + 5, y: 118)); path.closeSubpath()
    context.fill(path, with: .linearGradient(Gradient(colors: [color(0xFFE8B3), color(0xD5A26C)]),
      startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: 118)))
    context.stroke(path, with: .color(color(0xAC727C)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
    context.stroke(path, with: .color(color(0xF0B6B4)), style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
  }
  private func label(_ suffix: String, x: Double, volume: Double) {
    let title = GalaxySSIHealthAtlasText.get("health_atlas_bladder_expansion_" + suffix, language)
    let value = GalaxySSIHealthAtlasPhysiologyText.number(volume, digits: 0, language: language) + " mL"
    let font = UIFont.systemFont(ofSize: 12)
    for (text, baseline) in [(title, 134.0), (value, 149.0)] {
      context.draw(Text(verbatim: text).font(.system(size: 12)).foregroundColor(.primary),
        at: CGPoint(x: x, y: baseline - font.ascender), anchor: .top)
    }
  }
}
