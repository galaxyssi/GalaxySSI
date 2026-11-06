import Foundation

struct AgentCollaborationNativeToolObservation: Codable {
  var runId: String
  var conversationId: String
  var turnId: String
  var memberId: String
  var sourceId: String
  var input: AgentMcpJSONObject
  var result: AgentNativeToolResult
}

struct AgentCollaborationToolEvidenceScope: Codable, Equatable {
  var runId: String
  var conversationId: String
  var turnId: String
  var memberId: String
  var sourceId: String

  var ownershipDigest: String {
    AgentMcpJSONCodec.sha256([
      "run": .string(runId), "conversation": .string(conversationId), "turn": .string(turnId),
      "member": .string(memberId), "source": .string(sourceId)
    ])
  }

  func matchesBrowserInvocation(conversation: String, turn: String) -> Bool {
    !runId.isBlank && !memberId.isBlank && !sourceId.isBlank &&
      !conversationId.isBlank && !turnId.isBlank && conversationId == conversation && turnId == turn
  }
}

struct AgentCollaborationModelAdmission: Codable, Equatable {
  enum Route: String, Codable { case streaming, compatibility }
  let id: UUID
  let scope: AgentCollaborationToolEvidenceScope
  let round: Int
  let provider: ModelStreamProvider
  let requestedModel: String?
  let startedAtMillis: Int64
  var route: Route? = nil
}

struct AgentCollaborationModelSettlement: Codable, Equatable {
  enum State: String, Codable { case completed, failed, cancelled, interrupted }
  let state: State
  let finishedAtMillis: Int64
  let reportedUsage: ModelUsage?
  // A logical stream can include internal HTTP retries; snapshots do not prove total usage.
  let usageComplete: Bool
  let costMicros: Int64?
  var reportedModel: String? = nil
}

struct AgentCollaborationModelAuditEntry: Codable, Equatable {
  let admission: AgentCollaborationModelAdmission
  let settlement: AgentCollaborationModelSettlement?
}

struct AgentCollaborationCloudToolEvidence: Codable, Equatable {
  var scope: AgentCollaborationToolEvidenceScope
  var round: Int
  var call: AssembledToolCall
  var output: String
  var succeeded: Bool
  var startedAtMillis: Int64
  var finishedAtMillis: Int64

  var observedFailure: Bool {
    !succeeded || Self.reportsFailure(output)
  }

  static func reportsFailure(_ output: String) -> Bool {
    guard let fields = try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(output.utf8)) else { return false }
    if fields["success"] == .bool(false) || fields["ok"] == .bool(false) || fields["isError"] == .bool(true) {
      return true
    }
    if ["failed", "error", "cancelled", "timed_out", "unavailable", "rejected",
        "verification_failed"].contains(fields.string("status")) { return true }
    switch fields["error"] {
    case .some(.bool(let value)): return value
    case .some(.int(let value)): return value != 0
    case .some(.double(let value)): return value != 0
    case .some(.string(let value)): return !value.isBlank
    case .some(.object(let value)): return !value.isEmpty
    case .some(.array(let value)): return !value.isEmpty
    default: return false
    }
  }
}

struct AgentCollaborationReadCoverage: Codable, Equatable {
  struct Span: Codable, Equatable {
    var start: Int64
    var end: Int64
  }

  var spans: [Span] = []

  mutating func include(start: Int64, end: Int64) {
    guard start < end else { return }
    var merged: [Span] = []
    for span in (spans + [.init(start: start, end: end)]).sorted(by: { $0.start < $1.start }) {
      if let last = merged.last, last.end >= span.start {
        merged[merged.count - 1].end = max(last.end, span.end)
      } else {
        merged.append(span)
      }
    }
    spans = merged
  }

  var contiguousEnd: Int64 {
    spans.first.flatMap { $0.start == 0 ? $0.end : nil } ?? 0
  }
}

struct AgentCollaborationResearchReference: Codable, Hashable {
  var objectId: String
  var revision: Int64
  var sha256: String

  enum CodingKeys: String, CodingKey {
    case objectId = "object_id"
    case revision, sha256
  }
}

struct AgentCollaborationResearchDraft: Codable {
  enum Kind: String, Codable {
    case innovationOpportunity = "innovation_opportunity"
    case hypothesis, evidence, counterexample, proposal, experiment, artifact, decision, question
    case acceptanceReview = "acceptance_review"
    case failureExperience = "failure_experience"
    case learningAgenda = "learning_agenda"
    case candidate
    case transferStudy = "transfer_study"
    case executableTool = "executable_tool"
    case toolTestPlan = "tool_test_plan"
    case environmentModel = "task_environment_model"
    case actionForecast = "action_forecast"
    case predictionOutcome = "prediction_outcome"
    case numericModelTrial = "numeric_model_trial"
    case experimentPlan = "experiment_plan"
    case experimentResult = "experiment_result"
    case capabilityLesson = "capability_lesson"
    case workflowMethod = "workflow_method"
    case candidateEvent = "candidate_event"
    case teamExchange = "team_exchange"
    case capabilityGap = "capability_gap"
    case innovation
  }

  var validFailureExperience: Bool {
    guard kind == .failureExperience, objectId?.isBlank != false, baseRevision == 0,
          let value = body["failure_experience"]?.objectValue,
          ["observed_issue", "interpretation", "uncertainty", "applies_when", "avoid_repetition", "reconsider_when"]
            .allSatisfy({ value[$0]?.stringValue?.isBlank == false }),
          let options = value["recovery_options"]?.arrayValue, (1...32).contains(options.count)
    else { return false }
    return options.allSatisfy { $0.stringValue?.isBlank == false }
  }
  var id: String
  var objectId: String?
  var baseRevision: Int64
  var kind: Kind
  var title: String
  var body: AgentMcpJSONObject
  var parents: [AgentCollaborationResearchReference]
  var resolves: [AgentCollaborationResearchReference]? = nil
  var observations: [AgentMcpJSONObject]? = nil

  enum CodingKeys: String, CodingKey {
    case id, kind, title, body, parents, resolves, observations
    case objectId = "object_id"
    case baseRevision = "base_revision"
  }
}

enum AgentCollaborationLearningAgendaIntake {
  static func matchesSelection(_ option: AgentMcpJSONObject, work: AgentCollaborationLiveGraph.Work) -> Bool {
    option.string("decision") == "select" && option.string("member") == work.member &&
      option["assignment"]?.stringValue.map { Data($0.utf8) == Data(work.assignment.utf8) } == true &&
      option.string("stage") == work.stage
  }

  static func validates(_ draft: AgentCollaborationResearchDraft, members: Set<String>,
                        gapOptions: (AgentCollaborationResearchReference) throws -> Set<String>?) rethrows -> Bool {
    guard draft.objectId?.isBlank != false, draft.baseRevision == 0,
          let agenda = draft.body["learning_agenda"]?.objectValue,
          hasText(agenda, ["goal_alignment", "resource_reasoning", "selection_reason", "reconsider_when"]),
          let options = agenda["options"]?.arrayValue, (1...32).contains(options.count) else { return false }
    var ranks = Set<Int64>()
    var ids = Set<String>()
    var choices: [String: Set<String>] = [:]
    for entry in options {
      guard let option = entry.objectValue,
            hasText(option, ["id", "gap_option", "current_goal_value", "future_transfer_value", "information_gain",
                             "uncertainty", "tradeoff", "verification", "reconsider_when", "member", "assignment"]),
            ids.insert(option.string("id")).inserted,
            case .int(let rank)? = option["priority"], rank > 0, ranks.insert(rank).inserted,
            members.contains(option.string("member")), option.string("assignment").utf8.count <= 8_000,
            ["select", "defer"].contains(option.string("decision")),
            ["EXECUTE", "EXPLORE", "CHALLENGE", "VERIFY", "REVISE"].contains(option.string("stage")),
            let gap = option["gap"]?.objectValue, Set(gap.keys) == Set(["object_id", "revision", "sha256"]),
            case .int(let revision)? = gap["revision"], revision > 0,
            let estimates = option["resource_estimates"]?.arrayValue, (1...5).contains(estimates.count)
      else { return false }
      let reference = AgentCollaborationResearchReference(objectId: gap.string("object_id"), revision: revision,
        sha256: gap.string("sha256"))
      let choice = option.string("gap_option")
      guard draft.parents.contains(reference), try gapOptions(reference)?.contains(choice) == true,
            choices[reference.sha256, default: []].insert(choice).inserted else { return false }
      var units = Set<String>()
      for estimate in estimates {
        guard let value = estimate.objectValue, hasText(value, ["basis"]),
              ["elapsed_ms", "tokens", "cost_micros", "network_bytes", "tool_calls"].contains(value.string("unit")),
              units.insert(value.string("unit")).inserted else { return false }
        switch (value.string("status"), value["value"]) {
        case ("unknown", nil), ("unknown", .some(.null)): break
        case ("estimated", .some(.int(let number))) where number >= 0: break
        case ("estimated", .some(.double(let number))) where number.isFinite && number >= 0: break
        default: return false
        }
      }
    }
    return true
  }

