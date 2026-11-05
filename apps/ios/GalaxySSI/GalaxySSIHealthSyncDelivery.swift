import SwiftUI
import UIKit
import UserNotifications

enum GalaxySSIHealthSyncDelivery {
  typealias Scope = GalaxySSIHealthKitImport.Scope
  typealias Incident = GalaxySSIHealthKitSync.Incident
  static let prefix = "galaxyssi.health.sync."
  static let pendingKey = "galaxyssi.pending_health_sync_token"
  static let openNotification = Notification.Name("galaxyssi.open_health_sync")

  struct Receipt: Codable, Equatable {
    let incident: UUID
    var token = UUID()
    var due: Date?
    var submitted = false
    var identifier: String { GalaxySSIHealthSyncDelivery.prefix + token.uuidString }
  }

  struct State: Codable, Equatable {
    var enabled = false
    var receipts: [Scope: Receipt] = [:]
  }

  struct Plan {
    var receipts: [Scope: Receipt] = [:]
    var pending: [Receipt] = []
    var keepDelivered: Set<UUID> = []
  }

  static func token(_ identifier: String) -> UUID? {
    guard identifier.hasPrefix(prefix) else { return nil }
    return UUID(uuidString: String(identifier.dropFirst(prefix.count)))
  }

  static func permitted(_ authorization: UNAuthorizationStatus) -> Bool {
    authorization == .authorized || authorization == .provisional || authorization == .ephemeral
  }

  static func dueAfter(_ date: Date, settings: GalaxySSIHealthRecordingReminders.Settings, calendar: Calendar) -> Date {
    settings.quietEndAfter(max(date, settings.pausedUntil ?? .distantPast), calendar: calendar)
  }

  static func plan(state: State, selected: Set<Scope>, incidents: [Incident],
                   settings: GalaxySSIHealthRecordingReminders.Settings, now: Date, calendar: Calendar,
                   permitted: Bool, scheduled: Set<UUID>, delivered: Set<UUID>) -> Plan {
    guard state.enabled, permitted else { return Plan() }
    let paused = (settings.pausedUntil ?? .distantPast) > now
    var plan = Plan()
    for incident in incidents where selected.contains(incident.scope) && !incident.handled {
      guard var receipt = state.receipts[incident.scope], receipt.incident == incident.id else { continue }
      let visible = delivered.contains(receipt.token)
      let pending = scheduled.contains(receipt.token)
      if visible || (receipt.submitted && !pending && (receipt.due ?? .distantFuture) <= now) {
        receipt.submitted = true
        if visible && !paused { plan.keepDelivered.insert(receipt.token) }
      } else {
        if let due = receipt.due, (pending || due > now), dueAfter(due, settings: settings, calendar: calendar) == due {
          if pending { receipt.submitted = true }
        } else {
          receipt = Receipt(incident: incident.id,
                            due: dueAfter(now.addingTimeInterval(2), settings: settings, calendar: calendar))
        }
        plan.pending.append(receipt)
      }
      plan.receipts[incident.scope] = receipt
    }
    return plan
  }

  static func target(token: UUID, state: State, selected: Set<Scope>, incidents: [Incident],
                     settings: GalaxySSIHealthRecordingReminders.Settings, now: Date) -> Scope? {
    guard state.enabled, (settings.pausedUntil ?? .distantPast) <= now,
          let match = state.receipts.first(where: { $0.value.token == token }),
          selected.contains(match.key),
          incidents.contains(where: { $0.scope == match.key && $0.id == match.value.incident && !$0.handled })
    else { return nil }
    return match.key
  }

  static func request(_ receipt: Receipt, title: String, body: String, now: Date) -> UNNotificationRequest? {
    guard let due = receipt.due else { return nil }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, due.timeIntervalSince(now)), repeats: false)
    return UNNotificationRequest(identifier: receipt.identifier, content: content, trigger: trigger)
  }
}

@MainActor
struct GalaxySSIHealthSyncNotificationLifecycle: ViewModifier {
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @ObservedObject var store: GalaxySSIStore
  @State private var generation = UUID()
  @State private var destination: Destination?

