import SwiftUI
import UIKit
import UserNotifications

enum GalaxySSIHealthReviewDelivery {
  static let prefix = "galaxyssi.health.review."
  static let pendingKey = "galaxyssi.pending_health_review_token"
  static let openNotification = Notification.Name("galaxyssi.open_health_review")

  struct Preferences: Codable, Equatable {
    var enabled = false
    var pausedUntil: Date?
    var quietStart = 22
    var quietEnd = 8

    func nextAllowed(_ date: Date, calendar: Calendar) -> Date {
      let date = max(date, pausedUntil ?? .distantPast)
      guard quietStart != quietEnd else { return date }
      let hour = calendar.component(.hour, from: date)
      let quiet = quietStart < quietEnd ? (quietStart..<quietEnd).contains(hour) : hour >= quietStart || hour < quietEnd
      guard quiet else { return date }
      return calendar.nextDate(after: date, matching: DateComponents(hour: quietEnd, minute: 0),
                               matchingPolicy: .nextTime) ?? date
    }
  }

  struct Ticket: Codable, Equatable {
    let token: UUID
    let due: Date
    let cycle: Date?
    let versions: [UUID]
    var submitted = false
    var suppressed = false
    var identifier: String { GalaxySSIHealthReviewDelivery.prefix + token.uuidString }
  }

  struct Plan {
    var tickets: [String: Ticket] = [:]
    var pending: [Ticket] = []
    var keepDelivered: Set<UUID> = []
  }

  static func action(for job: GalaxySSIHealthReviewReminders.Job,
                     state: GalaxySSIHealthReviewReminders.State) -> GalaxySSIHealthReviewReminders.Action? {
    guard let action = state.actions[job.key], action.versions == job.versions else { return nil }
    return action.action
  }

  static func cycle(for job: GalaxySSIHealthReviewReminders.Job, state: GalaxySSIHealthReviewReminders.State) -> Date? {
    if case .snoozed(let until)? = action(for: job, state: state) { return until }
    return nil
  }

  static func suppressExisting(_ jobs: [GalaxySSIHealthReviewReminders.Job],
                               in state: inout GalaxySSIHealthReviewReminders.State, at now: Date) {
    let tickets = jobs.compactMap { job -> (String, Ticket)? in
      guard action(for: job, state: state) != .handled else { return nil }
      return (job.key, Ticket(token: UUID(), due: now, cycle: cycle(for: job, state: state),
                             versions: job.versions, suppressed: true))
    }
    state.deliveries = Dictionary(uniqueKeysWithValues: tickets)
  }

  static func target(for token: UUID, jobs: [GalaxySSIHealthReviewReminders.Job],
                     state: GalaxySSIHealthReviewReminders.State, now: Date) -> GalaxySSIHealthReviewReminders.Job? {
    guard state.enabled, let prefs = state.notificationPreferences, prefs.enabled,
          (prefs.pausedUntil ?? .distantPast) <= now,
          let entry = state.deliveries?.first(where: { $0.value.token == token && !$0.value.suppressed }),
          let job = jobs.first(where: { $0.key == entry.key && $0.versions == entry.value.versions }),
          action(for: job, state: state)?.hides(at: now) != true,
          cycle(for: job, state: state) == entry.value.cycle else { return nil }
    return job
  }

  static func token(_ identifier: String) -> UUID? {
    guard identifier.hasPrefix(prefix) else { return nil }
    return UUID(uuidString: String(identifier.dropFirst(prefix.count)))
  }

  static func request(_ ticket: Ticket, title: String, body: String, now: Date) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, ticket.due.timeIntervalSince(now)), repeats: false)
    return UNNotificationRequest(identifier: ticket.identifier, content: content, trigger: trigger)
  }

  static func permitted(_ status: UNAuthorizationStatus) -> Bool {
    status == .authorized || status == .provisional || status == .ephemeral
  }

  static func plan(jobs: [GalaxySSIHealthReviewReminders.Job], state: GalaxySSIHealthReviewReminders.State,
                   now: Date, calendar: Calendar, permitted: Bool, scheduled: Set<UUID>, delivered: Set<UUID>)
    -> Plan {
    let prefs = state.notificationPreferences ?? .init()
    guard state.enabled && prefs.enabled else { return Plan() }
    let paused = (prefs.pausedUntil ?? .distantPast) > now
    let existing = state.deliveries ?? [:]
    var plan = Plan()
    for job in jobs {
      if action(for: job, state: state) == .handled { continue }
      let snooze = cycle(for: job, state: state)
      let previous = existing[job.key].flatMap { $0.cycle == snooze ? $0 : nil }
      let consumed = previous.map {
        delivered.contains($0.token) || ($0.submitted && $0.due <= now && !scheduled.contains($0.token))
      } ?? false
      if !permitted || previous?.suppressed == true || (consumed && previous?.versions != job.versions) {
        if let previous, previous.suppressed, previous.versions == job.versions { plan.tickets[job.key] = previous }
        else {
          plan.tickets[job.key] = Ticket(token: UUID(), due: now, cycle: snooze,
                                         versions: job.versions, suppressed: true)
        }
        continue
      }
      if var previous, consumed {
        previous.submitted = true
        plan.tickets[job.key] = previous
        if !paused, delivered.contains(previous.token) { plan.keepDelivered.insert(previous.token) }
        continue
      }
      let earliest = prefs.nextAllowed(max(now.addingTimeInterval(2), snooze ?? .distantPast), calendar: calendar)
      let ticket: Ticket
      if let previous, previous.versions == job.versions, previous.due >= (snooze ?? .distantPast),
         (previous.due > now || scheduled.contains(previous.token)),
         prefs.nextAllowed(previous.due, calendar: calendar) == previous.due {
        var resumed = previous
        if scheduled.contains(previous.token) { resumed.submitted = true }
        ticket = resumed
      } else { ticket = Ticket(token: UUID(), due: earliest, cycle: snooze, versions: job.versions) }
      plan.tickets[job.key] = ticket
      if plan.pending.count < 24 { plan.pending.append(ticket) }
    }
    return plan
  }
}