  private static func hasText(_ object: AgentMcpJSONObject, _ fields: [String]) -> Bool {
    fields.allSatisfy { object[$0]?.stringValue?.isBlank == false }
  }
}

enum AgentCollaborationEvolutionIntake {
  static func validates(_ draft: AgentCollaborationResearchDraft) -> Bool {
    guard let value = draft.body[draft.kind.rawValue]?.objectValue,
          draft.body["content"] == nil || !draft.body.string("content").isBlank else { return false }
    switch draft.kind {
    case .capabilityGap:
      guard ["knowledge", "tool", "method", "verification", "coordination", "environment",
             "authorization", "unknown"].contains(value.string("category")),
            hasText(value, ["symptom", "needed_capability", "chosen_option", "rationale"]),
            let options = records(value, field: "learning_options",
              required: ["action", "expected_gain", "cost", "goal_relevance", "verification"])
      else { return false }
      return options.contains { $0.string("id") == value.string("chosen_option") }
    case .innovation:
      let origin = value.string("origin")
      guard ["gap", "contradiction", "limitation", "transfer", "combination"].contains(origin),
            value.string("novelty_scope") == "not_checked",
            hasText(value, ["hypothesis", "mechanism", "difference", "prior_art", "falsifier", "domain",
                            "applies_when", "risks"]),
            let alternatives = value["alternatives"]?.arrayValue, (1...32).contains(alternatives.count),
            alternatives.allSatisfy({ $0.stringValue?.isBlank == false }),
            records(value, field: "predictions", required: ["statement", "test"]) != nil else { return false }
      let parents = Set(draft.parents.map(\.objectId)).count
      return origin == "combination" ? parents >= 2 : (origin != "transfer" || parents >= 1)
    default:
      return false
    }
  }

  private static func hasText(_ object: AgentMcpJSONObject, _ fields: [String]) -> Bool {
    fields.allSatisfy { !object.string($0).isBlank }
  }

  private static func records(_ object: AgentMcpJSONObject, field: String, required: [String]) -> [AgentMcpJSONObject]? {
    guard let items = object[field]?.arrayValue, (1...32).contains(items.count) else { return nil }
    let values = items.compactMap(\.objectValue)
    guard values.count == items.count, values.allSatisfy({ hasText($0, ["id"] + required) }),
          Set(values.map { $0.string("id") }).count == values.count else { return nil }
    return values
  }
}

enum AgentCollaborationTransferIntake {
  static func validates(_ draft: AgentCollaborationResearchDraft,
                        exactCurrentKind: (AgentCollaborationResearchReference) throws -> String?) rethrows -> Bool {
    guard draft.kind == .transferStudy, draft.objectId?.isBlank != false, draft.baseRevision == 0,
          let study = draft.body["transfer_study"]?.objectValue,
          hasText(study, ["source_domain", "target_domain", "target_task", "abstract_strategy",
                          "proposed_method", "rationale", "risks", "falsifier", "limitations"]),
          ["cross_task", "cross_domain"].contains(study.string("mode")),
          study.string("mode") != "cross_domain" || study.string("source_domain") != study.string("target_domain"),
          let source = reference(study["source"]), draft.parents.contains(source),
          try exactCurrentKind(source) == "failure_experience",
          let alternatives = study["alternatives"]?.arrayValue, (1...32).contains(alternatives.count),
          alternatives.allSatisfy({ $0.stringValue?.isBlank == false }),
          let mappings = study["mappings"]?.arrayValue, (1...32).contains(mappings.count),
          mappings.allSatisfy({ item in
            item.objectValue.map { hasText($0, ["source_element", "target_element", "invariant", "adaptation", "breaks_when"]) } == true
          }),
          let calibration = study["calibration_data"]?.arrayValue, calibration.count <= 32 else { return false }
    var seen = Set<String>()
    for item in calibration {
      guard let artifact = reference(item), draft.parents.contains(artifact), seen.insert(artifact.objectId).inserted,
            try exactCurrentKind(artifact) == "artifact" else { return false }
    }
    return true
  }

  private static func hasText(_ object: AgentMcpJSONObject, _ fields: [String]) -> Bool {
    fields.allSatisfy { object[$0]?.stringValue?.isBlank == false }
  }

  private static func reference(_ raw: AgentMcpJSONValue?) -> AgentCollaborationResearchReference? {
    guard let object = raw?.objectValue, Set(object.keys) == Set(["object_id", "revision", "sha256"]),
          case .int(let revision)? = object["revision"], revision > 0 else { return nil }
    return AgentCollaborationResearchReference(objectId: object.string("object_id"),
      revision: revision, sha256: object.string("sha256"))
  }
}

enum AgentCollaborationOpportunityIntake {
  static func validates(_ draft: AgentCollaborationResearchDraft, goalHash: String,
                        contract: [AgentCollaborationGoalAssessmentPolicy.Criterion],
                        exactKind: (AgentCollaborationResearchReference) throws -> String?) rethrows -> Bool {
    guard draft.kind == .innovationOpportunity, draft.objectId?.isBlank != false, draft.baseRevision == 0,
          let value = draft.body["innovation_opportunity"]?.objectValue,
          value.string("goal_sha256") == goalHash,
          contract.contains(where: { $0.id == value.string("criterion_id") && $0.requirement == value.string("requirement") }),
          hasText(value, ["question", "unmet_need", "expected_benefit", "constraints", "null_hypothesis",
                          "discriminating_test", "uncertainty"]),
          let routes = value["alternative_routes"]?.arrayValue, (1...32).contains(routes.count),
          routes.allSatisfy({ $0.stringValue?.isBlank == false }),
          let drivers = value["drivers"]?.arrayValue, (1...32).contains(drivers.count) else { return false }
    var ids = Set<String>()
    for item in drivers {
      guard let driver = item.objectValue, hasText(driver, ["id", "why", "what_would_change"]),
            ids.insert(driver.string("id")).inserted,
            let sources = driver["sources"]?.arrayValue, (1...32).contains(sources.count) else { return false }
      var kinds = Set<String>()
      for item in sources {
        guard let source = item.objectValue, Set(source.keys) == Set(["object_id", "revision", "sha256"]),
              case .int(let version)? = source["revision"], version > 0 else { return false }
        let reference = AgentCollaborationResearchReference(objectId: source.string("object_id"),
          revision: version, sha256: source.string("sha256"))
        guard draft.parents.contains(reference), let kind = try exactKind(reference),
              ["artifact", "evidence", "counterexample", "proposal", "question", "innovation",
               "capability_gap", "capability_diagnosis", "failure_experience", "transfer_study"].contains(kind)
        else { return false }
        kinds.insert(kind)
      }
      switch driver.string("kind") {
      case "knowledge_gap":
        guard kinds.contains("capability_gap") || kinds.contains("capability_diagnosis") else { return false }
      case "contradiction":
        guard hasText(driver, ["claim_a", "claim_b"]), driver.string("claim_a") != driver.string("claim_b") else { return false }
      case "cross_domain":
        guard kinds.contains("transfer_study") else { return false }
      case "limitation": break
      default: return false
      }
    }
    return true
  }

  private static func hasText(_ object: AgentMcpJSONObject, _ fields: [String]) -> Bool {
    fields.allSatisfy { object[$0]?.stringValue?.isBlank == false }
  }
}

enum AgentCollaborationTeamExchangeIntake {
  static func validates(_ draft: AgentCollaborationResearchDraft, author: String,
                        current: (AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision?) rethrows -> Bool {
    guard draft.kind == .teamExchange, draft.objectId?.isBlank != false, draft.baseRevision == 0,
          let exchange = draft.body["team_exchange"]?.objectValue,
          hasText(exchange, ["issue", "reasoning", "discriminating_test", "uncertainty"]),
          let target = reference(exchange["innovation"]), draft.parents.contains(target),
          let idea = try current(target), idea.draft.kind.rawValue == "innovation" else { return false }
    let person = AgentTeamProgressPolicy.stableCollaborationMemberId(author)
    var contributors = Set<String>()
    var visited = Set<String>()
    var pending = [idea]
    while let item = pending.popLast() {
      guard visited.insert(item.reference.objectId).inserted else { continue }
      guard visited.count <= 128 else { return false }
      contributors.insert(AgentTeamProgressPolicy.stableCollaborationMemberId(item.authorId))
      for parent in item.draft.parents {
        guard let source = try current(parent) else { return false }
        if source.draft.kind.rawValue == "innovation" { pending.append(source) }
      }
    }
    switch exchange.string("operation") {
    case "challenge":
      return !contributors.contains(person) && exchange["challenge"] == nil && hasText(exchange, ["suggested_change"])
    case "response":
      guard contributors.contains(person), let challengeRef = reference(exchange["challenge"]),
            draft.parents.contains(challengeRef), let challenge = try current(challengeRef),
            challenge.draft.kind == .teamExchange,
            !contributors.contains(AgentTeamProgressPolicy.stableCollaborationMemberId(challenge.authorId)),
            let prior = challenge.draft.body["team_exchange"]?.objectValue, prior.string("operation") == "challenge",
            reference(prior["innovation"]) == target,
            ["adopt", "adapt", "reject", "test_needed"].contains(exchange.string("decision")) else { return false }
      return hasText(exchange, ["change_or_reason", "remaining_question"])
    default:
      return false
    }
  }

  private static func reference(_ raw: AgentMcpJSONValue?) -> AgentCollaborationResearchReference? {
    guard let object = raw?.objectValue, Set(object.keys) == Set(["object_id", "revision", "sha256"]),
          case .int(let revision)? = object["revision"], revision > 0 else { return nil }
    return .init(objectId: object.string("object_id"), revision: revision, sha256: object.string("sha256"))
  }

  private static func hasText(_ object: AgentMcpJSONObject, _ fields: [String]) -> Bool {
    fields.allSatisfy { object[$0]?.stringValue?.isBlank == false }
  }
}

enum AgentCollaborationToolRegistration {
  static func parameterSchema(_ spec: AgentMcpJSONObject) -> AgentSkillParameterSchema? {
    guard spec.string("language") == "python",
          hasText(spec, ["name", "purpose", "applies_when", "avoid_when", "environment", "dependencies", "side_effects", "source"]),
          let raw = spec["input_schema"]?.objectValue, raw.string("type") == "object",
          let schema = try? JSONDecoder().decode(AgentSkillParameterSchema.self,
            from: Data(AgentMcpJSONCodec.stringify(raw).utf8)),
          AgentSkillManifestValidator.validatesObjectParameterSchema(schema) else { return nil }
    return schema
  }

