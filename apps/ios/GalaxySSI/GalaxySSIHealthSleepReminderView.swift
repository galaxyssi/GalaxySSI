import SwiftUI
import UIKit
import UserNotifications

@MainActor
struct GalaxySSIHealthSleepReminderLifecycle: ViewModifier {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @ObservedObject var store: GalaxySSIStore
  @State private var generation = UUID()

  func body(content: Content) -> some View {
    content
      .onAppear(perform: refresh)
      .onChange(of: scene) { if $0 == .active { refresh() } }
      .onChange(of: store.profile.identityFingerprint) { _ in refresh() }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refresh() }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) {
        if $0.object as? String == store.profile.identityFingerprint { refresh() }
      }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecordingReminders.changed)) {
        if $0.object as? String == store.profile.identityFingerprint { refresh() }
      }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthSleepReminder.changed)) {
        if $0.object as? String == store.profile.identityFingerprint { refresh() }
      }
      .task(id: generation) { await reconcileDelivery() }
  }

  private func refresh() {
    if scene == .active { generation = UUID() }
  }

  private func reconcileDelivery() async {
    guard scene == .active else { return }
    let records = GalaxySSIHealthRecords(owner: store.profile.identityFingerprint, secrets: store.secrets)
    let center = UNUserNotificationCenter.current()
    let status = await center.notificationSettings().authorizationStatus
    let prefix = GalaxySSIHealthSleepReminder.notificationPrefix
    let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
    let visible = await center.deliveredNotifications().filter { $0.request.identifier.hasPrefix(prefix) }
    guard scene == .active, !Task.isCancelled, records.owner == store.profile.identityFingerprint else { return }
    let now = Date()
    let calendar = Calendar.autoupdatingCurrent
    func remove(keepingPending: String? = nil, keepingVisible: String? = nil) {
      center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0 != keepingPending })
      center.removeDeliveredNotifications(withIdentifiers: visible.map(\.request.identifier).filter { $0 != keepingVisible })
    }
    guard let ledger = try? records.reconcileSleepReminders(at: now, calendar: calendar),
          let archive = try? records.load() else { return }
    let settings = archive.recordingReminders?.settings
    let prefs = ledger.preferences
    guard GalaxySSIHealthSyncDelivery.permitted(status),
          let episode = ledger.episodes.first(where: { !$0.closed && !$0.completed }) else { remove(); return }
    func allowed(_ date: Date) -> Date? {
      GalaxySSIHealthSleepReminder.deliveryDate(date, episode: episode, preferences: prefs, settings: settings, calendar: calendar)
    }
    let id = prefix + episode.id.uuidString
    let previous = pending.first(where: { $0.identifier == id })
    let delivered = visible.first(where: { $0.request.identifier == id })
    let consumed = [episode.deliveredAt, delivered?.date, previous == nil ? episode.notificationDue : nil]
      .compactMap { $0 }.filter { $0 <= now }.min()
    if let consumed {
      remove(keepingVisible: allowed(now) == now ? id : nil)
      try? records.saveSleepDelivery(episode, preferences: prefs, settings: settings, due: nil, delivered: consumed)
      return
    }
    guard let due = allowed(now.addingTimeInterval(2)) else { remove(); return }
    if let saved = episode.notificationDue, saved > now, allowed(saved) == saved,
       let trigger = previous?.trigger as? UNCalendarNotificationTrigger,
       let next = trigger.nextTriggerDate(), abs(next.timeIntervalSince(saved)) < 1 {
      remove(keepingPending: id)
      return
    }
    remove()
    let content = UNMutableNotificationContent()
    content.title = GalaxySSIHealthSleepReminderView.text("generic_title", "GalaxySSI reminder", language: language)
    content.body = GalaxySSIHealthSleepReminderView.text("generic_body", "Open GalaxySSI to review.", language: language)
    let trigger = UNCalendarNotificationTrigger(dateMatching:
      GalaxySSIHealthRecordingReminders.calendarTriggerDate(due), repeats: false)
    do {
      try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
      guard records.owner == store.profile.identityFingerprint else { throw GalaxySSIHealthRecords.Failure.stale }
      try records.saveSleepDelivery(episode, preferences: prefs, settings: settings, due: due, delivered: nil)
    } catch {
      if !Task.isCancelled {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
      }
    }
  }
}

