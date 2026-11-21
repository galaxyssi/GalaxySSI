import SwiftUI

@MainActor
struct GalaxySSIHealthOverviewMetricRow: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.locale) private var locale
  @Environment(\.sizeCategory) private var sizeCategory
  let item: GalaxySSIHealthOverview.Metric
  let records: GalaxySSIHealthRecords
  let open: (GalaxySSIHealthReading) -> Void
  let manual: (GalaxySSIHealthMetric) -> Void
  @State private var expanded = false

  private var spacious: Bool { sizeCategory.isAccessibilityCategory || [.extraExtraLarge, .extraExtraExtraLarge].contains(sizeCategory) }
  private var status: GalaxySSIHealthOverviewRange? {
    item.ranges.first(where: \.outside) ?? item.ranges.first(where: { $0.position == .notComparable }) ?? item.ranges.first
  }
  private var icon: String {
    switch item.metric {
    case .bloodPressure, .heartRate, .restingHeartRate: return "heart"
    case .sleepDuration: return "moon.zzz"
    case .steps: return "chart.bar"
    default: return "cross.case"
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        if item.reading == nil { manual(item.metric) } else { expanded.toggle() }
      } label: {
        VStack(alignment: .leading, spacing: 5) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
            Spacer(minLength: 4)
            if !spacious { value }
            Image(systemName: item.reading == nil ? "chevron.right" : (expanded ? "chevron.up" : "chevron.down"))
              .font(.caption).foregroundColor(.secondary)
          }
          if spacious { value.frame(maxWidth: .infinity, alignment: .trailing) }
          if let reading = item.reading {
            if spacious {
              provenance(reading)
              statusText.frame(maxWidth: .infinity, alignment: .trailing)
            } else {
              HStack(alignment: .top, spacing: 6) {
                provenance(reading).frame(maxWidth: .infinity, alignment: .leading)
                statusText.multilineTextAlignment(.trailing)
              }
            }
          } else { Text(t("unrecorded", "Not recorded")).font(.caption).foregroundColor(.secondary) }
        }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("health-overview-" + item.metric.rawValue)
      ForEach(Array(item.ranges.enumerated()), id: \.offset) { _, range in
        Text(sourceTitle(range.source) + ": " + componentTitle(range.component) + range.bounds + " " + range.unit)
          .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      if expanded, let reading = item.reading {
        NavigationLink {
          GalaxySSIHealthOverviewRecordView(records: records, record: reading, edit: open)
        } label: { Text(t("record_detail", "Measurement details")) }
        .frame(minHeight: 44)
        NavigationLink {
          GalaxySSIHealthOverviewHistoryView(records: records, metric: item.metric, open: open)
        } label: { Text(t("metric_history", "Measurement history")) }
        .frame(minHeight: 44)
      }
    }
    .padding(.vertical, 5)
    .onChange(of: item.reading?.id) { _ in expanded = false }
    .onChange(of: item.reading?.revision) { _ in expanded = false }
  }

  private var title: String {
    item.metric == .glucose && item.reading?.conditions == "fasting"
      ? t("fasting_glucose", "Fasting glucose") : item.metric.title(language: language)
  }
  private var value: Text {
    guard let reading = item.reading else { return Text("\u{2014}").foregroundColor(.secondary) }
    let first = item.metric == .bloodPressure ? GalaxySSIHealthCareTarget.Component.systolic : .value
    let notation = reading.reportedNotation.flatMap { $0.isBlank ? nil : $0 }
    let display = item.metric == .steps ? reading.value?.formatted(.number.precision(.fractionLength(0)).locale(locale)) :
      reading.reported?.raw ?? (item.metric != .bloodPressure ? notation : nil) ?? reading.value.map(number)
    var text = Text(display ?? "")
      .foregroundColor(ink(position(first)))
    if item.metric == .bloodPressure {
      text = text + Text("/").foregroundColor(.primary) + Text(reading.diastolic.map(number) ?? "")
        .foregroundColor(ink(position(.diastolic)))
    }
    let unit = item.metric == .steps ? t("steps_unit", "steps") : reading.unit
    return (text.font(.title3.weight(.semibold)) + Text(unit.isEmpty ? "" : " " + unit).font(.caption).foregroundColor(.secondary))
  }
  private func position(_ component: GalaxySSIHealthCareTarget.Component) -> GalaxySSIHealthOverviewRange.Position? {
    item.ranges.first(where: { $0.component == component && $0.outside })?.position ??
      item.ranges.first(where: { $0.component == component })?.position
  }
  private func ink(_ position: GalaxySSIHealthOverviewRange.Position?) -> Color {
    switch position {
    case .within: return .green
    case .below, .above: return .orange
    default: return .primary
    }
  }
  private var statusText: some View {
    let text: String
    if let status {
      let fallback: String
      switch status.position {
      case .below: fallback = "Below"
      case .within: fallback = "Within"
      case .above: fallback = "Above"
      case .notComparable: fallback = "Not comparable"
      }
      text = componentTitle(status.component) + t("position." + status.position.rawValue, fallback) + " \u{00B7} " + sourceTitle(status.source)
    } else { text = t("no_range", "No comparable range") }
    return Text(text).font(.caption.weight(.semibold)).foregroundColor(status.map { ink($0.position) } ?? .secondary)
  }
  private func sourceTitle(_ source: GalaxySSIHealthOverviewRange.Source) -> String {
    let fallback: String
    switch source {
    case .report: fallback = "Report reference"
    case .record: fallback = "Recorded reference"
    case .confirmedTarget: fallback = "Confirmed target"
    }
    return t("range_source." + source.rawValue, fallback)
  }
  private func componentTitle(_ component: GalaxySSIHealthCareTarget.Component) -> String {
    guard item.metric == .bloodPressure else { return "" }
    return GalaxySSILocalization.string("galaxyssi.health." + component.rawValue,
      fallback: component == .diastolic ? "Diastolic" : "Systolic", language: language) + " "
  }
  private func provenance(_ reading: GalaxySSIHealthReading) -> some View {
    Text(reading.measuredAt.formatted(date: .abbreviated, time: .shortened) + " \u{00B7} " + Self.origin(reading, language: language))
      .font(.caption).foregroundColor(.secondary)
  }
  static func origin(_ reading: GalaxySSIHealthReading, language: String) -> String {
    let key: String, fallback: String
    if reading.reportSource != nil { key = "report_source"; fallback = "Report" }
    else if reading.healthKitSource != nil { return "Apple Health" }
    else if reading.tableSource != nil { key = "table.source"; fallback = "Imported table" }
    else if reading.bluetoothReceipt != nil { key = "bluetooth.source"; fallback = "Bluetooth monitor" }
    else { key = "manual_source"; fallback = "Entered manually" }
    return GalaxySSILocalization.string("galaxyssi.health." + key, fallback: fallback, language: language)
  }
  private func number(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).description(withLocale: locale) }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.overview_list." + key, fallback: fallback, language: language)
  }
}