  static func validatesTestPlan(_ plan: AgentMcpJSONObject, tool: AgentMcpJSONObject) -> Bool {
    guard let schema = parameterSchema(tool), plan.string("environment") == tool.string("environment"),
          hasText(plan, ["purpose", "coverage_gaps", "oracle_basis"]),
          let cases = plan["cases"]?.arrayValue, (2...32).contains(cases.count) else { return false }
    var ids = Set<String>()
    var coverage = Set<String>()
    for item in cases {
      guard let test = item.objectValue, hasText(test, ["id", "reason"]),
            ids.insert(test.string("id")).inserted, ["target", "edge", "regression"].contains(test.string("purpose")),
            let input = test["input"]?.objectValue, test["expected"] != nil,
            AgentSkillManifestValidator.validateParameters(schema, value: .object(input), path: "$.input").isEmpty
      else { return false }
      coverage.insert(test.string("purpose"))
    }
    return coverage.contains("target") && coverage.contains("regression")
  }

  private static func hasText(_ object: AgentMcpJSONObject, _ fields: [String]) -> Bool {
    fields.allSatisfy { object[$0]?.stringValue?.isBlank == false }
  }
}

enum AgentCollaborationForecastIntake {
  static func actionIds(_ model: AgentMcpJSONObject) -> Set<String>? {
    guard let actions = model["actions"]?.arrayValue, (2...32).contains(actions.count) else { return nil }
    var ids = Set<String>()
    var canDefer = false
    for item in actions {
      guard let action = item.objectValue, hasText(action, ["id", "description", "preconditions",
        "expected_transition", "side_effects", "reversibility", "authorization"]),
        ids.insert(action.string("id")).inserted,
        ["act", "probe", "defer"].contains(action.string("mode")) else { return nil }
      canDefer = canDefer || action.string("mode") == "defer"
    }
    return canDefer ? ids : nil
  }

  static func utilities(_ forecast: AgentMcpJSONObject, actions: Set<String>) -> [String: Double]? {
    guard hasText(forecast, ["work_id", "executor", "horizon", "decision_rationale", "risk_tradeoff",
                            "information_value", "revalidate_before_action", "utility_unit"]),
          actions.contains(forecast.string("selected_action")),
          let events = forecast["events"]?.arrayValue, (1...32).contains(events.count),
          let choices = forecast["choices"]?.arrayValue, choices.count == actions.count else { return nil }
    var utilities: [String: (Double, Double)] = [:]
    for item in events {
      guard let event = item.objectValue, hasText(event, ["id", "meaning", "unit"]),
            event.string("pointer").hasPrefix("/"),
            let expected = event["expected"], expected.objectValue == nil, expected.arrayValue == nil,
            let yes = number(event["utility_if_true"]), let no = number(event["utility_if_false"]),
            utilities.updateValue((yes, no), forKey: event.string("id")) == nil else { return nil }
    }
    var result: [String: Double] = [:]
    for item in choices {
      guard let choice = item.objectValue, hasText(choice, ["reasoning", "uncertainty", "resources", "risk"]),
            choice["expectations"] == nil, actions.contains(choice.string("action_id")),
            let probabilities = choice["probabilities"]?.objectValue,
            Set(probabilities.keys) == Set(utilities.keys) else { return nil }
      var sum = 0.0
      for id in utilities.keys.sorted() {
        guard let outcomes = utilities[id], let p = number(probabilities[id]), (0...1).contains(p) else { return nil }
        sum += p * outcomes.0 + (1 - p) * outcomes.1
      }
      guard sum.isFinite, result.updateValue(sum, forKey: choice.string("action_id")) == nil else { return nil }
    }
    return result
  }

  static func hypothesisInformation(_ forecast: AgentMcpJSONObject,
                                    carriedPosterior: AgentMcpJSONObject? = nil) -> [String: Double]? {
    guard let spec = forecast["hypothesis_test"]?.objectValue,
          (spec["prior_outcome"] != nil) == (carriedPosterior != nil),
          hasText(spec, ["question", "assumptions", "likelihood_basis", "misspecification_check"]),
          let hypotheses = spec["hypotheses"]?.arrayValue, (2...32).contains(hypotheses.count),
          let rawIds = spec["event_ids"]?.arrayValue, (2...32).contains(rawIds.count),
          let matrix = spec["likelihoods"]?.objectValue,
          let choices = forecast["choices"]?.arrayValue, let events = forecast["events"]?.arrayValue else { return nil }
    let ids = rawIds.compactMap(\.strictStringValue)
    guard ids.count == rawIds.count, Set(ids).count == ids.count else { return nil }
    let categorical = events.compactMap(\.objectValue).filter { ids.contains($0.string("id")) }
    guard categorical.count == ids.count, Set(categorical.map { $0.string("id") }) == Set(ids),
          let pointer = categorical.first?.string("pointer"), pointer.hasPrefix("/"),
          pointer.range(of: "~(?![01])", options: .regularExpression) == nil,
          categorical.allSatisfy({ $0.string("pointer") == pointer }) else { return nil }
    var labels: [AgentMcpJSONValue] = []
    for event in categorical {
      guard let value = event["expected"], value.objectValue == nil, value.arrayValue == nil,
            !labels.contains(where: { previous in
              if let a = number(previous), let b = number(value) { return a == b }
              return previous == value
            }) else { return nil }
      labels.append(value)
    }
    var weights: AgentMcpJSONObject = [:]
    for hypothesis in hypotheses {
      guard let row = hypothesis.objectValue, hasText(row, ["id", "claim"]),
            carriedPosterior == nil || row["prior"] == nil,
            let prior = carriedPosterior?[row.string("id")] ?? row["prior"],
            weights.updateValue(prior, forKey: row.string("id")) == nil else { return nil }
    }
    let keys = weights.keys.sorted()
    if let carriedPosterior, Set(carriedPosterior.keys) != Set(keys) { return nil }
    func distribution(_ row: AgentMcpJSONObject, keys: [String]) -> [Double]? {
      guard Set(row.keys) == Set(keys) else { return nil }
      let values = keys.compactMap { number(row[$0]) }
      let total = values.reduce(0, +)
      guard values.count == keys.count, values.allSatisfy({ (0...1).contains($0) }),
            abs(total - 1) <= 1e-12 else { return nil }
      return values.map { $0 / total }
    }
    func entropy(_ p: [Double]) -> Double {
      p.filter { $0 > 0 }.reduce(0) { $0 - $1 * log2($1) }
    }
    guard let prior = distribution(weights, keys: keys) else { return nil }
    var result: [String: Double] = [:]
    for raw in choices {
      guard let choice = raw.objectValue, let rows = matrix[choice.string("action_id")]?.objectValue,
            Set(rows.keys) == Set(keys), let probabilities = choice["probabilities"]?.objectValue else { return nil }
      let distributions = keys.compactMap { rows[$0]?.objectValue.flatMap { distribution($0, keys: ids) } }
      guard distributions.count == keys.count else { return nil }
      var expected = 0.0
      for (index, event) in ids.enumerated() {
        let joint = zip(prior, distributions).map { $0.0 * $0.1[index] }
        let mass = joint.reduce(0, +)
        guard let declared = number(probabilities[event]), abs(declared - mass) <= 1e-12 else { return nil }
        if mass > 0 { expected += mass * entropy(joint.map { $0 / mass }) }
      }
      guard result.updateValue(max(0, entropy(prior) - expected), forKey: choice.string("action_id")) == nil else { return nil }
    }
    return Set(matrix.keys) == Set(result.keys) ? result : nil
  }