@MainActor
struct GalaxySSIHealthReviewNotificationSettings: View {
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.scenePhase) private var scene
  @Environment(\.openURL) private var openURL
  let records: GalaxySSIHealthRecords
  @State private var preferences = GalaxySSIHealthReviewDelivery.Preferences()
  @State private var failed = false
  @State private var authorization: UNAuthorizationStatus?

  var body: some View {
    Section(t("system", "System review notifications")) {
      Toggle(t("system", "System review notifications"), isOn: Binding(get: { preferences.enabled }, set: setEnabled))
      if preferences.enabled {
        if let authorization, !GalaxySSIHealthReviewDelivery.permitted(authorization) {
          Button(t("notification_permission", "Allow notifications in Settings")) {
            if authorization == .notDetermined {
              Task { await refreshAuthorization(request: true) }
            } else if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
          }
        }
        Picker(t("quiet_start", "Quiet hours begin"), selection: setting(\.quietStart)) { hours }
        Picker(t("quiet_end", "Quiet hours end"), selection: setting(\.quietEnd)) { hours }
        if (preferences.pausedUntil ?? .distantPast) > Date() {
          Button(t("resume_notifications", "Resume notifications")) { change { $0.pausedUntil = nil } }
        } else {
          Button(t("pause_notifications", "Pause notifications for one hour")) {
            change { $0.pausedUntil = Date().addingTimeInterval(3_600) }
          }
        }
      }
      if failed { Text(t("failed", "The review changed or is unavailable.")).foregroundColor(.secondary) }
    }
    .onAppear {
      preferences = (try? records.load().reviewReminderState?.notificationPreferences) ?? .init()
    }
    .task(id: scene) { if scene == .active { await refreshAuthorization() } }
  }

  private var hours: some View {
    ForEach(0..<24) { hour in Text(String(format: "%02d:00", hour)).tag(hour) }
  }

  private func setting<Value>(_ key: WritableKeyPath<GalaxySSIHealthReviewDelivery.Preferences, Value>) -> Binding<Value> {
    Binding(get: { preferences[keyPath: key] }, set: { value in change { $0[keyPath: key] = value } })
  }

  private func setEnabled(_ enabled: Bool) {
    change { $0.enabled = enabled }
    if enabled && preferences.enabled { Task { await refreshAuthorization(request: true) } }
  }

  private func refreshAuthorization(request: Bool = false) async {
    let center = UNUserNotificationCenter.current()
    let status = await center.notificationSettings().authorizationStatus
    if request, status == .notDetermined {
      do { _ = try await center.requestAuthorization(options: [.alert]) }
      catch { failed = true }
    }
    guard !Task.isCancelled else { return }
    authorization = await center.notificationSettings().authorizationStatus
    if request {
      NotificationCenter.default.post(name: GalaxySSIHealthRecords.reviewInputsChanged, object: records.owner)
    }
  }

  private func change(_ update: (inout GalaxySSIHealthReviewDelivery.Preferences) -> Void) {
    var edited = preferences
    update(&edited)
    do { try records.setReviewNotificationPreferences(edited); preferences = edited; failed = false }
    catch { failed = true }
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.review_reminder." + key, fallback: fallback, language: language)
  }
}

@MainActor
struct GalaxySSIHealthReviewNotificationLifecycle: ViewModifier {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @ObservedObject var store: GalaxySSIStore
  @State private var generation = UUID()
  @State private var destination: Destination?

  private struct Destination: Identifiable {
    let records: GalaxySSIHealthRecords
    let job: GalaxySSIHealthReviewReminders.Job
    let original: GalaxySSIHealthOriginalStore.Original?
    var id: String { job.key }
  }

  private var records: GalaxySSIHealthRecords {
    GalaxySSIHealthRecords(owner: store.profile.identityFingerprint, secrets: store.secrets)
  }