@MainActor
struct GalaxySSIHealthSleepReminderView: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  let records: GalaxySSIHealthRecords
  @State private var ledger = GalaxySSIHealthSleepReminder.Ledger()
  @State private var allowed = false
  @State private var failed = false
  @SceneStorage("galaxyssi.health.sleep.latest-evidence-episode") private var latestEvidenceEpisode = ""
  @State private var evidenceRoute: EvidenceRoute?

  private struct EvidenceRoute: Identifiable {
    enum Kind { case baseline, recent, report }
    let id = UUID()
    let kind: Kind
    let snapshot: GalaxySSIHealthSleepReminder.Evidence
  }

  var body: some View {
    Form {
      if scene == .active {
        Section(t("settings", "Reminder settings")) {
          Toggle(t("enabled", "Sleep duration changes"), isOn: setting(\.enabled))
          if ledger.preferences.enabled {
            Picker(t("threshold", "Decrease threshold"), selection: setting(\.threshold)) {
              ForEach(GalaxySSIHealthSleepReminder.thresholds, id: \.self) { Text(minutes(Decimal($0))).tag($0) }
            }
            Toggle(t("merge", "Combine continuing changes"), isOn: setting(\.merge))
            Toggle(t("notifications", "System notifications"), isOn: setting(\.notifications))
            if ledger.preferences.notifications {
              hourPicker(t("quiet_start", "Quiet hours begin"), selection: setting(\.quietStart))
              hourPicker(t("quiet_end", "Quiet hours end"), selection: setting(\.quietEnd))
            }
          }
        }
        if allowed {
          Section(t("history", "Sleep change history")) {
            if ledger.episodes.isEmpty { Text(t("empty", "No qualifying changes")) }
            ForEach(ledger.episodes) { episode in
              NavigationLink {
                detail(episode.id)
              } label: {
                VStack(alignment: .leading) {
                  Text(episode.latest.day, style: .date)
                  Text(status(episode)).foregroundColor(.secondary)
                }
              }
            }
          }
        } else { Text(t("permission", "Enable the local measurement summary in Health Privacy to see evidence.")) }
        if failed { Text(t("error", "Could not update reminders.")).foregroundColor(.secondary) }
      }
    }
    .navigationTitle(t("title", "Sleep Change Reminders"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onChange(of: scene) { if $0 == .active { reload() } else { allowed = false; ledger = .init() } }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.trendInputsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
  }

  @ViewBuilder
  private func detail(_ id: UUID) -> some View {
    List {
      if scene == .active && allowed, let episode = ledger.episodes.first(where: { $0.id == id }) {
        let hasLatest = episode.first != episode.latest
        let showLatest = hasLatest && latestEvidenceEpisode == id.uuidString
        if hasLatest {
          Picker(t("snapshot", "Evidence version"), selection: Binding(get: { showLatest }, set: {
            latestEvidenceEpisode = $0 ? id.uuidString : ""
          })) {
            Text(t("first", "Initial evidence")).tag(false)
            Text(t("latest", "Latest evidence")).tag(true)
          }
          .pickerStyle(.segmented)
        }
        let selected = showLatest ? episode.latest : episode.first
        evidence(showLatest ? t("latest", "Latest evidence") : t("first", "Initial evidence"), selected)
        Section {
          Button(t("recent_records", "Recent contributing records")) {
            evidenceRoute = .init(kind: .recent, snapshot: selected)
          }
          Button(t("baseline_records", "Baseline contributing records")) {
            evidenceRoute = .init(kind: .baseline, snapshot: selected)
          }
          Button(t("sleep_report", "Open sleep-only weekly report")) {
            evidenceRoute = .init(kind: .report, snapshot: selected)
          }
        }
        if !episode.closed && !episode.completed {
          Button(t("complete", "Complete")) { update(episode, complete: true) }
          Button(t("snooze", "Snooze for 24 hours")) { update(episode, complete: false) }
        }
      }
    }
    .navigationTitle(t("evidence", "Sleep Evidence"))
    .onChange(of: allowed) { if !$0 { evidenceRoute = nil } }
    .onChange(of: scene) { if $0 == .background { evidenceRoute = nil } }
    .sheet(item: $evidenceRoute) { route in
      NavigationView {
        Group {
          if route.kind == .report {
            GalaxySSIWeeklyHealthReportView(records: records, sleepEvidence: route.snapshot)
          } else {
            GalaxySSIHealthSleepContributors(records: records, snapshot: route.snapshot, baseline: route.kind == .baseline)
          }
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) {
          Button(t("close", "Close")) { evidenceRoute = nil }
        } }
      }
      .navigationViewStyle(.stack)
    }
  }

  private func evidence(_ title: String, _ evidence: GalaxySSIHealthSleepReminder.Evidence) -> some View {
    Section(title) {
      Text(t("decrease", "Average decrease") + ": " + minutes(evidence.decrease))
      Text(evidence.calculatedAt, format: .dateTime)
      Text(String(format: t("coverage", "%lld of 14 baseline days; %lld of 7 recent days"),
                  Int64(evidence.days.prefix(14).compactMap(\.minutes).count),
                  Int64(evidence.days.suffix(7).compactMap(\.minutes).count)))
      Text(String(format: t("rule", "Rule %lld; threshold %lld min"), Int64(evidence.rule), Int64(evidence.threshold)))
      Text(evidence.zone).foregroundColor(.secondary)
      chart(evidence.days)
      ForEach(evidence.days) { day in
        HStack {
          Text(day.date, style: .date)
          Spacer()
          Text(day.minutes.map(minutes) ?? t("missing", "No reading")).foregroundColor(.secondary)
        }
      }
    }
    .environment(\.timeZone, TimeZone(identifier: evidence.zone) ?? .current)
  }

  private func chart(_ days: [GalaxySSIHealthSleepReminder.Day]) -> some View {
    Canvas { context, size in
      let values = days.compactMap(\.minutes).map { NSDecimalNumber(decimal: $0).doubleValue }
      guard let low = values.min(), let high = values.max(), low.isFinite, high.isFinite else { return }
      var last: CGPoint?
      for (index, day) in days.enumerated() {
        guard let value = day.minutes else { last = nil; continue }
        let number = NSDecimalNumber(decimal: value).doubleValue
        let fraction = high > low ? (number - low) / (high - low) : 0.5
        let point = CGPoint(x: 4 + CGFloat(index) / CGFloat(max(1, days.count - 1)) * (size.width - 8),
                            y: 4 + CGFloat(1 - fraction) * (size.height - 8))
        if let last {
          var path = Path()
          path.move(to: last)
          path.addLine(to: point)
          context.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
        context.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)),
                     with: .color(.accentColor))
        last = point
      }
    }
    .frame(height: 100)
    .accessibilityHidden(true)
  }

  private func setting<Value>(_ key: WritableKeyPath<GalaxySSIHealthSleepReminder.Preferences, Value>) -> Binding<Value> {
    Binding(get: { ledger.preferences[keyPath: key] }, set: { value in
      var updated = ledger.preferences
      updated[keyPath: key] = value
      do { try records.setSleepPreferences(updated); reload() }
      catch { failed = true }
    })
  }

  private func hourPicker(_ title: String, selection: Binding<Int>) -> some View {
    Picker(title, selection: selection) {
      ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) }
    }
  }

  private func update(_ episode: GalaxySSIHealthSleepReminder.Episode, complete: Bool) {
    do {
      try records.updateSleepEpisode(version: episode.version, completion: complete,
                                     snooze: complete ? nil : Date().addingTimeInterval(86_400))
      NotificationCenter.default.post(name: GalaxySSIHealthRecords.trendInputsChanged, object: records.owner)
      reload()
    } catch { failed = true; reload() }
  }

  private func reload() {
    guard scene == .active else { return }
    do {
      allowed = try records.load().derivesOverview == true
      ledger = try records.reconcileSleepReminders(at: Date(), calendar: .autoupdatingCurrent)
    } catch { failed = true; allowed = false; ledger = .init() }
  }

  private func status(_ episode: GalaxySSIHealthSleepReminder.Episode) -> String {
    if episode.completed { return t("completed", "Completed") }
    if episode.closed { return t("closed", "Closed") }
    if (episode.snoozedUntil ?? .distantPast) > Date() { return t("snoozed", "Snoozed") }
    return t("open", "Open")
  }

  private func minutes(_ value: Decimal) -> String { value.formatted(.number.precision(.fractionLength(0...1))) + " " + t("min", "min") }
  private func t(_ key: String, _ fallback: String) -> String { Self.text(key, fallback, language: language) }
  static func text(_ key: String, _ fallback: String, language: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.sleep_reminder." + key, fallback: fallback, language: language)
  }
}

