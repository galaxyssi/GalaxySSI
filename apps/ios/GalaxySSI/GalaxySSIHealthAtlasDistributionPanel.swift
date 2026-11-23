import SwiftUI

struct GalaxySSIHealthAtlasDistributionPanel: View {
  @Binding var model: GalaxySSIHealthAtlasDistribution
  let language: String
  private var locale: Locale { GalaxySSILocalization.interfaceLocale(language: language) }
  private func t(_ key: String) -> String { GalaxySSIHealthAtlasText.get("health_atlas_" + key, language) }
  private func number(_ value: Double) -> String {
    value.formatted(.number.locale(locale).precision(.fractionLength(0...2)))
  }
  private let names = ["central", "peripheral", "eliminated"]
  private var colors: [Color] { [GalaxySSIHealthTheme.accent, .orange, .secondary] }
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(GalaxySSIHealthAtlasPhysiologyText.string("model_synthetic", language: language)).font(.footnote)
      diagram
      Text(model.summary(locale: locale, text: t)).fixedSize(horizontal: false, vertical: true)
      chart
      Text(t("hours_axis")).font(.caption)
      ForEach(0..<3) { index in
        Text(t("distribution_legend_" + names[index])).font(.caption).foregroundColor(colors[index])
      }
      ForEach(0..<4) { index in
        VStack(alignment: .leading, spacing: 4) {
          Text(parameterLabel(index)).fixedSize(horizontal: false, vertical: true)
          Slider(value: binding(index), in: 0...Double(index == 0 ? 192 : 300), step: 1)
            .accessibilityLabel(parameterLabel(index))
            .accessibilityIdentifier("atlas-distribution-parameter-" + String(index))
        }
      }
      Button { model = .standard } label: {
        Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44)
      }.accessibilityLabel(t("reset")).help(t("reset"))
      ForEach(["scope", "formula", "boundary"], id: \.self) { key in
        Text(t("distribution_" + key)).font(.footnote).fixedSize(horizontal: false, vertical: true)
      }
      Link(t("distribution_reference"), destination: GalaxySSIHealthAtlasDistribution.source).frame(minHeight: 44)
    }
  }
  private var diagram: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 8) {
        node(0)
        VStack(spacing: 8) {
          Image(systemName: "arrow.right")
          Image(systemName: "arrow.left")
        }.frame(width: 32).accessibilityHidden(true)
        node(1)
      }
      HStack(spacing: 8) {
        VStack { Image(systemName: "arrow.down").accessibilityHidden(true); node(2) }
        Spacer(minLength: 0)
      }
    }.accessibilityElement(children: .ignore)
      .accessibilityLabel(model.summary(locale: locale, text: t))
      .accessibilityIdentifier("atlas-distribution-diagram")
  }
  private func node(_ index: Int) -> some View {
    VStack(spacing: 6) {
      Text(t("distribution_" + names[index])).font(.subheadline).fixedSize(horizontal: false, vertical: true)
      Text(String(format: t("distribution_percent"), number(model.amounts.values[index])))
        .font(.title3).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        .frame(height: 36).foregroundColor(colors[index])
    }.frame(maxWidth: .infinity)
  }
  private func parameterLabel(_ index: Int) -> String {
    if index == 0 { return String(format: t("distribution_time"), number(model.hours)) }
    let key = ["outward", "return", "loss"][index - 1]
    return String(format: t("distribution_rate"), t("distribution_" + key), number([model.k12, model.k21, model.k10][index - 1]))
  }
  private func binding(_ index: Int) -> Binding<Double> {
    Binding(get: { Double([model.quarterHours, model.outward, model.returning, model.elimination][index]) },
      set: { value in
        guard value.isFinite, value >= 0, value <= Double(index == 0 ? 192 : 300),
          let changed = model.changing(index, to: Int(value.rounded())) else { return }
        model = changed
      })
  }
  private var chart: some View {
    let samples = (0...384).map { model.at(Double($0) / 8)!.values }
    return HStack(spacing: 8) {
      VStack(alignment: .trailing) { Text("100%"); Spacer(); Text("50%"); Spacer(); Text("0%") }
        .font(.caption).frame(height: 180)
      VStack(spacing: 6) {
        GeometryReader { geometry in
          let x = { (hours: Double) in 6 + max(1, geometry.size.width - 12) * CGFloat(hours / 48) }
          let y = { (amount: Double) in 6 + max(1, geometry.size.height - 12) * CGFloat(1 - amount / 100) }
          ZStack {
            Path { path in
              for amount in [0.0, 50, 100] {
                path.move(to: CGPoint(x: 6, y: y(amount))); path.addLine(to: CGPoint(x: geometry.size.width - 6, y: y(amount)))
              }
              path.move(to: CGPoint(x: x(model.hours), y: 6))
              path.addLine(to: CGPoint(x: x(model.hours), y: geometry.size.height - 6))
            }.stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            ForEach(0..<3) { index in
              Path { path in
                for step in samples.indices {
                  let point = CGPoint(x: x(Double(step) / 8), y: y(samples[step][index]))
                  if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
              }.stroke(colors[index], style: StrokeStyle(lineWidth: 2.5, dash: index == 0 ? [] : index == 1 ? [7, 4] : [2, 4]))
              Circle().fill(colors[index]).frame(width: 8, height: 8)
                .position(x: x(model.hours), y: y(model.amounts.values[index]))
            }
          }
        }.frame(height: 180)
        HStack { Text(number(0)); Spacer(); Text(number(24)); Spacer(); Text(number(48)) }.font(.caption)
      }
    }.accessibilityElement(children: .ignore)
      .accessibilityLabel(String(format: t("distribution_chart"), model.summary(locale: locale, text: t)))
      .accessibilityIdentifier("atlas-distribution-chart")
  }
}