  static func hypothesisFeedback(_ forecast: AgentMcpJSONObject, observed: AgentMcpJSONValue?,
                                 withinValidity: Bool, carriedPosterior: AgentMcpJSONObject? = nil) -> AgentMcpJSONObject? {
    guard let spec = forecast["hypothesis_test"]?.objectValue,
          let ids = spec["event_ids"]?.arrayValue?.compactMap(\.strictStringValue),
          let hypotheses = spec["hypotheses"]?.arrayValue?.compactMap(\.objectValue),
          let likelihoods = spec["likelihoods"]?.objectValue?[forecast.string("selected_action")]?.objectValue,
          let events = forecast["events"]?.arrayValue?.compactMap(\.objectValue) else { return nil }
    var feedback: AgentMcpJSONObject = ["state": .string("incomplete_observation"), "posterior": .null,
      "brier_scores": .null,
      "information_gain_bits": .null, "probabilities_are_assumptions": .bool(true), "causality_proven": .bool(false)]
    guard withinValidity else { feedback["state"] = .string("stale_observation"); return feedback }
    guard let observed else { return feedback }
    let matches = events.filter { event in
      guard ids.contains(event.string("id")), let expected = event["expected"] else { return false }
      if let lhs = number(expected), let rhs = number(observed) { return lhs == rhs }
      return expected == observed
    }
    guard matches.count == 1, let event = matches.first?.string("id") else {
      feedback["state"] = .string("unmodeled_outcome")
      return feedback
    }
    if let choice = forecast["choices"]?.arrayValue?.compactMap(\.objectValue).first(where: {
      $0.string("action_id") == forecast.string("selected_action")
    }), let probabilities = choice["probabilities"]?.objectValue {
      var scores: AgentMcpJSONObject = [:]
      for id in ids {
        guard let p = number(probabilities[id]), let score = brierScore(probability: p, occurred: id == event) else { return nil }
        scores[id] = .string(score)
      }
      feedback["brier_scores"] = .object(scores)
    }
    var weights: [(String, Double, Double)] = []
    for hypothesis in hypotheses {
      let id = hypothesis.string("id")
      guard let prior = number(carriedPosterior?[id] ?? hypothesis["prior"]), let row = likelihoods[id]?.objectValue,
            let likelihood = number(row[event]) else { return nil }
      let total = ids.compactMap { number(row[$0]) }.reduce(0, +)
      guard total > 0 else { return nil }
      weights.append((id, prior, prior * (likelihood / total)))
    }
    let priorTotal = weights.reduce(0) { $0 + $1.1 }
    let mass = weights.reduce(0) { $0 + $1.2 }
    guard priorTotal > 0 else { return nil }
    feedback["event_id"] = .string(event)
    feedback["predictive_probability"] = .double(mass / priorTotal)
    guard mass > 0 else { feedback["state"] = .string("contradicted_hypothesis_space"); return feedback }
    var posterior: AgentMcpJSONObject = [:]
    var gain = 0.0
    for (id, prior, weight) in weights {
      let updated = weight / mass
      posterior[id] = .double(updated)
      if updated > 0 { gain += updated * (log2(updated) - log2(prior / priorTotal)) }
    }
    guard gain.isFinite else { return nil }
    feedback["state"] = .string("updated_from_observation")
    feedback["posterior"] = .object(posterior)
    feedback["information_gain_bits"] = .double(max(0, gain))
    return feedback
  }

  static func brierScore(probability: Double, occurred: Bool) -> String? {
    guard probability.isFinite, (0...1).contains(probability) else { return nil }
    if probability == 0 { return occurred ? "1" : "0" }
    if probability == 1 { return occurred ? "0" : "1" }
    let notation = String(probability).split(separator: "e")
    let parts = notation[0].split(separator: ".")
    let exponent = notation.count == 2 ? (Int(notation[1]) ?? 0) : 0
    let scale = (parts.count == 2 ? parts[1].count : 0) - exponent
    let digits = parts.joined().utf8.map { Int($0) - 48 }
    guard scale > 0 else { return nil }
    // Square the decimal numerator without imposing the input type's exponent range on the result.
    var error = Array(digits.reversed())
    while error.last == 0 { error.removeLast() }
    if occurred {
      error += Array(repeating: 0, count: max(0, scale - error.count))
      var borrow = 0
      for index in error.indices {
        let diff = -error[index] - borrow
        borrow = diff < 0 ? 1 : 0
        error[index] = diff + 10 * borrow
      }
    }
    while error.last == 0 { error.removeLast() }
    var square = Array(repeating: 0, count: 2 * scale + 1)
    for i in error.indices {
      for j in error.indices { square[i + j] += error[i] * error[j] }
    }
    for index in 0..<(square.count - 1) {
      square[index + 1] += square[index] / 10
      square[index] %= 10
    }
    let fraction = square.dropLast().reversed().map(String.init).joined()
    let trimmed = String(fraction.reversed().drop(while: { $0 == "0" }).reversed())
    return trimmed.isEmpty ? "0" : "0." + trimmed
  }

  static func sameHypothesisQuestion(_ old: AgentMcpJSONObject, _ new: AgentMcpJSONObject) -> Bool {
    func claims(_ value: AgentMcpJSONObject) -> [String: Data]? {
      guard let rows = value["hypotheses"]?.arrayValue, rows.count >= 2 else { return nil }
      var result: [String: Data] = [:]
      for item in rows {
        guard let row = item.objectValue, hasText(row, ["id", "claim"]),
              result.updateValue(Data(row.string("claim").utf8), forKey: row.string("id")) == nil else { return nil }
      }
      return result
    }
    guard hasText(old, ["question"]), hasText(new, ["question", "conditional_history"]),
          Data(old.string("question").utf8) == Data(new.string("question").utf8),
          let previous = claims(old), let next = claims(new) else { return false }
    return previous == next
  }

  static func hasText(_ object: AgentMcpJSONObject, _ fields: [String]) -> Bool {
    fields.allSatisfy { object[$0]?.stringValue?.isBlank == false }
  }

