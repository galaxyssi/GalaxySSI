import Foundation

enum GalaxySSIHealthOverviewCare {
  static let previewLimit = 3
  static let candidateLimit = 8

  struct Action: Equatable, Identifiable {
    let concern: UUID
    let metric: GalaxySSIHealthMetric
    let revision: Int
    let actionID: String
    let title: String
    let due: Date
    let overdue: Bool
    var id: String { concern.uuidString + ":" + actionID }

    init?(_ item: GalaxySSIHealthCareAgenda.Item, now: Date) {
      guard item.bucket == .planned, let action = item.action, let planned = item.plannedAt else { return nil }
      concern = item.scope.concern; metric = item.scope.metric; revision = item.revision
      actionID = action.id; title = action.action.description
      let deadline = item.reminder?.requestedAt ?? action.action.dueUntil ?? planned
      overdue = deadline < now
      due = overdue ? deadline : planned
    }
  }

  struct Concern: Equatable, Identifiable {
    let id: UUID
    let metric: GalaxySSIHealthMetric
    let revision: Int
    let stage: GalaxySSIHealthCare.Stage
    let sourceChanged: Bool
  }

  struct Visit: Equatable, Identifiable {
    let concern: UUID
    let metric: GalaxySSIHealthMetric
    let concernRevision: Int
    let entry: GalaxySSIHealthEncounter.Entry
    let journal: GalaxySSIHealthVisitJournal.Entry?
    var id: UUID { entry.id }
    var at: Date? { entry.details.attendedAt ?? entry.details.plannedAt }
  }

  struct Snapshot {
    var permitted = true
    var enabled = false
    var permission: UUID?
    var actionsReady = true
    var actions: [Action] = []
    var upcoming: Action?
    var concerns: [Concern] = []
    var visits: [Visit] = []
  }

  // A cancelled latest encounter must not resurrect an older active visit.
  static func latestVisit(_ entries: [GalaxySSIHealthEncounter.Entry], concern: UUID)
      -> GalaxySSIHealthEncounter.Entry? {
    let latest = entries.filter { $0.concern == concern }.max {
      if $0.revision != $1.revision { return $0.revision < $1.revision }
      if $0.updated != $1.updated { return $0.updated < $1.updated }
      return $0.id.uuidString < $1.id.uuidString
    }
    return latest?.details.state == .cancelled ? nil : latest
  }
}
