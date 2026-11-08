import Foundation

enum GalaxySSIHealthCareResearch {
  static let process = UUID()

  struct Authorization: Codable, Equatable, Identifiable {
    var id = UUID()
    let concern: UUID
    let metric: GalaxySSIHealthMetric
    let thread: UUID
    let localPermission: UUID
    let onlinePermission: UUID
    let profileScopeEpoch: UUID?
    let contact: String
    let model: String
    let endpoint: URL
    let destination: String
    let sources: Set<GalaxySSIHealthCareEvidence.PublicSource>
    let authorizedAt: Date
    var handoffVersion: Int?
  }

  enum State: String, Codable {
    case queued, preparing, dispatched, completed, interrupted, failed, sourceUnavailable, cancelled, superseded

    var active: Bool { self == .queued || self == .preparing || self == .dispatched }
  }

  struct Job: Codable, Equatable, Identifiable {
    var id = UUID()
    let authorization: UUID
    let trigger: String
    var revision: Int
    let createdAt: Date
    var state = State.queued
    var owner: UUID?
  }

  struct Ledger: Codable, Equatable {
    var authorizations: [String: Authorization] = [:]
    var jobs: [String: Job] = [:]
    // A bounded authorization is renewed explicitly before its deduplication history can be discarded.
    var seen: [String: Set<String>] = [:]
    var checkpoints: [String: GalaxySSIHealthCareResearchHandoff.Checkpoint]?

    mutating func renew(_ authorization: Authorization) {
      let key = authorization.concern.uuidString
      authorizations[key] = authorization
      jobs.removeValue(forKey: key)
      seen[key] = []
    }

    mutating func revoke(_ concern: UUID) {
      let key = concern.uuidString
      authorizations.removeValue(forKey: key)
      seen.removeValue(forKey: key)
      checkpoints?.removeValue(forKey: key)
      if let job = jobs[key], job.state.active {
        jobs[key]?.state = .cancelled
        jobs[key]?.owner = nil
      }
    }

    mutating func reconcile(_ authorization: Authorization, trigger: String, revision: Int,
                            process: UUID, now: Date) {
      let key = authorization.concern.uuidString
      guard authorizations[key] == authorization else { return }
      if let job = jobs[key], job.authorization == authorization.id, job.trigger == trigger {
        if job.state == .dispatched, job.revision != revision {
          jobs[key]?.state = .superseded
          jobs[key]?.owner = nil
        } else if job.state == .dispatched, job.owner != process {
          jobs[key]?.state = .interrupted
          jobs[key]?.owner = nil
        } else if job.state == .preparing, job.owner != process || job.revision != revision {
          jobs[key]?.state = .queued
          jobs[key]?.owner = nil
        }
        if jobs[key]?.state == .queued { jobs[key]?.revision = revision }
        // Pending proposals and view revisions do not create a new research request.
        return
      }
      let keys = seen[key] ?? []
      guard keys.count < 128, !keys.contains(trigger) else {
        if jobs[key]?.state.active == true {
          jobs[key]?.state = .superseded
          jobs[key]?.owner = nil
        }
        return
      }
      seen[key, default: []].insert(trigger)
      jobs[key] = .init(authorization: authorization.id, trigger: trigger, revision: revision, createdAt: now)
    }

    mutating func transition(_ job: Job, concern: UUID, to state: State, process: UUID) throws {
      let key = concern.uuidString
      guard var current = jobs[key], current == job,
            authorizations[key]?.id == current.authorization else { throw GalaxySSIHealthRecords.Failure.stale }
      let allowed: Bool
      switch (current.state, state) {
      case (.queued, .preparing): allowed = true
      case (.preparing, .queued), (.preparing, .dispatched), (.preparing, .failed),
           (.preparing, .sourceUnavailable),
           (.dispatched, .completed), (.dispatched, .failed), (.dispatched, .interrupted):
        allowed = current.owner == process
      default: allowed = false
      }
      guard allowed else { throw GalaxySSIHealthRecords.Failure.stale }
      current.state = state
      current.owner = state == .preparing || state == .dispatched ? process : nil
      jobs[key] = current
    }
  }

  private struct Trigger: Encodable {
    let assessment: GalaxySSIHealthCare.Assessment
    let context: GalaxySSIHealthCare.Context?
    let target: Int?
    let history: String
    let actionOutcomes: [GalaxySSIHealthCarePlan.AdoptedAction]
    let dueActions: [String]
  }

  static func trigger(_ concern: GalaxySSIHealthCare.Concern, history: String, now: Date,
                      scopedActions: [GalaxySSIHealthCarePlan.AdoptedAction]) throws -> String {
    let actions = scopedActions.sorted { $0.id < $1.id }
    let input = Trigger(assessment: concern.assessment, context: concern.context, target: concern.targetRevision,
      history: history, actionOutcomes: actions.filter { $0.outcome != nil },
      dueActions: actions.filter { $0.outcome == nil && $0.action.dueFrom.map { $0 <= now } == true }.map(\.id))
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return AgentModelLoopRecoveryIdentity.sha256(["health_research": String(decoding: try encoder.encode(input), as: UTF8.self)])
  }
}
