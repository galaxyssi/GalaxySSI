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
  @SceneStorage private var kindID: Int
  @SceneStorage private var days: Int
  @SceneStorage private var firstStamp: Double
  @SceneStorage private var lastStamp: Double
  @SceneStorage private var initialized: Bool
  @SceneStorage private var selectedDay: String
  @State private var comparison: GalaxySSIHealthActivityComparison?
  @State private var loaded: GalaxySSIHealthActivityComparison?
  @State private var liveMotion: GalaxySSIHealthMotion.State?
  @State private var liveTask: Task<Void, Never>?
  @State private var visible = false
  @State private var task: Task<Void, Never>?
  @State private var historyTask: Task<[GalaxySSIHealthActivityDay], Error>?
  @State private var request: UUID?
  @State private var failure: Failure?
  @State private var trackingTouch = false
  init(records: GalaxySSIHealthRecords) {
    self.records = records
    let prefix = "galaxyssi.health.activity." + records.owner + "."
    _kindID = SceneStorage(wrappedValue: 0, prefix + "kind")
    _days = SceneStorage(wrappedValue: 7, prefix + "days")
    _firstStamp = SceneStorage(wrappedValue: Date().timeIntervalSince1970, prefix + "first")
    _lastStamp = SceneStorage(wrappedValue: Date().timeIntervalSince1970, prefix + "last")
    _initialized = SceneStorage(wrappedValue: false, prefix + "initialized")
    _selectedDay = SceneStorage(wrappedValue: "", prefix + "selected")
  }
  private var kind: GalaxySSIHealthActivityKind { GalaxySSIHealthActivityKind(rawValue: kindID) ?? .steps }
  private var first: Date { get { Date(timeIntervalSince1970: firstStamp) } nonmutating set { firstStamp = newValue.timeIntervalSince1970 } }
  private var last: Date { get { Date(timeIntervalSince1970: lastStamp) } nonmutating set { lastStamp = newValue.timeIntervalSince1970 } }
  private enum Failure { case unavailable, permission, dates }
  private var calendar: Calendar { var value = Calendar(identifier: .gregorian); value.timeZone = timeZone; return value }
  private var canRead: Bool {
    visible && scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

  var body: some View {
    List {
      if canRead {
        Section {
          kindPicker
          periodPicker
          if days == 0 {
            DatePicker(t("from", "From"), selection: Binding(get: { first }, set: { first = $0 }), in: ...today, displayedComponents: .date)
            DatePicker(t("through", "Through"), selection: Binding(get: { last }, set: { last = $0 }), in: ...today, displayedComponents: .date)
          }
        }
        if let failure {
          Text(failureText(failure)).foregroundColor(.secondary)
          if failure == .unavailable { Button(t("retry", "Reload"), action: reload) }
        } else if let comparison {
          summary(comparison)
          Section {
            GalaxySSIHealthActivityChart(result: comparison, kind: kind, locale: locale, zone: timeZone,
              language: language, selectedDay: $selectedDay, onTracking: { active in
                trackingTouch = active
                if !active { renderLive() }
              })
              .frame(height: max(220, UIFontMetrics(forTextStyle: .body).scaledValue(for: 220)))
          }
        } else { ProgressView().accessibilityLabel(t("loading", "Loading activity history")) }
      }
    }
    .navigationTitle(t("title", "Activity comparison")).galaxySSIHealthTheme().privacySensitive()
    .onAppear {
      visible = true
      if !initialized {
        initialized = true; last = today
        first = calendar.date(byAdding: .day, value: -6, to: last) ?? last
      }
      reload()
    }
    .onDisappear { visible = false; clear() }
    .onChange(of: kindID) { _ in selectedDay = ""; reload() }
    .onChange(of: days) { _ in selectedDay = ""; reload() }
    .onChange(of: firstStamp) { _ in if days == 0 { selectedDay = ""; reload() } }
    .onChange(of: lastStamp) { _ in if days == 0 { selectedDay = ""; reload() } }
    .onChange(of: timeZone) { _ in selectedDay = ""; reload() }
    .onChange(of: store.profile.identityFingerprint) { _ in selectedDay = ""; clear() }
    .onChange(of: scene) { if $0 == .active { reload() } else { clear() } }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.motionChanged)) { motionChanged($0) }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
  }

  private var today: Date { calendar.startOfDay(for: Date()) }
  private var kindPicker: some View {
    Picker(t("kind", "Activity"), selection: $kindID) {
      Text(t("steps", "Steps")).tag(GalaxySSIHealthActivityKind.steps.rawValue)
      Text(t("cycling", "Cycling")).tag(GalaxySSIHealthActivityKind.cycling.rawValue)
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
      Text(t("total", "Recorded total")).font(.caption).foregroundColor(.secondary)
      Text(amount(result.coverage == 0 ? nil : result.currentTotal)).font(.title3.weight(.semibold))
        .accessibilityIdentifier("health-activity-total")
      Text(String(format: t("coverage", "%lld of %lld days recorded"), Int64(result.coverage), Int64(result.pairs.count)))
        .font(.caption).foregroundColor(.secondary)
      if result.coverage > 0 {
        Text(t("average", "Average per recorded day") + ": " + amount(result.currentTotal / Int64(result.coverage))).font(.subheadline)
      }
    }
  }
  private func reload() {
    clear()
    guard canRead else { return }
    let now = Date(), local = calendar, selected = kind
    do {
      let preset = days == 0 ? nil : try GalaxySSIHealthActivityComparison.trailing(days: days, now: now, calendar: local)
      let start = preset?.lowerBound ?? local.startOfDay(for: first)
      let end = preset?.upperBound ?? local.startOfDay(for: last)
      let window = try GalaxySSIHealthActivityComparison(first: start, last: end, now: now, calendar: local, rows: [], kind: selected)
      guard let floor = window.pairs.first?.day else { throw GalaxySSIHealthRecords.Failure.invalid }
      let archive = try records.load(), consent = archive.privacyEvents?.last?.id
      guard archive.derivesOverview == true else { failure = .permission; return }
      liveMotion = try records.loadMotion()
      let history = try records.activityHistoryStore()
      let id = UUID(); request = id
      let firstKey = GalaxySSIHealthActivityComparison.dayKey(floor, zone: local.timeZone)
      let lastKey = GalaxySSIHealthActivityComparison.dayKey(end, zone: local.timeZone)
      let worker = Task.detached(priority: .userInitiated) {
        try Task.checkCancellation()
        let rows = try history.read(kind: selected, first: firstKey, last: lastKey)
        try Task.checkCancellation()
        return rows
      }
      historyTask = worker
      task = Task { @MainActor in
        do {
          let rows = try await worker.value
          guard !Task.isCancelled, request == id, canRead else { return }
          let fresh = try records.load()
          guard fresh.derivesOverview == true, fresh.privacyEvents?.last?.id == consent else { failure = .permission; return }
          loaded = try .init(first: start, last: end, now: now, calendar: local, rows: rows, kind: selected)
          renderLive()
        } catch {
          guard !Task.isCancelled, request == id, canRead else { return }
          failure = .unavailable
        }
      }
    } catch GalaxySSIHealthRecords.Failure.invalid { failure = .dates }
    catch { failure = .unavailable }
  }
  private func motionChanged(_ notification: Notification) {
    guard notification.object as? String == records.owner, canRead else { return }
    guard let state = notification.userInfo?["state"] as? GalaxySSIHealthMotion.State else { reload(); return }
    liveMotion = state
    guard loaded != nil, liveTask == nil else { return }
    liveTask = Task { @MainActor in
      do { try await Task.sleep(nanoseconds: 750_000_000) } catch { return }
      guard !Task.isCancelled, canRead else { return }
      liveTask = nil; renderLive()
    }
  }
  private func renderLive() {
    guard canRead, let loaded, !trackingTouch else { return }
    let now = Date()
    // A day rollover changes the query window, not just the display-only overlay.
    if days > 0, loaded.pairs.last?.day != calendar.startOfDay(for: now) { reload(); return }
    let row = GalaxySSIHealthActivityComparison.today(liveMotion, kind: kind, now: now, calendar: calendar)
    if let value = try? loaded.withDay(row, kind: kind, zone: timeZone), value != comparison { comparison = value }
  }
  private func changed(_ notification: Notification) { if notification.object as? String == records.owner { reload() } }
  private func clear() {
    task?.cancel(); task = nil; historyTask?.cancel(); historyTask = nil
    liveTask?.cancel(); liveTask = nil; request = nil
    comparison = nil; loaded = nil; liveMotion = nil; failure = nil; trackingTouch = false
  }
  private func amount(_ value: Int64?) -> String {
    guard let value else { return "\u{2014}" }
    if kind == .steps { return value.formatted(.number.locale(locale)) + " " + t("steps_unit", "steps") }
    return (Double(value) / 60_000).formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + " " + t("minutes", "min")
  }
  private func failureText(_ failure: Failure) -> String {
    switch failure {
    case .dates: return t("invalid_dates", "Choose 1 to 366 calendar days, ending no later than today.")
    case .permission: return t("permission", "Enable local measurement summaries in Health Privacy to compare activity.")
    case .unavailable: return t("unavailable", "Activity history could not be read. Saved totals are unchanged.")
    }
  }
  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.activity_comparison." + key, fallback: fallback, language: language)
  }
}
