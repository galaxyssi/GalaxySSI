import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthOverviewMetricRow: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.locale) private var locale
  @Environment(\.sizeCategory) private var sizeCategory
  let item: GalaxySSIHealthOverview.Metric
  let records: GalaxySSIHealthRecords
  let open: (GalaxySSIHealthReading) -> Void
  let manual: (GalaxySSIHealthMetric) -> Void
  var birthDate: Date? = nil
  var progressPermitted = false
  var detailed = false
  var openRecordInsteadOfMetric = false
  var summaryOnly = false
  var showsGuidance = true
  var caption: String? = nil
  @ObservedObject private var motion = GalaxySSIHealthMotionController.shared
  @State private var motionSettings = false
  private var guidance: GalaxySSIHealthOverviewGuidance.Reference? {
    guard showsGuidance else { return nil }
    return GalaxySSIHealthOverviewGuidance.reference(metric: item.metric,
      age: GalaxySSIHealthOverviewGuidance.age(birth: birthDate, on: item.reading?.measuredAt ?? Date(), calendar: .autoupdatingCurrent), language: language)
  }
  private var motionState: GalaxySSIHealthMotion.State? { motion.matches(records) ? motion.state : nil }
  private var phoneSteps: Int? {
    item.metric == .steps ? motionState?.steps?.today(Date(), calendar: .autoupdatingCurrent) : nil
  }
  private var staleSteps: Bool {
    item.metric == .steps && item.reading.map { !Calendar.autoupdatingCurrent.isDateInToday($0.measuredAt) } == true
  }

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
    Group {
      if detailed { detailContent }
      else if item.metric == .steps { stepTile }
      else if summaryOnly { compactContent }
      else if openRecordInsteadOfMetric, let reading = item.reading {
        NavigationLink {
          GalaxySSIHealthOverviewRecordView(records: records, record: reading, edit: open)
        } label: { compactContent }
          .buttonStyle(.plain).accessibilityIdentifier("health-overview-" + item.metric.rawValue)
      }
      else {
        NavigationLink {
          GalaxySSIHealthOverviewMetricDetailView(records: records, metric: item.metric, open: open, manual: manual)
        } label: { compactContent }
          .buttonStyle(.plain)
          .accessibilityIdentifier("health-overview-" + item.metric.rawValue)
      }
    }
    .sheet(isPresented: $motionSettings) { NavigationView { GalaxySSIHealthMotionView(records: records) }.navigationViewStyle(.stack) }
  }

  private var compactContent: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
        Spacer(minLength: 4)
        if !spacious { value }
        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
      }
      if spacious { value.frame(maxWidth: .infinity, alignment: .trailing) }
      if spacious { comparisonBasis; if status != nil { statusText } }
      else {
        HStack(alignment: .top, spacing: 6) {
          comparisonBasis.frame(maxWidth: .infinity, alignment: .leading)
          if status != nil { statusText.multilineTextAlignment(.trailing) }
        }
      }
      if let caption, !caption.isEmpty { Text(caption).font(.caption2).foregroundColor(.secondary) }
    }.frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
      .padding(.vertical, 8).contentShape(Rectangle())
  }

  @ViewBuilder private var comparisonBasis: some View {
    if let status {
      Text(item.ranges.filter { $0.source == status.source }.map {
        sourceTitle($0.source) + ": " + componentTitle($0.component) + $0.bounds + " " + $0.unit
      }.joined(separator: "\n")).font(.caption).foregroundColor(.secondary)
    } else if let guidance {
      Text(guidance.lines.joined(separator: "\n")).font(.caption).foregroundColor(.secondary)
    } else {
      Text(item.reading == nil ? t("unrecorded", "Not recorded") : t("no_range", "No comparable range"))
        .font(.caption).foregroundColor(.secondary)
    }
  }

  private var stepTile: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button { motionSettings = true } label: {
        VStack(alignment: .leading, spacing: 5) {
          Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundColor(.primary)
          value
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
      }.buttonStyle(.plain)
      Button { motionSettings = true } label: {
        Text(motionState?.goal.map { String(format: GalaxySSIHealthMotionView.text("goal_value", "Daily goal: %lld steps", language), Int64($0)) } ??
          GalaxySSIHealthMotionView.text("set_goal", "Set a daily step goal", language))
          .font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
      }.buttonStyle(.plain)
      if let ratio = stepProgress { Text(ratio.formatted(.percent)).font(.caption).foregroundColor(.secondary) }
    }.accessibilityIdentifier("health-overview-steps")
      .accessibilityHint(GalaxySSIHealthMotionView.status(motion.matches(records) ? motion.stepStatus : .failed, language: language))
  }

  private var detailContent: some View {
    VStack(alignment: .leading, spacing: 8) {
      value
      if let reading = item.reading {
        provenance(reading)
        if !reading.conditions.isBlank { Text(reading.conditions).font(.caption).foregroundColor(.secondary) }
        if let side = reading.measurementSide {
          Text(GalaxySSILocalization.string("galaxyssi.health.measurement_comparison.side_" + side,
            fallback: side == "left" ? "Left" : side == "right" ? "Right" : "Not specified", language: language))
            .font(.caption).foregroundColor(.secondary)
        }
      } else { Text(t("unrecorded", "Not recorded")).foregroundColor(.secondary) }
      ForEach(Array(item.ranges.enumerated()), id: \.offset) { _, range in
        Text(sourceTitle(range.source) + ": " + componentTitle(range.component) + range.bounds + " " + range.unit)
          .font(.subheadline)
        Text(componentTitle(range.component) + t("position." + range.position.rawValue, range.position.rawValue))
          .font(.caption).foregroundColor(ink(range.position))
      }
      if let guidance {
        ForEach(guidance.lines, id: \.self) { Text($0).font(.caption).foregroundColor(.secondary) }
        Text(guidance.detail).font(.caption).foregroundColor(.secondary)
        Link(guidance.source, destination: guidance.url).font(.caption).frame(minHeight: 44)
      }
      if item.reading == nil {
        Button(t("manual", "Record measurement")) { manual(item.metric) }.frame(minHeight: 44)
      }
    }
    .padding(.vertical, 5)
  }

  private var title: String {
    item.metric == .steps ? t("steps_today", "Steps today") : item.metric == .glucose && item.reading?.conditions == "fasting"
      ? t("fasting_glucose", "Fasting glucose") : item.metric.title(language: language)
  }
  private var value: Text {
    if let count = phoneSteps {
      return Text(count.formatted(.number.locale(locale))).font(.title3.weight(.semibold)).foregroundColor(.primary) +
        Text(" " + t("steps_unit", "steps")).font(.caption).foregroundColor(.secondary)
    }
    if staleSteps { return Text("\u{2014}").foregroundColor(.secondary) }
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
  private var stepProgress: Double? {
    guard let goal = motionState?.goal, !staleSteps || phoneSteps != nil,
          (try? records.load().derivesOverview) == true else { return nil }
    let count = phoneSteps ?? item.reading?.value.flatMap { Int(NSDecimalNumber(decimal: $0).stringValue) }
    return GalaxySSIHealthMotion.progress(goal: goal, steps: count,
      fresh: phoneSteps != nil || item.freshness == .recent, permitted: progressPermitted)
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
struct GalaxySSIHealthOverviewMetricDetailView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  let records: GalaxySSIHealthRecords
  let metric: GalaxySSIHealthMetric
  let open: (GalaxySSIHealthReading) -> Void
  let manual: (GalaxySSIHealthMetric) -> Void
  @State private var item: GalaxySSIHealthOverview.Metric?
  @State private var recent: [GalaxySSIHealthReading] = []
  @State private var birth: Date?
  @State private var concern: UUID?
  @State private var discussion: UUID?
  @State private var failed = false
  @State private var changed = false
  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }
  private var localCalendar: Calendar { var value = calendar; value.timeZone = timeZone; return value }
  var body: some View {
    List {
      if canRead {
        if let item {
          Section {
            GalaxySSIHealthOverviewMetricRow(item: item, records: records, open: open, manual: manual,
              birthDate: birth, detailed: true)
          }
          if !recent.isEmpty {
            Section(t("recent_records", "Recent records")) {
              ForEach(recent.prefix(3)) { reading in
                NavigationLink {
                  GalaxySSIHealthOverviewRecordView(records: records, record: reading, edit: open)
                } label: {
                  HStack(alignment: .top) {
                    Text(reading.measuredAt, style: .date).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(GalaxySSIHealthOverviewHistoryView.amount(reading)).font(.subheadline.weight(.semibold))
                  }.frame(minHeight: 44)
                }
              }
              NavigationLink {
                GalaxySSIHealthOverviewHistoryView(records: records, metric: metric, open: open)
              } label: { Text(t("metric_history", "Measurement history")) }
            }
          }
          if item.outsideRange {
            Text(t("compare_note", "Compare with earlier measurements taken under similar conditions."))
              .font(.caption).foregroundColor(.secondary)
          }
          if concern != nil {
            Button(t("discuss_metric", "Discuss in a separate health chat"), action: openDiscussion).frame(minHeight: 44)
          }
          if changed { Text(health("stale", "The health data changed. Reload and try again.")).foregroundColor(.secondary) }
        } else if failed {
          Text(health("unavailable", "Health records could not be accessed."))
          Button(health("retry", "Reload records"), action: reload)
        }
      }
    }
    .navigationTitle(metric == .glucose && item?.reading?.conditions == "fasting"
      ? t("fasting_glucose", "Fasting glucose") : metric.title(language: language))
    .galaxySSIHealthTheme().privacySensitive()
    .background(NavigationLink(isActive: Binding(get: { discussion != nil }, set: { if !$0 { discussion = nil } })) {
      if let discussion { GalaxySSIHealthCareDiscussionView(records: records, concernID: discussion, metric: metric) }
    } label: { EmptyView() }.hidden())
    .onAppear(perform: reload)
    // Pushing a child must not remove its source NavigationLink. Privacy observers clear inactive data.
    .onChange(of: scene) { if $0 == .active { reload() } else { clear() } }
    .onChange(of: timeZone) { _ in reload() }
    .onChange(of: store.profile.identityFingerprint) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { changedRecords($0) }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.profileInputsChanged)) { changedRecords($0) }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
  }
  private func reload() {
    guard canRead else { clear(); return }
    do {
      let archive = try records.load()
      let now = Date()
      recent = GalaxySSIHealthOverview.recent(archive.current, metric: metric, now: now)
      let ranges = (try? records.overviewRanges(expected: archive, now: now)) ?? [:]
      birth = try? records.overviewBirthDate(expected: archive)
      let cutoff = localCalendar.date(byAdding: .day, value: -6, to: localCalendar.startOfDay(for: now)) ?? now
      item = .init(metric: metric, reading: recent.first,
        freshness: recent.first.map { $0.measuredAt >= cutoff ? .recent : .stale } ?? .missing,
        ranges: ranges[metric] ?? [])
      concern = nil
      if let reading = recent.first { concern = try? records.overviewDiscussionConcern(reading: reading, now: now) }
      failed = false
    } catch { clear(); failed = true }
  }
  private func openDiscussion() {
    guard canRead, let reading = item?.reading, let expected = concern,
          (try? records.overviewDiscussionConcern(reading: reading)) == expected else {
      reload(); changed = true; return
    }
    discussion = expected
  }
  private func changedRecords(_ notification: Notification) {
    if notification.object as? String == records.owner {
      let prior = discussion
      reload()
      if prior != concern { discussion = nil }
    }
  }
  private func clear() { item = nil; recent = []; birth = nil; concern = nil; discussion = nil; failed = false; changed = false }
  private func t(_ key: String, _ fallback: String) -> String { health("overview_list." + key, fallback) }
  private func health(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health." + key, fallback: fallback, language: language)
  }
}