@MainActor
private struct GalaxySSIHealthOverviewHistoryView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let metric: GalaxySSIHealthMetric
  let open: (GalaxySSIHealthReading) -> Void
  @State private var readings: [GalaxySSIHealthReading] = []
  @State private var failed = false
  @State private var limit = 30
  var body: some View {
    List {
      if scene == .active {
        if failed { Text(t("unavailable", "Health records could not be accessed.")); Button(t("retry", "Reload records"), action: reload) }
        ForEach(readings.prefix(limit)) { reading in
          NavigationLink {
            GalaxySSIHealthOverviewRecordView(records: records, record: reading, edit: open)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text((reading.reported?.raw ?? reading.reportedNotation.flatMap { $0.isBlank ? nil : $0 } ?? reading.value?.formatted() ?? "") +
                (reading.diastolic.map { "/" + $0.formatted() } ?? ""))
              Text(reading.unit).font(.caption)
              Text(reading.measuredAt.formatted(date: .abbreviated, time: .shortened)).font(.caption)
              Text(GalaxySSIHealthOverviewMetricRow.origin(reading, language: language)).font(.caption).foregroundColor(.secondary)
            }
          }
        }
        if !failed, readings.isEmpty { Text(t("missing_reading", "Not recorded")) }
        if readings.count > limit { Button(t("more", "Show more")) { limit += 30 } }
      }
    }
    .navigationTitle(metric.title(language: language)).navigationBarTitleDisplayMode(.inline)
    .privacySensitive()
    .onAppear(perform: reload)
    .onDisappear { readings = []; failed = false }
    .onChange(of: scene) { if $0 == .active { reload() } else { readings = []; failed = false } }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
  }
  private func reload() {
    guard scene == .active else { return }
    do { readings = try records.load().current.filter { $0.metric == metric }; failed = false }
    catch { readings = []; failed = true }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health." + key, fallback: fallback, language: language)
  }
}