  private static func number(_ value: AgentMcpJSONValue?) -> Double? {
    switch value {
    case .some(.int(let number)): return Double(number)
    case .some(.double(let number)) where number.isFinite: return number
    default: return nil
    }
  }
}

enum AgentCollaborationExperimentPlanIntake {
  static func validates(_ draft: AgentCollaborationResearchDraft,
                        current: (AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision?) rethrows -> Bool {
    guard draft.kind == .experimentPlan, draft.objectId?.isBlank != false, draft.baseRevision == 0,
          let spec = draft.body["experiment_plan"]?.objectValue,
          ["retention_suite", "transfer_study", "team_comparison", "workflow_comparison"].allSatisfy({ spec[$0] == nil }),
          hasText(spec, ["method", "environment", "budget_unit", "prediction_id"]),
          let pointer = spec["report_pointer"]?.stringValue, pointer.isEmpty || pointer.hasPrefix("/"),
          let limit = number(spec["budget_limit"]), limit > 0,
          let source = spec["source"]?.objectValue, source.string("origin") == "ios_cloud_tool",
          hasText(source, ["tool"]), !source.string("tool").lowercased().contains("recall"),
          source.string("tool") != "research_evidence_audit",
          let idea = reference(spec["innovation"]), let baseline = reference(spec["baseline"]),
          idea.objectId != baseline.objectId, draft.parents.contains(idea), draft.parents.contains(baseline),
          let savedIdea = try current(idea), savedIdea.draft.kind.rawValue == "innovation",
          let savedBaseline = try current(baseline),
          ["proposal", "artifact", "innovation"].contains(savedBaseline.draft.kind.rawValue),
          let predictions = savedIdea.draft.body["innovation"]?.objectValue?["predictions"]?.arrayValue,
          predictions.contains(where: { $0.objectValue?.string("id") == spec.string("prediction_id") }),
          let cases = spec["cases"]?.arrayValue, validatesCases(cases) else { return false }
    for raw in cases {
      if let item = raw.objectValue, item["dataset"] != nil {
        guard let dataset = reference(item["dataset"]), draft.parents.contains(dataset),
              try current(dataset)?.draft.kind == .artifact else { return false }
      }
    }
    return true
  }

  static func validatesCases(_ cases: [AgentMcpJSONValue]) -> Bool {
    guard (1...64).contains(cases.count) else { return false }
    var ids = Set<String>()
    var hasTarget = false
    for raw in cases {
      guard let item = raw.objectValue, hasText(item, ["id", "metric", "prediction"]),
            ids.insert(item.string("id")).inserted,
            ["target", "regression", "transfer", "feasibility"].contains(item.string("purpose")),
            ["maximize", "minimize"].contains(item.string("direction")),
            let gain = number(item["minimum_gain"]), gain >= 0,
            let tolerance = number(item["tolerance"]), tolerance >= 0,
            case .int(let count)? = item["repetitions"], count > 0,
            item.string("purpose") != "feasibility" || number(item["threshold"]) != nil else { return false }
      hasTarget = hasTarget || ["target", "feasibility"].contains(item.string("purpose"))
    }
    return hasTarget
  }

  static func reference(_ value: AgentMcpJSONValue?) -> AgentCollaborationResearchReference? {
    guard let object = value?.objectValue, Set(object.keys) == Set(["object_id", "revision", "sha256"]),
          case .int(let revision)? = object["revision"], revision > 0 else { return nil }
    return .init(objectId: object.string("object_id"), revision: revision, sha256: object.string("sha256"))
  }

  private static func hasText(_ object: AgentMcpJSONObject, _ fields: [String]) -> Bool {
    fields.allSatisfy { object[$0]?.stringValue?.isBlank == false }
  }

  private static func number(_ value: AgentMcpJSONValue?) -> Double? {
    switch value {
    case .some(.int(let number)): return Double(number)
    case .some(.double(let number)) where number.isFinite: return number
    default: return nil
    }
  }

  static func measure(_ reports: [AgentMcpJSONObject], plan: AgentCollaborationResearchRevision)
    -> [AgentCollaborationMeasuredCase]? {
    guard let spec = plan.draft.body["experiment_plan"]?.objectValue,
          let cases = spec["cases"]?.arrayValue, validatesCases(cases),
          let idea = reference(spec["innovation"]), let baseline = reference(spec["baseline"]),
          let budget = number(spec["budget_limit"]), budget > 0 else { return nil }
    let definitions = Dictionary(uniqueKeysWithValues: cases.compactMap(\.objectValue).map { ($0.string("id"), $0) })
    struct Sample: Hashable { var variant: String; var repetition: Int64 }
    var values: [String: [Sample: Double]] = [:]
    for report in reports {
      guard report.string("format") == "galaxyssi.experiment-measurements.v1",
            report.string("plan_sha256") == plan.reference.sha256,
            report.string("environment") == spec.string("environment"),
            report.string("budget_unit") == spec.string("budget_unit"),
            let samples = report["measurements"]?.arrayValue, (1...2_048).contains(samples.count) else { return nil }
      for raw in samples {
        guard let sample = raw.objectValue, let item = definitions[sample.string("case_id")],
              ["baseline", "candidate"].contains(sample.string("variant")),
              sample.string("variant_sha256") == (sample.string("variant") == "baseline" ? baseline.sha256 : idea.sha256),
              sample.string("metric") == item.string("metric"),
              item["dataset"] == nil || sample.string("dataset_sha256") == reference(item["dataset"])?.sha256,
              case .int(let repeatIndex)? = sample["repetition"], repeatIndex > 0,
              case .int(let count)? = item["repetitions"], repeatIndex <= count,
              let used = number(sample["budget_used"]), used >= 0, used <= budget,
              let value = number(sample["value"]) else { return nil }
        let key = Sample(variant: sample.string("variant"), repetition: repeatIndex)
        guard values[item.string("id"), default: [:]].updateValue(value, forKey: key) == nil else { return nil }
      }
    }
    var results: [AgentCollaborationMeasuredCase] = []
    for id in definitions.keys.sorted() {
      guard let item = definitions[id], case .int(let count)? = item["repetitions"] else { return nil }
      let samples = values[id] ?? [:]
      let purpose = item.string("purpose")
      guard count <= Int64(samples.count / 2), Int64(samples.count) == count * 2 else {
        results.append(.init(id: id, purpose: purpose, state: "incomplete"))
        continue
      }
      func mean(_ variant: String) -> Double {
        samples.filter { $0.key.variant == variant }.sorted { $0.key.repetition < $1.key.repetition }
          .reduce(0) { $0 + $1.value / Double(count) }
      }
      let control = mean("baseline")
      let candidate = mean("candidate")
      let maximize = item.string("direction") == "maximize"
      let gain = maximize ? candidate - control : control - candidate
      guard control.isFinite, candidate.isFinite, gain.isFinite else { return nil }
      let passed: Bool
      switch purpose {
      case "regression": passed = gain >= -(number(item["tolerance"]) ?? 0)
      case "feasibility":
        guard let threshold = number(item["threshold"]) else { return nil }
        passed = maximize ? candidate >= threshold : candidate <= threshold
      default: passed = gain > 0 && gain >= (number(item["minimum_gain"]) ?? 0)
      }
      results.append(.init(id: id, purpose: purpose, state: passed ? "passed" : "not_met",
        baseline: control, candidate: candidate, gain: gain))
    }
    return results
  }
}

struct AgentCollaborationMeasuredCase: Codable, Equatable {
  var id: String
  var purpose: String
  var state: String
  var baseline: Double? = nil
  var candidate: Double? = nil
  var gain: Double? = nil

  static func supportsRetention(_ cases: [Self]) -> Bool {
    cases.contains { $0.purpose == "target" } &&
      cases.contains { $0.purpose == "regression" } &&
      cases.allSatisfy { $0.state == "passed" }
  }
}

enum AgentCollaborationWorkflowIntake {
  static func validates(_ method: AgentMcpJSONObject) -> Bool {
    guard ["purpose", "domain", "bottleneck", "change_rationale", "applies_when", "avoid_when", "risks",
           "expected_gain", "falsifier"].allSatisfy({ method[$0]?.stringValue?.isBlank == false }),
          let dimensions = strings(method["dimensions"]), !dimensions.isEmpty,
          dimensions.isSubset(of: ["decomposition", "retrieval", "tool_use", "collaboration", "verification"]),
          let roles = strings(method["roles"]), !roles.isEmpty, strings(method["inputs"]) != nil,
          let steps = method["steps"]?.arrayValue, (1...1_024).contains(steps.count) else { return false }
    var graph: [String: (role: String, dependencies: Set<String>, review: Set<String>)] = [:]
    for raw in steps {
      guard let step = raw.objectValue,
            Set(step.keys).isSubset(of: ["id", "role", "stage", "assignment", "depends_on",
                                        "dependency_policy", "independent_review", "review_targets"]),
            let id = step["id"]?.stringValue, !id.isBlank, id.utf8.count <= 160, graph[id] == nil,
            roles.contains(step.string("role")),
            ["EXECUTE", "EXPLORE", "CHALLENGE", "VERIFY", "REVISE"].contains(step.string("stage")),
            let assignment = step["assignment"]?.stringValue, !assignment.isBlank, assignment.utf8.count <= 8_000,
            let dependencies = strings(step["depends_on"] ?? .array([])), !dependencies.contains(id),
            ["success", "terminal"].contains(step["dependency_policy"]?.stringValue ?? (step["dependency_policy"] == nil ? "success" : "")),
            step["independent_review"] == nil || step["independent_review"] == .bool(true) || step["independent_review"] == .bool(false)
      else { return false }
      let independent = step["independent_review"] == .bool(true)
      let targets = step["review_targets"] == nil ? (independent ? dependencies : []) : strings(step["review_targets"])
      guard let targets, targets.isSubset(of: dependencies),
            independent ? !targets.isEmpty : step["review_targets"] == nil else { return false }
      graph[id] = (step.string("role"), dependencies, targets)
    }
    guard Set(graph.values.map { $0.role }) == roles else { return false }
    var incoming: [String: Int] = [:]
    var dependents: [String: [String]] = [:]
    for (id, step) in graph {
      incoming[id] = step.dependencies.count
      for dependency in step.dependencies {
        guard let source = graph[dependency], !step.review.contains(dependency) || source.role != step.role else { return false }
        dependents[dependency, default: []].append(id)
      }
    }
    var ready = incoming.compactMap { $0.value == 0 ? $0.key : nil }
    var visited = 0
    while let id = ready.popLast() {
      visited += 1
      for dependent in dependents[id] ?? [] {
        incoming[dependent, default: 0] -= 1
        if incoming[dependent] == 0 { ready.append(dependent) }
      }
    }
    return visited == graph.count
  }

  private static func strings(_ value: AgentMcpJSONValue?) -> Set<String>? {
    guard let values = value?.arrayValue else { return nil }
    let strings = values.compactMap(\.stringValue).filter { !$0.isBlank }
    let unique = Set(strings)
    return unique.count == values.count ? unique : nil
  }
}

struct AgentCollaborationResearchEnvelope: Decodable {
  static let wireFormat = "galaxyssi.research-artifact.v1"
  var format: String
  var workspace: [AgentCollaborationResearchDraft]?
  var milestones: [String]?