@MainActor
private struct GalaxySSIHealthSleepContributors: View {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  let records: GalaxySSIHealthRecords
  let snapshot: GalaxySSIHealthSleepReminder.Evidence
  let baseline: Bool
  @State private var rows: [GalaxySSIHealthReading]?
  @State private var limit = 30

  var body: some View {
    List {
      if scene == .active {
        if let rows {
          ForEach(rows.prefix(limit)) { reading in
            VStack(alignment: .leading, spacing: 4) {
              HStack {
                Text(reading.measuredAt, style: .date)
                Text(reading.measuredAt, style: .time)
              }
              Text((reading.value?.formatted() ?? "") + " " + reading.unit)
              Text(String(format: t("revision", "Revision %lld"), Int64(reading.revision)))
                .foregroundColor(.secondary)
            }
          }
          if rows.count > limit { Button(t("more_records", "Show more records")) { limit += 30 } }
        } else {
          Text(t("evidence_stale", "The saved evidence is unavailable or no longer matches the contributing records."))
        }
      }
    }
    .environment(\.timeZone, TimeZone(identifier: snapshot.zone) ?? .current)
    .navigationTitle(baseline ? t("baseline_records", "Baseline contributing records") : t("recent_records", "Recent contributing records"))
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: reload)
    .onDisappear { rows = nil }
    .onChange(of: scene) { if $0 == .active { reload() } else { rows = nil } }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) {
      if $0.object as? String == records.owner { reload() }
    }
  }

  private func reload() {
    guard scene == .active, let archive = try? records.load(), archive.derivesOverview == true else {
      rows = nil
      return
    }
    rows = snapshot.contributors(archive.current, baseline: baseline)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSIHealthSleepReminderView.text(key, fallback, language: language)
  }
}
