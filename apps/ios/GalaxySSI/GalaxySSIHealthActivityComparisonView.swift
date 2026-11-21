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
  @State private var loaded: GalaxySSIHealthActivityComparison?
  @State private var liveMotion: GalaxySSIHealthMotion.State?
  @State private var liveTask: Task<Void, Never>?
  @State private var visible = false
  @State private var task: Task<Void, Never>?
  @State private var historyTask: Task<[GalaxySSIHealthActivityDay], Error>?
  @State private var request: UUID?
  @State private var failure: Failure?
  @State private var showsData = false
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
            DatePicker(t("from", "From"), selection: $first, in: ...today, displayedComponents: .date)
            DatePicker(t("through", "Through"), selection: $last, in: ...today, displayedComponents: .date)
          }
        }
        if let failure {
          Text(failureText(failure)).foregroundColor(.secondary)
          if failure == .unavailable { Button(t("retry", "Reload"), action: reload) }
        } else if let comparison {
          summary(comparison)
          Section {
            Button { showsData = true } label: { chart(comparison).frame(height: 180).contentShape(Rectangle()) }
              .buttonStyle(.plain).accessibilityLabel(t("data", "Chart data"))
              .accessibilityIdentifier("health-activity-chart")
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
    .onChange(of: kind) { _ in reload() }
    .onChange(of: days) { _ in reload() }
    .onChange(of: first) { _ in if days == 0 { reload() } }
    .onChange(of: last) { _ in if days == 0 { reload() } }
    .onChange(of: timeZone) { _ in reload() }
    .onChange(of: store.profile.identityFingerprint) { _ in clear() }
    .onChange(of: scene) { if $0 == .active { reload() } else { clear() } }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.motionChanged)) { motionChanged($0) }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
    .sheet(isPresented: $showsData) { chartData }
  }

  private var today: Date { calendar.startOfDay(for: Date()) }
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
  private func chart(_ result: GalaxySSIHealthActivityComparison) -> some View {
    Canvas { context, size in
      let divisor: Double = kind == .cycling ? 60_000 : 1
      let maximum = max(3 * divisor, Double(result.pairs.flatMap { [$0.current, $0.previous].compactMap { $0 } }.max() ?? 0))
      let left: CGFloat = 44, right = max(left, size.width - 10), top: CGFloat = 14, bottom = max(top, size.height - 10)
      for tick in 0...3 {
        let y = bottom - (bottom - top) * CGFloat(tick) / 3
        var line = Path(); line.move(to: CGPoint(x: left, y: y)); line.addLine(to: CGPoint(x: right, y: y))
        context.stroke(line, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)
        let value = (maximum * Double(tick) / 3 / divisor).formatted(.number.precision(.fractionLength(0)).locale(locale))
        context.draw(Text(value).font(.caption2).foregroundColor(.secondary), at: CGPoint(x: left - 6, y: y), anchor: .trailing)
      }
      for previous in [true, false] {
        var lastPoint: CGPoint?
        let color: Color = previous ? .blue : .green
        for pair in result.pairs {
          guard let value = previous ? pair.previous : pair.current else { lastPoint = nil; continue }
          let point = CGPoint(x: left + (right - left) * CGFloat(pair.id) / CGFloat(max(1, result.pairs.count - 1)),
            y: bottom - (bottom - top) * CGFloat(Double(value) / maximum))
          if let lastPoint {
            var line = Path(); line.move(to: lastPoint); line.addLine(to: point)
            context.stroke(line, with: .color(color), lineWidth: 2)
          }
          context.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)), with: .color(color))
          lastPoint = point
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
    do {
      let preset = days == 0 ? nil : try GalaxySSIHealthActivityComparison.trailing(days: days, now: now, calendar: local)
      let start = preset?.lowerBound ?? local.startOfDay(for: first)
      let end = preset?.upperBound ?? local.startOfDay(for: last)
      let window = try GalaxySSIHealthActivityComparison(first: start, last: end, now: now, calendar: local, rows: [], kind: selected)
      guard let floor = window.pairs.first?.previousDay else { throw GalaxySSIHealthRecords.Failure.invalid }
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
  private var chartData: some View {
    NavigationView {
      List {
        if canRead, let comparison {
          ForEach(comparison.pairs) { pair in
            VStack(alignment: .leading, spacing: 5) {
              Text(pair.day, style: .date).font(.subheadline)
              Text(t("current", "Current period") + ": " + amount(pair.current))
              Text(pair.previousDay, style: .date).font(.caption).foregroundColor(.secondary)
              Text(t("previous", "Previous period") + ": " + amount(pair.previous))
            }.fixedSize(horizontal: false, vertical: true)
          }
        }
      }.navigationTitle(t("data", "Chart data")).galaxySSIHealthTheme().privacySensitive()
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button { showsData = false } label: { Image(systemName: "xmark") }
              .accessibilityLabel(t("close", "Close"))
          }
        }
    }.navigationViewStyle(.stack)
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
    guard canRead, let loaded else { return }
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
    comparison = nil; loaded = nil; liveMotion = nil; failure = nil; showsData = false
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