  static func publication(in raw: String) throws -> [AgentCollaborationResearchDraft]? {
    guard raw.utf8.count <= 256_000, raw.contains(wireFormat) else { return nil }
    let envelope = try JSONDecoder().decode(Self.self, from: Data(raw.utf8))
    guard envelope.format == wireFormat, let workspace = envelope.workspace, !workspace.isEmpty else { return nil }
    return workspace
  }
}

struct AgentCollaborationResearchRevision: Codable {
  static let standardStorageBytes = 256_000
  static let numericReplayStorageBytes = 4_194_304
  static let numericReplayBatchBytes = 8_388_608
  var reference: AgentCollaborationResearchReference
  var previousHash: String?
  var runId: String
  var turnId: String
  var authorId: String
  var sourceId: String
  var draft: AgentCollaborationResearchDraft
  var frozenCloudReads: [AgentCollaborationFrozenCloudRead]? = nil
  var declaredExpectedUtilities: [String: Double]? = nil
  var expectedInformationGainBits: [String: Double]? = nil
  var hypothesisFeedback: AgentMcpJSONObject? = nil
  var carriedHypothesisPosterior: AgentMcpJSONObject? = nil
  var registeredAtMillis: Int64? = nil
  var measuredCases: [AgentCollaborationMeasuredCase]? = nil
  var trialAuthors: [String]? = nil
  var numericReplay: AgentMcpJSONObject? = nil

  var storageBytesLimit: Int {
    draft.kind == .numericModelTrial && numericReplay != nil
      ? Self.numericReplayStorageBytes : Self.standardStorageBytes
  }
}

struct AgentCollaborationFrozenCloudRead: Codable {
  var evidenceId: String
  var sha256: String
  var totalCharacters: Int64
}

struct AgentCollaborationMilestoneRejection: Codable {
  var artifact: Data
  var reason: String
}

struct AgentCollaborationResearchPublication: Codable {
  var requestHash: String
  var references: [AgentCollaborationResearchReference]
  var milestoneId: String? = nil
  var recordedAtMillis: Int64? = nil
}

struct AgentCollaborationPublicationRejection: Codable, Equatable {
  enum Reason: String, Codable {
    case malformedEnvelope = "malformed_envelope"
    case invalidDraft = "invalid_draft"
    case staleBindingOrRevision = "stale_binding_or_revision"
  }

  var scope: AgentCollaborationToolEvidenceScope
  var replyHash: String
  var reason: Reason
}

enum AgentSubagentStatus: String, Codable, CaseIterable, Identifiable {
  case pending = "PENDING"
  case queued = "QUEUED"
  case running = "RUNNING"
  case succeeded = "SUCCEEDED"
  case failed = "FAILED"
  case cancelled = "CANCELLED"
  case skipped = "SKIPPED"
  case interrupted = "INTERRUPTED"

  var id: String { rawValue }

  var isTerminal: Bool {
    [.succeeded, .failed, .cancelled, .skipped, .interrupted].contains(self)
  }
}

enum AgentTeamExecutionState: String, Codable, CaseIterable, Identifiable {
  case queued = "QUEUED"
  case created = "CREATED"
  case running = "RUNNING"
  case waitingResponse = "WAITING_RESPONSE"
  case succeeded = "SUCCEEDED"
  case completedWithFailures = "COMPLETED_WITH_FAILURES"
  case failed = "FAILED"
  case cancelled = "CANCELLED"
  case interrupted = "INTERRUPTED"

  var id: String { rawValue }

  var isTerminal: Bool {
    [.succeeded, .completedWithFailures, .failed, .cancelled, .interrupted].contains(self)
  }

  var deliverable: Bool {
    [.succeeded, .completedWithFailures, .failed, .cancelled].contains(self)
  }
}

struct AgentTeamProgressProjection: Codable, Equatable {
  var state: AgentTeamExecutionState
  var primaryAgentId: String
  var finalOutput: String
  var members: [AgentTeamMemberSnapshot]
  var memberDetailsVisible: Bool
}

enum AgentTeamProgressPolicy {
  static func stableCollaborationMemberId(_ memberId: String) -> String {
    let parts = memberId.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    if let first = parts.first, let rosterId = UUID(uuidString: String(first)),
       parts.count == 1 || ["revise", "recheck"].contains(String(parts[1])) {
      return rosterId.uuidString.lowercased()
    }
    return memberId
  }

  static func currentCollaborationMembers(_ snapshot: AgentTeamExecutionSnapshot) -> [AgentTeamMemberSnapshot] {
    var keys: [String] = []
    var current: [String: AgentTeamMemberSnapshot] = [:]
    for member in snapshot.members where member.deliveryMode != .ignore {
      let key = stableCollaborationMemberId(member.memberId)
      if let previous = current[key] {
        let candidateRank = collaborationStatusRank(member)
        let previousRank = collaborationStatusRank(previous)
        guard candidateRank > previousRank ||
          (candidateRank == previousRank && member.updatedAtMillis >= previous.updatedAtMillis) else { continue }
      } else {
        keys.append(key)
      }
      current[key] = member
    }
    return keys.compactMap { current[$0] }
  }

  private static func collaborationStatusRank(_ member: AgentTeamMemberSnapshot) -> Int {
    if member.status.isTerminal { return 0 }
    if member.status == .running || member.dispatchCheckpoint == .dispatching || member.dispatchCheckpoint == .accepted {
      return 2
    }
    return 1
  }

  static func project(_ snapshot: AgentTeamExecutionSnapshot, expanded: Bool) -> AgentTeamProgressProjection {
    let showMembers = expanded || snapshot.visibilityMode == .visible
    return AgentTeamProgressProjection(
      state: snapshot.state,
      primaryAgentId: snapshot.primaryAgentId,
      finalOutput: snapshot.finalOutput,
      members: showMembers ? snapshot.members : [],
      memberDetailsVisible: showMembers
    )
  }
}

enum AgentTeamMemberDispatchCheckpoint: String, Codable {
  case notStarted = "not_started"
  case dispatching
  case accepted
}

struct AgentTeamMemberSnapshot: Codable, Equatable {
  static let maxErrorCharacters = 1_000

  var agentId: String
  var role: String
  var deliveryMode: AgentDeliveryMode
  var status: AgentSubagentStatus
  var output: String
  var errorMessage: String
  var updatedAtMillis: Int64
  var instanceId: String
  var sourceMessageId: String
  var richOutputJson: String
  var replyContent: String?
  var dispatchCheckpoint: AgentTeamMemberDispatchCheckpoint?
  var dispatchDependencyMemberIds: [String]? = nil
  var dispatchResourceObservation: AgentMcpJSONObject? = nil
  var displayName: String?
  var researchStage: String?
  var executionStartedAtMillis: Int64?

  var memberId: String { instanceId.ifBlank(agentId) }

  init(
    agentId: String,
    role: String = "",
    deliveryMode: AgentDeliveryMode = .observe,
    status: AgentSubagentStatus = .pending,
    output: String = "",
    errorMessage: String = "",
    updatedAtMillis: Int64 = 0,
    instanceId: String = "",
    sourceMessageId: String = "",
    richOutputJson: String = "",
    replyContent: String? = nil,
    dispatchCheckpoint: AgentTeamMemberDispatchCheckpoint? = nil,
    displayName: String? = nil,
    researchStage: String? = nil,
    executionStartedAtMillis: Int64? = nil
  ) {
    self.agentId = agentId
    self.role = role
    self.deliveryMode = deliveryMode
    self.status = status
    self.output = String(output.prefix(AgentConnectorResponse.maxContentCharacters))
    self.errorMessage = String(errorMessage.prefix(Self.maxErrorCharacters))
    self.updatedAtMillis = max(updatedAtMillis, 0)
    self.instanceId = instanceId.ifBlank(agentId)
    self.sourceMessageId = sourceMessageId
    self.richOutputJson = richOutputJson
    self.replyContent = replyContent
    self.dispatchCheckpoint = dispatchCheckpoint
    self.displayName = displayName.map { String($0.prefix(256)) }
    self.researchStage = researchStage
    self.executionStartedAtMillis = executionStartedAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case agentId = "agent_id"
    case role
    case deliveryMode = "delivery_mode"
    case status
    case output
    case errorMessage = "error_message"
    case updatedAtMillis = "updated_at_millis"
    case instanceId = "instance_id"
    case sourceMessageId = "source_message_id"
    case richOutputJson = "rich_output_json"
    case replyContent = "reply_content"
    case dispatchCheckpoint = "dispatch_checkpoint"
    case dispatchDependencyMemberIds = "dispatch_dependency_member_ids"
    case dispatchResourceObservation = "dispatch_resource_observation"
    case displayName = "display_name"
    case researchStage = "research_stage"
    case executionStartedAtMillis = "execution_started_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let agentId = try container.decodeIfPresent(String.self, forKey: .agentId) ?? ""
    self.init(
      agentId: agentId,
      role: try container.decodeIfPresent(String.self, forKey: .role) ?? "",
      deliveryMode: try container.decodeIfPresent(AgentDeliveryMode.self, forKey: .deliveryMode) ?? .observe,
      status: try container.decodeIfPresent(AgentSubagentStatus.self, forKey: .status) ?? .pending,
      output: try container.decodeIfPresent(String.self, forKey: .output) ?? "",
      errorMessage: try container.decodeIfPresent(String.self, forKey: .errorMessage) ?? "",
      updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? 0,
      instanceId: try container.decodeIfPresent(String.self, forKey: .instanceId) ?? agentId,
      sourceMessageId: try container.decodeIfPresent(String.self, forKey: .sourceMessageId) ?? "",
      richOutputJson: try container.decodeIfPresent(String.self, forKey: .richOutputJson) ?? "",
      replyContent: try container.decodeIfPresent(String.self, forKey: .replyContent),
      dispatchCheckpoint: try container.decodeIfPresent(AgentTeamMemberDispatchCheckpoint.self, forKey: .dispatchCheckpoint),
      displayName: try container.decodeIfPresent(String.self, forKey: .displayName),
      researchStage: try container.decodeIfPresent(String.self, forKey: .researchStage),
      executionStartedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .executionStartedAtMillis)
    )
    dispatchDependencyMemberIds = try container.decodeIfPresent([String].self, forKey: .dispatchDependencyMemberIds)
    dispatchResourceObservation = try container.decodeIfPresent(AgentMcpJSONObject.self, forKey: .dispatchResourceObservation)
  }