@MainActor
struct GalaxySSIHealthOverviewHistoryView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  var metric: GalaxySSIHealthMetric? = nil
  let open: (GalaxySSIHealthReading) -> Void
  @State private var readings: [GalaxySSIHealthReading] = []
  @State private var failed = false
  @State private var limit = 30
  private var localCalendar: Calendar { var value = calendar; value.timeZone = timeZone; return value }
  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }
  var body: some View {
    List {
      if canRead {
        if failed { Text(t("unavailable", "Health records could not be accessed.")); Button(t("retry", "Reload records"), action: reload) }
        ForEach(GalaxySSIHealthOverview.days(Array(readings.prefix(limit)), calendar: localCalendar)) { day in
        Section {
        ForEach(day.readings) { reading in
          NavigationLink {
            GalaxySSIHealthOverviewRecordView(records: records, record: reading, edit: open)
          } label: {
            HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
              Text(reading.metric.title(language: language)).font(.subheadline.weight(.semibold))
              Text(reading.measuredAt, style: .time).font(.caption).foregroundColor(.secondary)
              Text(GalaxySSIHealthOverviewMetricRow.origin(reading, language: language)).font(.caption).foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            Text(Self.amount(reading)).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
            }.frame(minHeight: 52)
          }
        }
        } header: { Text(day.date, style: .date) }
        }
        if !failed, readings.isEmpty { Text(t("missing_reading", "Not recorded")) }
        if readings.count > limit { Button(t("more", "Show more")) { limit += 30 } }
      }
    }
    .navigationTitle(metric?.title(language: language) ?? t("overview_list.all_records", "All records"))
    .galaxySSIHealthTheme()
    .privacySensitive()
    .onAppear(perform: reload)
    .onChange(of: scene) { if $0 == .active { reload() } else { readings = []; failed = false } }
    .onChange(of: timeZone) { _ in reload() }
    .onChange(of: store.profile.identityFingerprint) { _ in readings = [] }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in readings = [] }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
  }
  private func reload() {
    guard canRead else { readings = []; return }
    do { readings = GalaxySSIHealthOverview.recent(try records.load().current, metric: metric, now: Date()); failed = false }
    catch { readings = []; failed = true }
  }
  static func amount(_ reading: GalaxySSIHealthReading) -> String {
    (reading.reported?.raw ?? reading.reportedNotation.flatMap { $0.isBlank ? nil : $0 } ?? reading.value?.formatted() ?? "") +
      (reading.diastolic.map { "/" + $0.formatted() } ?? "") + (reading.unit.isEmpty ? "" : " " + reading.unit)
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health." + key, fallback: fallback, language: language)
  }
}

@MainActor
struct GalaxySSIHealthOverviewRecordView: View {
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
            Group {
              if let reference = selected.referenceInterval, !reference.isBlank { Text(t("overview_list.recorded_reference", "Recorded reference") + ": " + reference) }
              if !selected.conditions.isBlank { Text(selected.conditions) }
              if let side = selected.measurementSide {
                Text(GalaxySSILocalization.string("galaxyssi.health.measurement_comparison.side_" + side,
                  fallback: side == "left" ? "Left" : side == "right" ? "Right" : "Not specified", language: language))
              }
              if !selected.notes.isBlank { Text(selected.notes) }
            }
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
    .navigationTitle(record.metric.title(language: language)).galaxySSIHealthTheme()
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
