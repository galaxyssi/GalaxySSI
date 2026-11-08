import Foundation

enum GalaxySSIHealthCareResearchHandoff {
  typealias Research = GalaxySSIHealthCareResearch

  enum Reason: String, Codable {
    case initialReview = "initial_review", priorUnavailable = "prior_context_unavailable"
    case newMeasurement = "new_measurement", correction = "record_corrected"
    case historyChanged = "measurement_history_changed", contextChanged = "measurement_context_changed"
    case targetChanged = "reviewed_target_changed", actionFeedback = "action_feedback"
    case reviewDue = "review_due", authorizationReview = "authorization_review"
  }

  struct Basis: Codable, Equatable {
    let measurement: GalaxySSIHealthCare.Record?
    let history: String
    let contextDigest: String?
    let targetRevision: Int?
    let due: Set<String>
    let outcomes: [String: String]

    init(_ concern: GalaxySSIHealthCare.Concern, history: String, observedAt: Date,
         actions: [GalaxySSIHealthCarePlan.AdoptedAction]) throws {
      measurement = concern.assessment.record
      self.history = history
      let encoder = JSONEncoder()
      encoder.outputFormatting = .sortedKeys
      func digest<T: Encodable>(_ item: T) throws -> String {
        AgentModelLoopRecoveryIdentity.sha256(["health_review_basis": String(decoding: try encoder.encode(item), as: UTF8.self)])
      }
      contextDigest = try concern.context.map { try digest($0) }
      targetRevision = concern.targetRevision
      due = Set(actions.filter { $0.outcome == nil && $0.action.dueFrom.map { $0 <= observedAt } == true }.map(\.id))
      var outcomeDigests: [String: String] = [:]
      for action in actions {
        if let outcome = action.outcome { outcomeDigests[action.id] = try digest(outcome) }
      }
      outcomes = outcomeDigests
    }
  }

  struct Checkpoint: Codable, Equatable {
    let authorization: Research.Authorization
    let turn: UUID
    let revision: Int
    let startedAt: Date
    let basis: Basis

    func matches(_ current: Research.Authorization, job: Research.Job) -> Bool {
      turn != job.id && startedAt <= job.createdAt && authorization.concern == current.concern &&
        authorization.thread == current.thread && authorization.destination == current.destination &&
        authorization.localPermission == current.localPermission && authorization.onlinePermission == current.onlinePermission &&
        authorization.profileScopeEpoch == current.profileScopeEpoch && authorization.sources == current.sources
    }
  }

  struct Handoff: Equatable {
    let basis: Basis
    let payload: AgentMcpJSONObject
    let plansOnly: Bool
  }

  struct PlanContext {
    let proposal: GalaxySSIHealthCarePlan.Proposal
    let includeDescriptions: Bool
  }

  static func reusable(_ receipt: GalaxySSIHealthCareEvidence.Receipt, turn: UUID, owner: String,
                       authorization: Research.Authorization, job: Research.Job) -> Bool {
    let binding = receipt.binding
    return turn != job.id && binding.turn == turn && binding.owner == owner && binding.thread == authorization.thread &&
      binding.concern == authorization.concern && binding.destination == authorization.destination &&
      binding.carePermission == authorization.localPermission && binding.onlinePermission == authorization.onlinePermission &&
      authorization.sources.contains(where: { $0.url == receipt.url }) &&
      receipt.retrievedAt <= receipt.observedAt && receipt.observedAt <= job.createdAt && !receipt.modelExcerpt.isEmpty
  }

  private static func historicalSource(_ receipt: GalaxySSIHealthCareEvidence.Receipt) -> AgentMcpJSONValue {
    let allowed = receipt.modelExcerpt
    var size = 0
    let excerpt = String(allowed.prefix { character in
      size += String(character).utf8.count
      return size <= 1_000
    })
    return .object(["url": .string(receipt.url.absoluteString), "title": .string(receipt.title),
      "retrieved_at": .string(ISO8601DateFormatter().string(from: receipt.retrievedAt)),
      "content_sha256": .string(receipt.contentHash), "excerpt": .string(excerpt),
      "excerpt_truncated": .bool(receipt.excerptTruncated != false || excerpt != receipt.excerpt),
      "medical_applicability_verified": .bool(false), "usable_for_new_plan": .bool(false)])
  }

