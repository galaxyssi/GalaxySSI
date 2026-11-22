import Foundation

enum GalaxySSIHealthOverviewAttention {
  enum Order: String, CaseIterable {
    case changesFirst = "CHANGES_FIRST", reviewFirst = "REVIEW_FIRST", mostRecent = "MOST_RECENT"
    func title(_ language: String) -> String {
      let fallback: String
      switch self {
      case .changesFirst: fallback = "Changes first"
      case .reviewFirst: fallback = "Reviews first"
      case .mostRecent: fallback = "Most recent"
      }
      return GalaxySSILocalization.string("galaxyssi.health.attention.order." + rawValue, fallback: fallback, language: language)
    }
  }
  enum Kind: Equatable { case change, report, table, connection }
  struct Item: Identifiable {
    let id: String
    let kind: Kind
    let at: Date
    var incident: GalaxySSIHealthSourceAttention.Incident? = nil
  }

  static func sorted(_ items: [Item], order: Order) -> [Item] {
    func priority(_ item: Item) -> Int {
      switch order {
      case .mostRecent: return 0
      case .changesFirst: return item.kind == .change ? 0 : 1
      case .reviewFirst: return item.kind == .report || item.kind == .table ? 0 : 1
      }
    }
    return items.sorted {
      if priority($0) != priority($1) { return priority($0) < priority($1) }
      if $0.at != $1.at { return $0.at > $1.at }
      return $0.id < $1.id
    }
  }

  @MainActor static func items(archive: GalaxySSIHealthRecords.Archive,
      sources: [GalaxySSIHealthSourceAttention.Incident], now: Date, calendar: Calendar) -> [Item] {
    var result = sources.map { Item(id: "source:" + $0.id.uuidString, kind: .connection, at: $0.failedAt, incident: $0) }
    let reviews = GalaxySSIHealthReviewReminders.visible(GalaxySSIHealthReviewReminders.jobs(in: archive),
      state: archive.reviewReminderState ?? .init(), now: now)
    result += reviews.prefix(30).map { Item(id: $0.id, kind: $0.kind == .report ? .report : .table, at: $0.at) }
    // Read-only projection: only an existing, still-current episode can appear here.
    if archive.derivesOverview == true, let ledger = archive.sleepReminders, ledger.preferences.enabled,
       let fresh = GalaxySSIHealthSleepReminder.evidence(archive.current, at: now, calendar: calendar,
         threshold: ledger.preferences.threshold),
       let episode = ledger.episodes.first(where: {
         !$0.closed && !$0.completed && $0.snoozedUntil.map({ $0 <= now }) != false && $0.latest.matches(fresh)
       }) {
      result.append(.init(id: "sleep:" + episode.id.uuidString, kind: .change, at: episode.latest.calculatedAt))
    }
    return result
  }
}
