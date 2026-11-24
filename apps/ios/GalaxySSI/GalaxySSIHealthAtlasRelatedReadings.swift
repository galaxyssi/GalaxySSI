import SwiftUI

@MainActor
struct GalaxySSIHealthAtlasRelatedReadings: View {
  let entryID: String
  let selected: GalaxySSIHealthMetric
  let readings: [GalaxySSIHealthMetric: GalaxySSIHealthReading]?
  let language: String
  let zone: TimeZone
  let select: (GalaxySSIHealthMetric) -> Void
  var body: some View {
    Section(GalaxySSIHealthAtlasText.get("health_atlas_related_metrics", language)) {
      ForEach(GalaxySSIHealthAtlasMetrics.forEntry(entryID)) { metric in
        Button { select(metric) } label: {
          HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
              Text(metric.title(language: language)).foregroundColor(.primary)
              if let reading = readings?[metric] {
                Text(provenance(reading)).font(.caption).foregroundColor(.secondary)
              }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let readings {
              Text(readings[metric].map(GalaxySSIHealthOverviewHistoryView.amount) ??
                GalaxySSIHealthAtlasText.get("health_atlas_no_reading", language))
                .foregroundColor(readings[metric] != nil && selected == metric ? .green : .secondary)
                .frame(maxWidth: .infinity, alignment: .trailing).multilineTextAlignment(.trailing)
                .accessibilityIdentifier("atlas-metric-reading-" + metric.rawValue)
            }
            Image(systemName: selected == metric ? "checkmark" : "chevron.right")
              .font(.caption).accessibilityHidden(true)
          }.fixedSize(horizontal: false, vertical: true).frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("atlas-metric-" + metric.rawValue)
          .accessibilityAddTraits(selected == metric ? .isSelected : [])
      }
    }.accessibilityIdentifier("atlas-related-metrics")
  }
  private func provenance(_ reading: GalaxySSIHealthReading) -> String {
    let date = DateFormatter()
    date.dateStyle = .medium; date.timeStyle = .none
    date.locale = GalaxySSILocalization.interfaceLocale(language: language); date.timeZone = zone
    return String(format: GalaxySSIHealthAtlasText.get("health_atlas_reading_source", language), date.string(from: reading.measuredAt),
      GalaxySSIHealthOverviewMetricRow.origin(reading, language: language))
  }
}