  static func make(job: Research.Job, authorization: Research.Authorization, basis: Basis, prior: Checkpoint?,
                   hasEarlierResult: Bool, plan: PlanContext?, recordedPlan: GalaxySSIHealthCarePlan.State?,
                   actionCount: Int, historicalSources: [GalaxySSIHealthCareEvidence.Receipt],
                   essentialContextMissing: Bool, priorityWarning: Bool) -> Handoff {
    let previous = prior.flatMap { $0.matches(authorization, job: job) ? $0 : nil }
    let before = previous?.basis
    var reasons: [Reason] = []
    var newDue = Set<String>()
    var feedback = Set<String>()
    if let before {
      if basis.measurement != before.measurement {
        reasons.append(basis.measurement?.id == before.measurement?.id ? .correction : .newMeasurement)
      } else if basis.history != before.history { reasons.append(.historyChanged) }
      if basis.contextDigest != before.contextDigest { reasons.append(.contextChanged) }
      if basis.targetRevision != before.targetRevision { reasons.append(.targetChanged) }
      feedback = Set(basis.outcomes.keys.filter { basis.outcomes[$0] != before.outcomes[$0] })
      newDue = basis.due.subtracting(before.due)
      if !feedback.isEmpty { reasons.append(.actionFeedback) }
      if !newDue.isEmpty { reasons.append(.reviewDue) }
      if reasons.isEmpty { reasons = [.authorizationReview] }
    } else {
      reasons = [hasEarlierResult || prior != nil ? .priorUnavailable : .initialReview]
    }
    func token(_ action: String) -> String {
      AgentModelLoopRecoveryIdentity.sha256(["discussion": authorization.thread.uuidString, "action": action])
    }
    func tokens(_ actions: Set<String>) -> AgentMcpJSONValue {
      .array(actions.map(token).sorted().map(AgentMcpJSONValue.string))
    }
    let date = ISO8601DateFormatter()
    let elapsedOnly = reasons == [.reviewDue]
    let sources = Array(historicalSources.prefix(8))
    let initialSourceReviewPending = sources.isEmpty && recordedPlan == nil && actionCount == 0
    let changedEvidence = reasons.contains(where: {
      switch $0 {
      case .newMeasurement, .correction, .historyChanged, .contextChanged, .targetChanged, .actionFeedback: return true
      default: return false
      }
    })
    let needsDraft = !priorityWarning && !(initialSourceReviewPending && essentialContextMissing) &&
      (changedEvidence || (recordedPlan == nil && !(elapsedOnly && plan != nil)))
    let actions: [AgentMcpJSONValue] = plan.map { plan in
      let proposal = plan.proposal
      return proposal.draft.actions.filter { proposal.state == .pending || proposal.selected.contains($0.id) }.map { action in
        let id = "\(proposal.id.uuidString):\(action.id)"
        return .object(["action_id": .string(token(id)), "kind": .string(action.kind.rawValue),
          "description": plan.includeDescriptions ? .string(action.description) : .null,
          "due_at": action.dueFrom.map { .string(date.string(from: $0)) } ?? .null,
          "state": .string(basis.outcomes[id] != nil ? "outcome_recorded" : proposal.state.rawValue)])
      }
    } ?? []
    let payload: AgentMcpJSONObject = [
      "observed_at": .string(date.string(from: job.createdAt)), "reasons": .array(reasons.map { .string($0.rawValue) }),
      "comparison_available": .bool(before != nil), "elapsed_time_only": .bool(elapsedOnly),
      "existing_plan": .bool(plan != nil), "existing_plan_actions": .array(actions), "due_action_ids": tokens(basis.due),
      "newly_due_action_ids": before == nil ? .null : tokens(newDue),
      "new_outcome_action_ids": before == nil ? .null : tokens(feedback),
      "research_progress": .object([
        "prior_response_completed": .bool(previous != nil), "source_context_available": .bool(!sources.isEmpty),
        "recorded_plan_exists": .bool(recordedPlan != nil),
        "recorded_plan_state": recordedPlan.map { .string($0.rawValue) } ?? .null,
        "recorded_action_count": .int(Int64(actionCount)), "initial_source_review_pending": .bool(initialSourceReviewPending),
        "essential_context_missing": .bool(essentialContextMissing), "priority_warning": .bool(priorityWarning)
      ]),
      "prior_automatic_source_reads": .array(sources.map(historicalSource)),
      "previous_review": previous.map {
        .object(["revision": .int(Int64($0.revision)), "started_at": .string(date.string(from: $0.startedAt))])
      } ?? .null
    ]
    return .init(basis: basis, payload: payload, plansOnly: needsDraft)
  }
}
