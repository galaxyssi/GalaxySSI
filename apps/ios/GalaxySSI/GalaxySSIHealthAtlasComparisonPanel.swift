import SwiftUI

struct GalaxySSIHealthAtlasModelTabs: View {
  let options: [String]
  @Binding var selected: Int
  let identifier: String
  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      ForEach(Array(options.enumerated()), id: \.offset) { index, title in
        Button { selected = index } label: {
          Text(title).font(.footnote).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4).padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 44)
            .background(selected == index ? GalaxySSIHealthTheme.accent.opacity(0.08) : Color.clear)
            .overlay(alignment: .bottom) {
              Rectangle().fill(selected == index ? GalaxySSIHealthTheme.accent : .clear).frame(height: 2)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected == index ? .isSelected : [])
          .accessibilityIdentifier(identifier + "-" + String(index))
      }
    }.accessibilityIdentifier(identifier)
  }
}

struct GalaxySSIHealthAtlasComparisonPanel: View {
  @Binding var model: GalaxySSIHealthAtlasModelComparison
  let language: String
  @ScaledMetric(relativeTo: .caption) private var axisFontSize: CGFloat = 12
  @Environment(\.colorScheme) private var colorScheme
  private func chartColor(_ light: UInt32, _ dark: UInt32) -> Color {
    let rgb = colorScheme == .dark ? dark : light
    return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
  }
  private var comparisonColor: Color { chartColor(0x8D4D00, 0xFFBD73) }
  private var chartNeutral: Color { chartColor(0x8E8E93, 0xA5ABB6) }
  private var chartSeparator: Color { chartColor(0xE5E5EA, 0x343841) }
  private var locale: Locale { GalaxySSILocalization.interfaceLocale(language: language) }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
  private var time: String { GalaxySSIHealthAtlasComparisonText.time(model, locale: locale, text: t) }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(t("compare_scope")).font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
      GalaxySSIHealthAtlasModelTabs(options: GalaxySSIHealthAtlasModelComparison.Scenario.allCases.map { t($0.label) },
        selected: Binding(get: { model.scenario.rawValue }, set: { raw in
          if let scenario = GalaxySSIHealthAtlasModelComparison.Scenario(rawValue: raw),
             let next = GalaxySSIHealthAtlasModelComparison(scenario: scenario, quarterHours: model.quarterHours) { model = next }
        }), identifier: "atlas-comparison-case")
      Text(GalaxySSIHealthAtlasComparisonText.rates(model, locale: locale, text: t)).font(.footnote).foregroundColor(.secondary)
        .accessibilityIdentifier("atlas-comparison-rates")
      chart
      Text(t("compare_legend")).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
      HStack {
        Text(time).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("atlas-comparison-time")
        Spacer()
        Button { model = .standard } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
          .accessibilityLabel(t("reset")).help(t("reset")).accessibilityIdentifier("atlas-comparison-reset")
      }
      Slider(value: Binding(get: { Double(model.quarterHours) }, set: { value in
        guard value.isFinite, (0...192).contains(value),
          let next = GalaxySSIHealthAtlasModelComparison(scenario: model.scenario, quarterHours: Int(value.rounded())) else { return }
        model = next
      }), in: 0...192, step: 1).accessibilityLabel(time).accessibilityIdentifier("atlas-comparison-elapsed")
      Text(GalaxySSIHealthAtlasComparisonText.summary(model.point, locale: locale, text: t))
        .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("atlas-comparison-result")
      Text(GalaxySSIHealthAtlasComparisonText.range(model.point, locale: locale, text: t)).font(.footnote)
        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("atlas-comparison-range")
      Text(t("compare_evidence")).font(.headline).padding(.top, 8)
      Text(t("compare_limit")).font(.footnote).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("atlas-comparison-evidence")
      Link(t("distribution_reference"), destination: GalaxySSIHealthAtlasDistribution.source)
        .frame(minHeight: 44).accessibilityIdentifier("atlas-source-comparison-equations")
      Link(t("compare_reference"), destination: GalaxySSIHealthAtlasComparisonText.validationSource)
        .frame(minHeight: 44).accessibilityIdentifier("atlas-source-comparison-validation")
    }
  }
  private var chart: some View {
    let samples = model.samples, point = model.point, hours = model.hours
    let font = Font.system(size: axisFontSize)
    return Canvas { context, size in
      let drawing = context
      func width(_ text: String) -> CGFloat {
        drawing.resolve(Text(text).font(font)).measure(in: CGSize(width: 999, height: 999)).width
      }
      let left = width("100%") + 12, right = size.width - width("48") / 2 - 4
      let top = axisFontSize, bottom = size.height - axisFontSize * 2
      guard right > left, bottom > top else { return }
      func x(_ value: Double) -> CGFloat { left + (right - left) * CGFloat(value / 48) }
      func y(_ value: Double) -> CGFloat { bottom - (bottom - top) * CGFloat(value / 100) }
      var area = Path()
      for index in samples.indices {
        let position = CGPoint(x: x(Double(index) / 4), y: y(samples[index].high))
        if index == 0 { area.move(to: position) } else { area.addLine(to: position) }
      }
      for index in samples.indices.reversed() { area.addLine(to: CGPoint(x: x(Double(index) / 4), y: y(samples[index].low))) }
      area.closeSubpath(); drawing.fill(area, with: .color(GalaxySSIHealthTheme.accent.opacity(42.0 / 255)))
      var guides = Path()
      for tick in [0.0, 50, 100] {
        guides.move(to: CGPoint(x: left, y: y(tick))); guides.addLine(to: CGPoint(x: right, y: y(tick)))
        drawing.draw(Text(String(Int(tick)) + "%").font(font).foregroundColor(chartNeutral),
          at: CGPoint(x: left - 6, y: y(tick)), anchor: .trailing)
      }
      drawing.stroke(guides, with: .color(chartSeparator), lineWidth: 1)
      for tick in [0.0, 24, 48] {
        drawing.draw(Text(String(Int(tick))).font(font).foregroundColor(chartNeutral),
          at: CGPoint(x: x(tick), y: bottom + axisFontSize * 1.4))
      }
      var marker = Path(); marker.move(to: CGPoint(x: x(hours), y: top)); marker.addLine(to: CGPoint(x: x(hours), y: bottom))
      drawing.stroke(marker, with: .color(chartNeutral), lineWidth: 1)
      func series(_ color: Color, dashed: Bool, value: (GalaxySSIHealthAtlasModelComparison.Point) -> Double) {
        var curve = Path()
        for index in samples.indices {
          let position = CGPoint(x: x(Double(index) / 4), y: y(value(samples[index])))
          if index == 0 { curve.move(to: position) } else { curve.addLine(to: position) }
        }
        drawing.stroke(curve, with: .color(color), style: StrokeStyle(lineWidth: 2.5, dash: dashed ? [6, 4] : []))
        drawing.fill(Path(ellipseIn: CGRect(x: x(hours) - 3.5, y: y(value(point)) - 3.5, width: 7, height: 7)), with: .color(color))
      }
      series(comparisonColor, dashed: false) { $0.two.central }
      series(GalaxySSIHealthTheme.accent, dashed: true) { $0.one }
    }.frame(height: 144 + 3 * axisFontSize).accessibilityHidden(true).accessibilityIdentifier("atlas-comparison-chart")
  }
}