  private struct Destination: Identifiable {
    let records: GalaxySSIHealthRecords
    let scope: GalaxySSIHealthKitImport.Scope
    var id: String { scope.rawValue }
  }

  private var records: GalaxySSIHealthRecords {
    .init(owner: store.profile.identityFingerprint, secrets: store.secrets)
  }

  func body(content: Content) -> some View {
    content
      .onAppear(perform: refresh)
      .onChange(of: scene) { if $0 == .active { refresh() } else if $0 == .background { destination = nil } }
      .onChange(of: store.profile.identityFingerprint) { _ in destination = nil; refresh() }
      .onReceive(NotificationCenter.default.publisher(for: .galaxySSIRuntimePlaintextWillClear)) { _ in destination = nil }
      .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refresh() }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthSyncDelivery.openNotification)) { _ in refresh() }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.syncIncidentsChanged)) {
        if $0.object as? String == records.owner { refresh() }
      }
      .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecordingReminders.changed)) {
        if $0.object as? String == records.owner { refresh() }
      }
      .task(id: generation) { await reconcile() }
      .sheet(item: $destination) { route in
        NavigationView {
          GalaxySSIHealthKitSyncView(records: route.records, focusedScope: route.scope)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
              Button(t("close", "Close")) { destination = nil }
            } }
        }.navigationViewStyle(.stack)
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
    let pendingIDs = Set(pending.compactMap { GalaxySSIHealthSyncDelivery.token($0.identifier) })
    let deliveredIDs = Set(delivered.compactMap { GalaxySSIHealthSyncDelivery.token($0.request.identifier) })
    guard let plan = try? records.reconcileSyncDelivery(now: Date(), calendar: .current,
      permitted: GalaxySSIHealthSyncDelivery.permitted(settings.authorizationStatus),
      scheduled: pendingIDs, delivered: deliveredIDs) else { return }
    let keepPending = Set(plan.pending.map(\.token))
    center.removePendingNotificationRequests(withIdentifiers: pendingIDs.subtracting(keepPending).map {
      GalaxySSIHealthSyncDelivery.prefix + $0.uuidString
    })
    center.removeDeliveredNotifications(withIdentifiers: deliveredIDs.subtracting(plan.keepDelivered).map {
      GalaxySSIHealthSyncDelivery.prefix + $0.uuidString
    })
    for receipt in plan.pending where !pendingIDs.contains(receipt.token) && !deliveredIDs.contains(receipt.token) {
      guard scene == .active, !Task.isCancelled, records.owner == store.profile.identityFingerprint else { return }
      guard let request = GalaxySSIHealthSyncDelivery.request(receipt, title: t("title", "GalaxySSI reminder"),
        body: t("body", "Open GalaxySSI to review."), now: Date()) else { continue }
      do {
        try await center.add(request)
        guard records.owner == store.profile.identityFingerprint else { throw GalaxySSIHealthRecords.Failure.stale }
        try records.markSyncDeliverySubmitted(receipt, calendar: .current)
      } catch {
        center.removePendingNotificationRequests(withIdentifiers: [receipt.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [receipt.identifier])
      }
    }
  }

  private func openPending() {
    let defaults = UserDefaults.standard
    let key = GalaxySSIHealthSyncDelivery.pendingKey
    guard let raw = defaults.string(forKey: key) else { return }
    defaults.removeObject(forKey: key)
    let records = records
    guard let token = UUID(uuidString: raw), let archive = try? records.load(),
          let state = archive.healthKitSyncDelivery,
          let scope = GalaxySSIHealthSyncDelivery.target(token: token, state: state,
            selected: archive.healthKitSyncSelection ?? [], incidents: archive.syncIncidents,
            settings: archive.recordingReminders?.settings ?? .init(), now: Date()) else { return }
    destination = .init(records: records, scope: scope)
  }

  private func t(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health.sync_notice." + key, fallback: fallback, language: language)
  }
}
