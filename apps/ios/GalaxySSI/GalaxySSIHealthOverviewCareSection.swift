import SwiftUI
import UIKit

@MainActor
struct GalaxySSIHealthOverviewCareSection: View {
  typealias Care = GalaxySSIHealthOverviewCare
  @EnvironmentObject private var store: GalaxySSIStore
  @Environment(\.scenePhase) private var scene
  @Environment(\.galaxySSIInterfaceLanguage) private var language
  @Environment(\.calendar) private var calendar
  @Environment(\.timeZone) private var timeZone
  @Environment(\.locale) private var locale
  let records: GalaxySSIHealthRecords
  @State private var snapshot: Care.Snapshot?
  @State private var failed = false
  @State private var route: Route?

  private enum Route: Identifiable {
    case action(Care.Action), concern(Care.Concern), visit(Care.Visit)
    var id: String {
      switch self {
      case .action(let item): return "action:" + item.id
      case .concern(let item): return "concern:" + item.id.uuidString
      case .visit(let item): return "visit:" + item.id.uuidString
      }
    }
  }

  var body: some View {
    Group {
      if canRead {
        if let snapshot, snapshot.enabled, snapshot.permitted {
          Section(t("actions", "Today's actions")) {
            if !snapshot.actionsReady {
              Text(t("pending", "Actions need review in Health Actions.")).foregroundColor(.secondary)
            } else if snapshot.actions.isEmpty && snapshot.upcoming == nil {
              Text(t("empty", "No actions planned for today")).foregroundColor(.secondary)
            }
            ForEach(snapshot.actions) { action in actionRow(action, next: false) }
            if let upcoming = snapshot.upcoming { actionRow(upcoming, next: true) }
          }
        }
        NavigationLink {
          GalaxySSIHealthCareAgendaView(records: records)
        } label: {
          Label(health("agenda.title", "Health Actions"), systemImage: "checklist")
        }
        if failed || snapshot?.permitted == false || snapshot?.enabled == false || snapshot?.concerns.isEmpty == false {
          Section(t("concerns", "Ongoing concerns")) {
            if failed { Text(t("unavailable", "Care overview is unavailable.")).foregroundColor(.secondary) }
            else if snapshot?.permitted == false {
              Text(t("privacy", "Enable local health summaries to view care here.")).foregroundColor(.secondary)
            } else if snapshot?.enabled == false {
              Text(t("disabled", "Local health review is off.")).foregroundColor(.secondary)
            }
            ForEach(snapshot?.concerns ?? []) { concern in
              Button { open(.concern(concern)) } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(concern.metric.title(language: language))
                  Text(concern.sourceChanged && concern.stage != .paused
                    ? t("source_changed", "Source changed; review required")
                    : GalaxySSIHealthCareText.stage(concern.stage, language: language))
                    .font(.caption).foregroundColor(.secondary)
                }
              }.buttonStyle(.borderless)
            }
          }
        }
        NavigationLink {
          GalaxySSIHealthCareView(records: records)
        } label: {
          Label(health("care.title", "Health Care"), systemImage: "heart.text.square")
        }
        if let snapshot, !snapshot.visits.isEmpty {
          Section(t("visits", "Visit follow-up")) {
            ForEach(snapshot.visits) { visit in
              Button { open(.visit(visit)) } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(visit.entry.details.purpose)
                  Text(visit.entry.details.state.title(language)).font(.caption).foregroundColor(.secondary)
                  if let at = visit.at { Text(visitDate(at, zone: visit.entry.details.zone)).font(.caption).foregroundColor(.secondary) }
                  if let journal = visit.journal { Text(journalTitle(journal.state)).font(.caption).foregroundColor(.secondary) }
                }
              }.buttonStyle(.borderless)
            }
          }
        }
      }
    }
    .onAppear { reload() }
    .onDisappear { clear() }
    .task(id: scene) {
      guard scene == .active else { clear(); return }
      reload()
      while !Task.isCancelled {
        do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
        guard !Task.isCancelled else { return }
        reload(dismiss: false)
      }
    }
    .onChange(of: store.profile.identityFingerprint) { _ in reload() }
    .onChange(of: timeZone) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in clear() }
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in reload() }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.recordsChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthRecords.profileInputsChanged)) { changed($0) }
    .onReceive(NotificationCenter.default.publisher(for: GalaxySSIHealthOriginalStore.indexChanged)) { changed($0) }
    .sheet(item: $route) { selected in
      switch selected {
      case .action(let action):
        navigation {
          GalaxySSIHealthCareActionReviewView(records: records,
            scope: .init(concern: action.concern, metric: action.metric), actionID: action.actionID)
        }
      case .concern(let concern):
        navigation { GalaxySSIHealthCareDetail(records: records, id: concern.id, metric: concern.metric) }
      case .visit(let visit):
        if visit.journal != nil {
          GalaxySSIHealthVisitJournalView(records: records, concern: visit.concern, metric: visit.metric, visit: visit.id)
        } else {
          navigation { GalaxySSIHealthEncounterView(records: records, concern: visit.concern, metric: visit.metric, entryID: visit.id) }
        }
      }
    }
  }

  private var canRead: Bool {
    scene == .active && UIApplication.shared.isProtectedDataAvailable && store.profile.identityFingerprint == records.owner
  }

  private func actionRow(_ action: Care.Action, next: Bool) -> some View {
    Button { open(.action(action)) } label: {
      VStack(alignment: .leading, spacing: 4) {
        Text(action.title)
        Text(next ? t("next", "Next action") : action.overdue ? t("overdue", "Overdue") : t("due", "Planned"))
          .font(.caption).foregroundColor(.secondary)
        Text(action.due, style: .date).font(.caption).foregroundColor(.secondary)
        Text(action.due, style: .time).font(.caption).foregroundColor(.secondary)
      }
    }.buttonStyle(.borderless)
  }

  private func open(_ selected: Route) {
    guard canRead, let old = snapshot, let fresh = try? records.localCareOverview(calendar: localCalendar),
          fresh.permitted, fresh.enabled, fresh.permission == old.permission else { reload(); return }
    snapshot = fresh
    if contains(selected, in: fresh) { route = selected }
  }

  private func contains(_ selected: Route, in value: Care.Snapshot) -> Bool {
    switch selected {
    case .action(let item): return value.actions.contains(item) || value.upcoming == item
    case .concern(let item): return value.concerns.contains(item)
    case .visit(let item): return value.visits.contains(item)
    }
  }

  private var localCalendar: Calendar { var value = calendar; value.timeZone = timeZone; return value }

  private func reload(dismiss: Bool = true) {
    if dismiss { route = nil }
    guard canRead else { clear(); return }
    do {
      let fresh = try records.localCareOverview(calendar: localCalendar)
      if let route, !fresh.enabled || !fresh.permitted || fresh.permission != snapshot?.permission || !contains(route, in: fresh) {
        self.route = nil
      }
      snapshot = fresh; failed = false
    }
    catch { snapshot = nil; route = nil; failed = true }
  }

  private func changed(_ notification: Notification) {
    if notification.object as? String == records.owner { reload() }
  }

  private func clear() { snapshot = nil; route = nil; failed = false }

  private func navigation<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    NavigationView {
      content().galaxySSIHealthTheme().toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(health("done", "Done")) { route = nil }
        }
      }
    }.navigationViewStyle(.stack)
  }

  private func visitDate(_ date: Date, zone: String) -> String {
    let format = DateFormatter()
    format.locale = locale; format.timeZone = TimeZone(identifier: zone) ?? timeZone
    format.dateStyle = .medium; format.timeStyle = .short
    return format.string(from: date) + " (" + zone + ")"
  }

  private func journalTitle(_ state: GalaxySSIHealthVisitJournal.State) -> String {
    switch state {
    case .active: return GalaxySSIHealthVisitJournal.text("state_active", "Active", language)
    case .review: return GalaxySSIHealthVisitJournal.text("state_review", "Review pending", language)
    case .paused: return GalaxySSIHealthVisitJournal.text("state_paused", "Paused", language)
    case .archived: return GalaxySSIHealthVisitJournal.text("state_archived", "Archived", language)
    }
  }

  private func t(_ key: String, _ fallback: String) -> String { health("overview_care." + key, fallback) }
  private func health(_ key: String, _ fallback: String) -> String {
    GalaxySSILocalization.string("galaxyssi.health." + key, fallback: fallback, language: language)
  }
}
