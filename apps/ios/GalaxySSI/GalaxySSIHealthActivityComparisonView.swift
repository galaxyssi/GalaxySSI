import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthActivityComparisonView: View {
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.timeZone) private var timeZone
  @Environment(\.locale) private var locale
  @Environment(\.sizeCategory) private var sizeCategory
  let records: GalaxySSIHealthRecords
  @State private var kind = GalaxySSIHealthActivityKind.steps
  @State private var days = 7
  @State private var first = Date()
  @State private var last = Date()
  @State private var initialized = false
  @State private var comparison: GalaxySSIHealthActivityComparison?
  @State private var task: Task<Void, Never>?
  @State private var request: UUID?
  @State private var failure: Failure?
  @State private var showsData = false
  private enum Failure { case unavailable, permission, dates }
  private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = timeZone; return value }
  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

  var body: some View {
    List {
      if canRead {
        Section {
          kindPicker
          periodPicker
          if days == 0 {
            DatePicker(t("from", "From"), selection: $first, in: ...yesterday, displayedComponents: .date)
            DatePicker(t("through", "Through"), selection: $last, in: ...yesterday, displayedComponents: .date)
          }
        }
        if let failure {
          Text(failureText(failure)).foregroundColor(.secondary)
          if failure == .unavailable { Button(t("retry", "Reload"), action: reload) }
        } else if let comparison {
          summary(comparison)
          Section {
            chart(comparison).frame(height: 180)
            HStack {
              Label(t("current", "Current period"), systemImage: "square.fill").foregroundColor(.green)
              Spacer()
              Label(t("previous", "Previous period"), systemImage: "square.fill").foregroundColor(.blue)
            }.font(.caption)
            Text(t("missing", "Missing dates are unknown, not zero. Percentage change uses only dates recorded in both periods."))
              .font(.caption).foregroundColor(.secondary)
          }
          DisclosureGroup(t("data", "Chart data"), isExpanded: $showsData) {
            ForEach(comparison.pairs.reversed()) { pair in
              VStack(alignment: .leading, spacing: 5) {
                Text(pair.day, style: .date).font(.subheadline)
                HStack(alignment: .top, spacing: 12) {
                  VStack(alignment: .leading) { Text(t("current", "Current period")).font(.caption); Text(amount(pair.current)) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                  VStack(alignment: .trailing) {
                    Text(pair.previousDay, style: .date).font(.caption)
                    Text(amount(pair.previous))
                  }.frame(maxWidth: .infinity, alignment: .trailing)
                }
              }.fixedSize(horizontal: false, vertical: true)
            }
          }
        } else { ProgressView().accessibilityLabel(t("loading", "Loading activity history")) }
      }
    }
    .navigationTitle(t("title", "Activity comparison")).navigationBarTitleDisplayMode(.inline).privacySensitive()
    .onAppear {
      if !initialized {
        initialized = true; last = yesterday
        first = calendar.date(byAdding: .day, value: -6, to: last) ?? last
      }
      reload()
    }
    .onDisappear(perform: clear)
    .onChange(of: kind) { _ in reload() }
    .onChange(of: days) { _ in reload() }
    .onChange(of: first) { _ in if days == 0 { reload() } }
    .onChange(of: last) { _ in if days == 0 { reload() } }
    .onChange(of: timeZone) { _ in reload() }
    .onChange(of: store.profile.identityFingerprint) { _ in clear() }
    .onChange(of: scene) { if $0 == .active { reload() } else { clear() } }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.motionChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
  }

  private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) ?? Date() }
  private var kindPicker: some View {
    Picker(t("kind", "Activity"), selection: $kind) {
      Text(t("steps", "Steps")).tag(GalaxySSIHealthActivityKind.steps)
      Text(t("cycling", "Cycling")).tag(GalaxySSIHealthActivityKind.cycling)
    }.pickerStyle(.segmented)
  }
  @ViewBuilder private var periodPicker: some View {
    if sizeCategory.isAccessibilityCategory { periodOptions.pickerStyle(.menu) }
    else { periodOptions.pickerStyle(.segmented) }
  }
  private var periodOptions: some View {
    Picker(t("period", "Period"), selection: $days) {
      ForEach([7, 30, 90], id: \.self) { Text(String(format: t("days", "%lld days"), Int64($0))).tag($0) }
      Text(t("custom", "Custom")).tag(0)
    }
  }
  private func summary(_ result: GalaxySSIHealthActivityComparison) -> some View {
    Section {
      if let first = result.pairs.first, let last = result.pairs.last {
        Text(first.day, style: .date) + Text(" \u{2014} ") + Text(last.day, style: .date)
        Text(t("previous", "Previous period")).font(.caption).foregroundColor(.secondary)
        Text(first.previousDay, style: .date) + Text(" \u{2014} ") + Text(last.previousDay, style: .date)
      }
      Text(t("total", "Recorded total")).font(.caption).foregroundColor(.secondary)
      Text(amount(result.coverage == 0 ? nil : result.currentTotal)).font(.title3.weight(.semibold))
      Text(String(format: t("coverage", "%lld of %lld days recorded"), Int64(result.coverage), Int64(result.pairs.count)))
        .font(.caption).foregroundColor(.secondary)
      if result.coverage > 0 {
        Text(t("average", "Average per recorded day") + ": " + amount(result.currentTotal / Int64(result.coverage))).font(.subheadline)
      }
      if result.paired.isEmpty { Text(t("no_pairs", "No dates with readings in both periods")) }
      else {
        Text(String(format: t("paired", "%lld paired days"), Int64(result.paired.count))).font(.subheadline)
        Text(amount(result.currentPaired) + " / " + amount(result.previousPaired))
        if let change = result.changePercent { Text(change.formatted(.number.precision(.fractionLength(1)).locale(locale)) + "%") }
      }
    }
  }
  private func chart(_ result: GalaxySSIHealthActivityComparison) -> some View {
    Canvas { context, size in
      let maximum = max(1, result.pairs.flatMap { [$0.current, $0.previous].compactMap { $0 } }.max() ?? 1)
      let slot = size.width / CGFloat(max(1, result.pairs.count))
      for pair in result.pairs {
        for (offset, value) in [pair.current, pair.previous].enumerated() {
          guard let value else { continue }
          let height = size.height * CGFloat(value) / CGFloat(maximum)
          let rect = CGRect(x: CGFloat(pair.id) * slot + CGFloat(offset) * slot * 0.4,
            y: size.height - height, width: slot * 0.35, height: height)
          context.fill(Path(rect), with: .color(offset == 0 ? .green : .blue))
        }
      }
    }.accessibilityHidden(true)
  }
  private func reload() {
    let retainedExpansion = showsData
    clear()
    showsData = retainedExpansion
    guard canRead else { return }
    let now = Date(), local = calendar, selected = kind
    let end = days == 0 ? local.startOfDay(for: last) : yesterday
    let start = days == 0 ? local.startOfDay(for: first) : local.date(byAdding: .day, value: -(days - 1), to: end) ?? end
    do {
      let window = try GalaxySSIHealthActivityComparison(first: start, last: end, now: now, calendar: local, rows: [], kind: selected)
      guard let floor = window.pairs.first?.previousDay else { throw GalaxySSIHealthRecords.Failure.invalid }
      guard try records.load().derivesOverview == true else { failure = .permission; return }
      _ = try records.loadMotion()
      let history = try records.activityHistoryStore()
      let id = UUID(); request = id
      let firstKey = GalaxySSIHealthActivityComparison.dayKey(floor, zone: local.timeZone)
      let lastKey = GalaxySSIHealthActivityComparison.dayKey(end, zone: local.timeZone)
      task = Task { @MainActor in
        do {
          let rows = try await Task.detached(priority: .userInitiated) { try history.read(kind: selected, first: firstKey, last: lastKey) }.value
          guard !Task.isCancelled, request == id, canRead else { return }
          guard try records.load().derivesOverview == true else { failure = .permission; return }
          comparison = try .init(first: start, last: end, now: now, calendar: local, rows: rows, kind: selected)
        } catch {
          guard !Task.isCancelled, request == id, canRead else { return }
          failure = .unavailable
        }
      }
    } catch GalaxySSIHealthRecords.Failure.invalid { failure = .dates }
    catch { failure = .unavailable }
  }
  private func changed(_ notification: Notification) { if notification.object as? String == records.owner { reload() } }
  private func clear() { task?.cancel(); task = nil; request = nil; comparison = nil; failure = nil; showsData = false }
  private func amount(_ value: Int64?) -> String {
    guard let value else { return "\u{2014}" }
    if kind == .steps { return value.formatted(.number.locale(locale)) + " " + t("steps_unit", "steps") }
    return (Double(value) / 60_000).formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + " " + t("minutes", "min")
  }
  private func failureText(_ failure: Failure) -> String {
    switch failure {
    case .dates: return t("invalid_dates", "Choose 1 to 366 completed calendar days.")
    case .permission: return t("permission", "Enable local measurement summaries in Health Privacy to compare activity.")
    case .unavailable: return t("unavailable", "Activity history could not be read. Saved totals are unchanged.")
    }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.activity_comparison." + key, fallback: fallback, language: language)
  }
}