  func body(content: Content) -> some View {
    content
      .onAppear(perform: refresh)
      .onChange(of: scene) { if $0 == .active { refresh() } else if $0 == .background { destination = nil } }
      .onChange(of: store.profile.identityFingerprint) { _ in destination = nil; refresh() }
      .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in destination = nil }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refresh() }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthReviewDelivery.openNotification)) { _ in refresh() }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.reviewInputsChanged)) {
        if $0.object as? String == records.owner { refresh() }
      }
      .task(id: generation) { await reconcile() }
      .sheet(item: $destination) { route in
        NavigationView {
          Group {
            if let original = route.original {
              GalaxySSIHealthReportBatchView(records: route.records,
                store: GalaxySSIHealthOriginalStore(owner: route.records.owner, secrets: route.records.secrets), original: original)
            } else {
              GalaxySSIHealthTableImportView(records: route.records, resumeReviewID: route.job.target,
                                              resumeReviewVersion: route.job.versions.first)
            }
          }
          .toolbar { ToolbarItem(placement: .cancellationAction) {
            Button(t("close", "Close")) { destination = nil }
          } }
        }
        .navigationViewStyle(.stack)
      }
  }

  private func refresh() {
    guard scene == .active else { return }
    openPending()
    generation = UUID()
  }

  private func reconcile() async {
    guard scene == .active else { return }
    let records = records
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    let pending = await center.pendingNotificationRequests()
    let delivered = await center.deliveredNotifications()
    guard scene == .active, !Task.isCancelled, records.owner == store.profile.identityFingerprint else { return }
    let pendingIDs = Set(pending.compactMap { GalaxySSIHealthReviewDelivery.token($0.identifier) })
    let deliveredIDs = Set(delivered.compactMap { GalaxySSIHealthReviewDelivery.token($0.request.identifier) })
    let calendar = Calendar.current
    let permitted = GalaxySSIHealthReviewDelivery.permitted(settings.authorizationStatus)
    var availableOriginals = Set<UUID>()
    if (try? records.load().reportReview?.isEmpty) == false {
      let store = GalaxySSIHealthOriginalStore(owner: records.owner, secrets: records.secrets)
      guard let listing = try? store.list() else { return }
      availableOriginals = Set(listing.originals.filter { $0.kind == .pdf }.map(\.id))
    }
    guard let plan = try? records.reconcileReviewDelivery(now: Date(), calendar: calendar,
      permitted: permitted, scheduled: pendingIDs, delivered: deliveredIDs, availableOriginals: availableOriginals)
    else { return }
    let keepPending = Set(plan.pending.map(\.token))
    center.removePendingNotificationRequests(withIdentifiers: pendingIDs.subtracting(keepPending).map {
      GalaxySSIHealthReviewDelivery.prefix + $0.uuidString
    })
    center.removeDeliveredNotifications(withIdentifiers: deliveredIDs.subtracting(plan.keepDelivered).map {
      GalaxySSIHealthReviewDelivery.prefix + $0.uuidString
    })
    for ticket in plan.pending where !pendingIDs.contains(ticket.token) && !deliveredIDs.contains(ticket.token) {
      guard scene == .active, !Task.isCancelled, records.owner == store.profile.identityFingerprint else { return }
      do {
        try await center.add(GalaxySSIHealthReviewDelivery.request(ticket,
          title: t("notification_title", "GalaxySSI reminder"), body: t("notification_body", "Open GalaxySSI to review."),
          now: Date()))
        guard records.owner == store.profile.identityFingerprint else { throw GalaxySSIHealthRecords.Failure.stale }
        try records.markReviewDeliverySubmitted(ticket, calendar: Calendar.current)
      } catch {
        center.removePendingNotificationRequests(withIdentifiers: [ticket.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [ticket.identifier])
      }
    }
  }

  private func openPending() {
    let defaults = UserDefaults.standard
    let key = GalaxySSIHealthReviewDelivery.pendingKey
    guard let raw = defaults.string(forKey: key), let token = UUID(uuidString: raw) else { return }
    defaults.removeObject(forKey: key)
    let records = records
    guard let archive = try? records.load(), let state = archive.reviewReminderState,
          let job = GalaxySSIHealthReviewDelivery.target(for: token, jobs: GalaxySSIHealthReviewReminders.jobs(in: archive),
                                                         state: state, now: Date()) else { return }
    let original: GalaxySSIHealthOriginalStore.Original?
    if job.kind == .report {
      let originals = GalaxySSIHealthOriginalStore(owner: records.owner, secrets: records.secrets)
      guard let item = try? originals.list().originals.first(where: { $0.id == job.target && $0.kind == .pdf }),
            archive.reportReview?.contains(where: {
              job.versions.contains($0.version) && $0.source.sha256 == item.sha256
            }) == true else { return }
      original = item
    } else { original = nil }
    destination = .init(records: records, job: job, original: original)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.review_reminder." + key, fallback: fallback, language: language)
  }
}