@MainActor
private struct GalaxySSIHealthOverviewRecordView: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let record: GalaxySSIHealthReading
  let edit: (GalaxySSIHealthReading) -> Void
  @State private var selectedRevision: Int?
  @State private var selected: GalaxySSIHealthReading?
  @State private var revisions: [GalaxySSIHealthReading] = []
  @State private var canEdit = false
  @State private var limit = 30
  var body: some View {
    List {
      if scene == .active {
        if let selected {
          Section {
            Text(selected.reported?.raw ?? selected.reportedNotation.flatMap { $0.isBlank ? nil : $0 } ?? selected.value?.formatted() ?? "")
            if let diastolic = selected.diastolic { Text(t("diastolic", "Diastolic") + ": " + diastolic.formatted()) }
            Text(selected.unit)
            Text(selected.measuredAt.formatted(date: .abbreviated, time: .shortened))
            Text(GalaxySSIHealthOverviewMetricRow.origin(selected, language: language)).foregroundColor(.secondary)
            Text(String(format: t("overview_list.revision", "Revision %lld"), Int64(selected.revision)))
            if let reference = selected.referenceInterval, !reference.isBlank { Text(t("overview_list.recorded_reference", "Recorded reference") + ": " + reference) }
            if !selected.conditions.isBlank { Text(selected.conditions) }
            if !selected.notes.isBlank { Text(selected.notes) }
            Button(t("overview_list.edit", "Edit measurement")) { edit(selected) }.disabled(!canEdit)
          }
          Section(t("history", "Revision history")) {
            ForEach(revisions.prefix(limit), id: \.revision) { revision in
              Button {
                selectedRevision = revision.revision; reload()
              } label: {
                HStack {
                  Text(String(format: t("overview_list.revision", "Revision %lld"), Int64(revision.revision)))
                  if revision.deleted { Image(systemName: "trash") }
                  Spacer()
                  if selected.revision == revision.revision { Image(systemName: "checkmark") }
                }
              }
            }
            if revisions.count > limit { Button(t("more", "Show more")) { limit += 30 } }
          }
        } else { Text(t("unavailable", "Health records could not be accessed.")); Button(t("retry", "Reload records"), action: reload) }
      }
    }
    .navigationTitle(record.metric.title(language: language)).navigationBarTitleDisplayMode(.inline)
    .privacySensitive()
    .onAppear(perform: reload)
    .onDisappear { clear() }
    .onChange(of: scene) { if $0 == .active { reload() } else { clear() } }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
  }
  private func clear() { selected = nil; revisions = []; canEdit = false }
  private func reload() {
    guard scene == .active else { return }
    do {
      let archive = try records.load()
      guard archive.revisions.contains(record), let reading = archive.revisions.first(where: {
        $0.id == record.id && $0.revision == (selectedRevision ?? record.revision)
      }) else { clear(); return }
      selected = reading
      revisions = archive.revisions.filter { $0.id == record.id }.sorted { $0.revision > $1.revision }
      canEdit = archive.draft == nil && archive.current.contains(reading)
    } catch { clear() }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health." + key, fallback: fallback, language: language)
  }
}