  func elapsedExecutionMillis(now: Int64, team: AgentTeamExecutionSnapshot) -> Int64? {
    guard let start = executionStartedAtMillis, start > 0 else { return nil }
    let end: Int64? = status.isTerminal ? updatedAtMillis :
      (team.state == .interrupted ? team.interruptedAtMillis : (team.state.isTerminal ? team.executionEndedAtMillis : now))
    guard let end, end >= start else { return nil }
    return end - start
  }
}

struct AgentTeamExecutionSnapshot: Codable, Equatable {
  var supervisorRunId: String
  var teamId: String
  var conversationId: String
  var taskId: String
  var primaryAgentId: String
  var goal: String
  var visibilityMode: AgentTeamVisibilityMode
  var state: AgentTeamExecutionState
  var members: [AgentTeamMemberSnapshot]
  var finalOutput: String
  var createdAtMillis: Int64
  var updatedAtMillis: Int64
  var interruptedAtMillis: Int64
  var primaryInstanceId: String
  var executionStartedAtMillis: Int64?
  var executionEndedAtMillis: Int64?

  var primaryMemberId: String { primaryInstanceId.ifBlank(primaryAgentId) }

  init(
    supervisorRunId: String,
    teamId: String,
    conversationId: String = "",
    taskId: String = "",
    primaryAgentId: String,
    goal: String = "",
    visibilityMode: AgentTeamVisibilityMode = .background,
    state: AgentTeamExecutionState,
    members: [AgentTeamMemberSnapshot] = [],
    finalOutput: String = "",
    createdAtMillis: Int64 = 0,
    updatedAtMillis: Int64 = 0,
    interruptedAtMillis: Int64 = 0,
    primaryInstanceId: String = "",
    executionStartedAtMillis: Int64? = nil,
    executionEndedAtMillis: Int64? = nil
  ) {
    self.supervisorRunId = supervisorRunId
    self.teamId = teamId
    self.conversationId = conversationId
    self.taskId = taskId
    self.primaryAgentId = primaryAgentId
    self.goal = goal
    self.visibilityMode = visibilityMode
    self.state = state
    self.members = members
    self.finalOutput = String(finalOutput.prefix(AgentConnectorResponse.maxContentCharacters))
    self.createdAtMillis = max(createdAtMillis, 0)
    self.updatedAtMillis = max(updatedAtMillis, 0)
    self.interruptedAtMillis = max(interruptedAtMillis, 0)
    self.primaryInstanceId = primaryInstanceId.ifBlank(primaryAgentId)
    self.executionStartedAtMillis = executionStartedAtMillis
    self.executionEndedAtMillis = executionEndedAtMillis
  }

  enum CodingKeys: String, CodingKey {
    case supervisorRunId = "supervisor_run_id"
    case teamId = "team_id"
    case conversationId = "conversation_id"
    case taskId = "task_id"
    case primaryAgentId = "primary_agent_id"
    case goal
    case visibilityMode = "visibility_mode"
    case state
    case members
    case finalOutput = "final_output"
    case createdAtMillis = "created_at_millis"
    case updatedAtMillis = "updated_at_millis"
    case interruptedAtMillis = "interrupted_at_millis"
    case primaryInstanceId = "primary_instance_id"
    case executionStartedAtMillis = "execution_started_at_millis"
    case executionEndedAtMillis = "execution_ended_at_millis"
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      supervisorRunId: try container.decodeIfPresent(String.self, forKey: .supervisorRunId) ?? "",
      teamId: try container.decodeIfPresent(String.self, forKey: .teamId) ?? "",
      conversationId: try container.decodeIfPresent(String.self, forKey: .conversationId) ?? "",
      taskId: try container.decodeIfPresent(String.self, forKey: .taskId) ?? "",
      primaryAgentId: try container.decodeIfPresent(String.self, forKey: .primaryAgentId) ?? "",
      goal: try container.decodeIfPresent(String.self, forKey: .goal) ?? "",
      visibilityMode: try container.decodeIfPresent(AgentTeamVisibilityMode.self, forKey: .visibilityMode) ?? .background,
      state: try container.decodeIfPresent(AgentTeamExecutionState.self, forKey: .state) ?? .queued,
      members: try container.decodeIfPresent([AgentTeamMemberSnapshot].self, forKey: .members) ?? [],
      finalOutput: try container.decodeIfPresent(String.self, forKey: .finalOutput) ?? "",
      createdAtMillis: try container.decodeIfPresent(Int64.self, forKey: .createdAtMillis) ?? 0,
      updatedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .updatedAtMillis) ?? 0,
      interruptedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .interruptedAtMillis) ?? 0,
      primaryInstanceId: try container.decodeIfPresent(String.self, forKey: .primaryInstanceId) ??
        (try container.decodeIfPresent(String.self, forKey: .primaryAgentId) ?? ""),
      executionStartedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .executionStartedAtMillis),
      executionEndedAtMillis: try container.decodeIfPresent(Int64.self, forKey: .executionEndedAtMillis)
    )
  }

  var primaryRichOutput: String {
    guard let primary = members.first(where: { $0.memberId == primaryMemberId && $0.deliveryMode == .respond }),
          primary.status == .succeeded else { return "" }
    return AgentTeamArtifactOutput.bounded(primary.richOutputJson)
  }

  var hasSuccessfulOutput: Bool {
    [.succeeded, .completedWithFailures].contains(state) &&
      (!finalOutput.isBlank || AgentTeamArtifactOutput.hasArtifacts(primaryRichOutput))
  }

  func elapsedExecutionMillis(now: Int64) -> Int64? {
    guard let start = executionStartedAtMillis, start > 0 else { return nil }
    let end: Int64
    if let recordedEnd = executionEndedAtMillis {
      end = recordedEnd
    } else if state == .interrupted {
      end = interruptedAtMillis
    } else if state == .running || state == .waitingResponse {
      end = now
    } else {
      return nil
    }
    return end >= start ? end - start : nil
  }
}

enum AgentTeamArtifactOutput {
  static func hasArtifacts(_ raw: String) -> Bool {
    AgentRichContentCodec.decode(raw).contains(where: \.isArtifactBlock)
  }

  static func bounded(_ raw: String) -> String {
    let blocks = AgentRichContentCodec.decode(raw)
    let encoded = AgentRichContentCodec.encode(blocks)
    let limit = AgentConnectorResponse.maxRichOutputCharacters
    if encoded.utf8.count <= limit { return encoded }
    var included: [AgentRichBlock] = []
    for block in blocks where block.isArtifactBlock {
      let candidate = AgentRichContentCodec.encode(included + [block])
      if !candidate.isEmpty && candidate.utf8.count <= limit { included.append(block) }
    }
    return AgentRichContentCodec.encode(included)
  }

  static func appendingArtifacts(_ raw: String, to reply: String, richOutput: String) -> String {
    var blocks = AgentRichContentCodec.presentationBlocks(content: reply, richOutputJson: richOutput)
    var seen = Set(blocks.filter(\.isArtifactBlock).map { $0.artifactIdentity() })
    for artifact in AgentRichContentCodec.decode(raw) where artifact.isArtifactBlock {
      if seen.insert(artifact.artifactIdentity()).inserted { blocks.append(artifact) }
    }
    return AgentRichContentCodec.encode(blocks).ifBlank(richOutput)
  }
}

enum AgentSavedTeamReplyPolicy {
  static func reconcileRecoveryWait(_ task: AgentTaskRecord, runId: String, cancelled: Bool,
                                    verification: String, now: Int64) -> AgentTaskRecord? {
    guard !runId.isBlank,
          (task.phase == .executing && (task.teamRecoveryRunId == nil || task.teamRecoveryRunId == runId)) ||
            (task.phase == .paused && task.teamRecoveryRunId == runId) else { return nil }
    var recovered = task
    recovered.phase = cancelled ? .cancelled : .waitingResponse
    recovered.blocked = false
    recovered.teamRecoveryRunId = cancelled ? nil : runId
    recovered.verification = verification
    recovered.executionLog.append("Agent team recovery: retained original team " + runId)
    recovered.updatedAtMillis = max(task.updatedAtMillis, now)
    return recovered
  }

  static func canContinueAutomatically(_ task: AgentTaskRecord) -> Bool {
    guard task.phase == .paused, task.teamRecoveryRunId == nil,
          let plan = task.activePlan, plan.executionMode == .autoComplete,
          !plan.confirmationRequired else { return false }
    let runnable = AgentToolCoordination.runnableActions(plan)
    return !runnable.isEmpty && runnable.allSatisfy { $0.status == .proposed }
  }

  static func settleParent(_ parent: AgentTaskRecord, saved: AgentTeamExecutionSnapshot,
                           failureText: String, now: Int64) -> AgentTaskRecord? {
    guard saved.state.deliverable, parent.result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          (parent.phase == .waitingResponse && (parent.teamRecoveryRunId == nil || parent.teamRecoveryRunId == saved.supervisorRunId)) ||
            (parent.phase == .paused && parent.teamRecoveryRunId == saved.supervisorRunId),
          parent.taskId == saved.taskId, parent.sessionId == saved.conversationId,
          saved.createdAtMillis >= parent.createdAtMillis,
          var plan = parent.activePlan else { return nil }
    let matchingIndices = plan.actions.indices.filter { index in
      plan.actions[index].kind == .callConnector &&
        AgentTeamDispatchSpecCodec.decode(plan.actions[index].parameters[agentTeamSpecParameter] ?? "")?.supervisorRunId == saved.supervisorRunId
    }
    guard matchingIndices.count == 1, let index = matchingIndices.first,
          plan.actions[index].status != .completed,
          let spec = AgentTeamDispatchSpecCodec.decode(plan.actions[index].parameters[agentTeamSpecParameter] ?? ""),
          spec.supervisorRunId == saved.supervisorRunId, spec.definition.teamId == saved.teamId,
          spec.definition.primaryMemberId == saved.primaryMemberId,
          spec.definition.members.count == saved.members.count,
          spec.definition.members.allSatisfy({ expected in
            saved.members.contains { $0.memberId == expected.memberId && $0.agentId == expected.agentId }
          }) else { return nil }
    let success = saved.hasSuccessfulOutput
    var result = parent
    result.phase = saved.state == .cancelled ? .cancelled : (success ? .completed : .failed)
    result.result = success ? saved.finalOutput.ifBlank("Agent team returned attachments.") : failureText
    result.teamResultRichOutput = success && !saved.primaryRichOutput.isEmpty ? saved.primaryRichOutput : nil
    result.blocked = false
    result.teamRecoveryRunId = nil
    result.pendingAction = nil
    result.pendingActions = []
    plan.actions[index].status = success ? .completed : .failed
    plan.actions[index].result = result.result
    if success && !plan.actions.allSatisfy({ $0.status == .completed }) {
      result.nativeActionResults = Array((result.nativeActionResults + [String(result.result.prefix(600))]).suffix(8))
      result.phase = .paused
      result.pendingActions = AgentToolCoordination.runnableActions(plan)
      result.pendingAction = result.pendingActions.first
    }
    result.activePlan = plan
    result.planContext = AgentTaskPlanContext(plan: plan)
    result.updatedAtMillis = max(now, parent.updatedAtMillis)
    return result
  }

  static func apply(to saved: AgentTeamExecutionSnapshot, source: String, conversation: String,
                    turn: String, task: String, contact: String, content: String, richOutputJson: String = "",
                    success: Bool, now: Int64) -> AgentTeamExecutionSnapshot? {
    guard (!saved.state.isTerminal || saved.state == .interrupted), !source.isEmpty,
          saved.conversationId == conversation, saved.taskId == turn, task == source,
          let index = saved.members.firstIndex(where: {
            $0.sourceMessageId == source && $0.agentId == contact &&
              (!$0.status.isTerminal || (saved.state == .interrupted && $0.status == .interrupted))
          }),
          !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            (success && (saved.members[index].deliveryMode == .observe || AgentTeamArtifactOutput.hasArtifacts(richOutputJson)))
          else { return nil }
    var result = saved
    result.members[index].status = success ? .succeeded : .failed
    result.members[index].output = success ? String(content.prefix(AgentConnectorResponse.maxContentCharacters)) : ""
    result.members[index].errorMessage = success ? "" : String(content.prefix(AgentTeamMemberSnapshot.maxErrorCharacters))
    result.members[index].updatedAtMillis = now
    result.members[index].richOutputJson = richOutputJson
    result.members[index].replyContent = content
    result.updatedAtMillis = max(saved.updatedAtMillis, now)
    if result.members[index].memberId == saved.primaryMemberId && !success {
      result.state = .failed
    } else if result.members.allSatisfy({ $0.status.isTerminal && $0.status != .interrupted }),
       let primary = result.members.first(where: { $0.memberId == saved.primaryMemberId }) {
      result.finalOutput = primary.output
      if primary.status == .succeeded &&
        (!primary.output.isBlank || AgentTeamArtifactOutput.hasArtifacts(primary.richOutputJson)) {
        result.state = result.members.contains(where: { $0.status != .succeeded }) ? .completedWithFailures : .succeeded
      } else { result.state = .failed }
    }
    return result
  }
}

protocol AgentTeamCompletionSink: AnyObject {
  @discardableResult
  func publish(_ snapshot: AgentTeamExecutionSnapshot) -> Bool
  func remove(supervisorRunId: String)
  func clear()
}

extension AgentTeamCompletionSink {
  func remove(supervisorRunId: String) {}
  func clear() {}
}

final class AgentConnectorTeamCompletionSink: AgentTeamCompletionSink {
  static let maxErrorCharacters = AgentTeamMemberSnapshot.maxErrorCharacters

  private let responseStore: AgentConnectorResponseSink
  private let ledger: AgentTeamCompletionDeliveryLedger
  private let historyStore: AgentTeamExecutionHistoryStore
  private let nowMillis: () -> Int64

  init(
    responseStore: AgentConnectorResponseSink,
    ledger: AgentTeamCompletionDeliveryLedger = AgentTeamCompletionDeliveryLedger(),
    historyStore: AgentTeamExecutionHistoryStore = .shared,
    nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) }
  ) {
    self.responseStore = responseStore
    self.ledger = ledger
    self.historyStore = historyStore
    self.nowMillis = nowMillis
  }

  @discardableResult
  func publish(_ snapshot: AgentTeamExecutionSnapshot) -> Bool {
    guard historyStore.upsert(snapshot) else { return false }
    guard snapshot.state.deliverable,
      !ledger.contains(snapshot.supervisorRunId) else {
      return false
    }
    let output = snapshot.finalOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    let successful = snapshot.hasSuccessfulOutput
    let content: String
    if successful {
      content = output.ifBlank("Agent team returned attachments.")
    } else if let error = snapshot.members.map(\.errorMessage).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
      content = "Agent team failed: \(String(error.prefix(Self.maxErrorCharacters)))"
    } else {
      content = "Agent team failed."
    }
    responseStore.publish(AgentConnectorResponse(
      sourceMessageId: AgentTeamDispatchIds.sourceMessageId(supervisorRunId: snapshot.supervisorRunId),
      contactId: AgentTeamDispatchIds.responseContactId(teamId: snapshot.teamId),
      content: content,
      conversationId: snapshot.conversationId,
      turnId: snapshot.taskId,
      taskId: snapshot.taskId,
      success: successful,
      richOutputJson: successful ? snapshot.primaryRichOutput : "",
      receivedAtMillis: max(snapshot.updatedAtMillis, nowMillis())
    ))
    ledger.mark(snapshot.supervisorRunId)
    return true
  }

  func remove(supervisorRunId: String) {
    ledger.remove(supervisorRunId)
    historyStore.remove(supervisorRunId: supervisorRunId)
  }

  func clear() {
    ledger.clear()
    historyStore.clear()
  }
}

final class AgentTeamCompletionDeliveryLedger {
  private let lock = NSRecursiveLock()
  private var delivered: [String]
  private let maximumRecords: Int

  init(delivered: [String] = [], maxRecords: Int = 512) {
    let limit = Swift.max(maxRecords, 1)
    let cleaned = delivered
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    self.delivered = Self.stableDistinct(cleaned)
      .suffix(limit)
      .map { $0 }
    self.maximumRecords = limit
  }

  private static func stableDistinct(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
  }

  func contains(_ supervisorRunId: String) -> Bool {
    let clean = supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
    lock.lock()
    defer { lock.unlock() }
    return delivered.contains(clean)
  }

  func mark(_ supervisorRunId: String) {
    let clean = supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      return
    }
    lock.lock()
    defer { lock.unlock() }
    delivered = delivered.filter { $0 != clean } + [clean]
    if delivered.count > maximumRecords {
      delivered = Array(delivered.suffix(maximumRecords))
    }
  }

  func remove(_ supervisorRunId: String) {
    let clean = supervisorRunId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else {
      return
    }
    lock.lock()
    defer { lock.unlock() }
    delivered.removeAll { $0 == clean }
  }

  func clear() {
    lock.lock()
    defer { lock.unlock() }
    delivered.removeAll()
  }

  func snapshot() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return delivered
  }
}
