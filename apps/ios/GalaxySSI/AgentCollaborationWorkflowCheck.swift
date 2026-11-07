import Foundation

enum AgentCollaborationWorkflowCheck {
  static let mode = "workflow_check"
  static let kind = "workflow_selection_rule"
  static let trust = "host_predicate_check_of_declared_inputs_not_method_validation"
  static let instructions = "Use workflow_check with exact workflow_selection_rule object_id, revision, sha256 and compact inputs. " +
    "Inputs may be partial and are declared, not verified. Keep inputs and the rule unchanged while following next_offset. " +
    "Unknown conditions may or may not affect selection. This does not execute work or certify either method."

  static func isCall(_ tool: String, _ input: AgentMcpJSONObject) -> Bool {
    tool == CloudModelStreamMutableConversation.collaborationRecallName && input["mode"] == .string(mode)
  }

  // Read only the host-authored comparison metadata, never a similarly named field in the model's draft.
  struct StoredPlan: Decodable {
    struct Comparison: Codable {
      let baseline: AgentCollaborationResearchReference
      let candidate: AgentCollaborationResearchReference
      let dataset: AgentCollaborationResearchReference
    }
    let workflowComparison: Comparison?
  }

  struct Rule {
    let comparison: StoredPlan.Comparison
    let inputNames: Set<String>
    let whenAll: [AgentCollaborationWorkflowConditions.Condition]
    let unlessAny: [AgentCollaborationWorkflowConditions.Condition]
  }

  static func current(_ ref: AgentCollaborationResearchReference, scope: AgentCollaborationToolEvidenceScope,
                      database: AgentTeamHistoryDatabase, changed: Set<String> = []) throws -> AgentCollaborationResearchRevision? {
    guard valid(ref), !changed.contains(ref.objectId),
          let record = try database.researchRecord(AgentCollaborationResearchRevision.self,
            conversationId: scope.conversationId, key: "object:" + ref.objectId),
          record.reference == ref,
          record.turnId != scope.turnId || (record.runId == scope.runId && record.authorId == scope.memberId) else { return nil }
    return record
  }

  static func rule(_ draft: AgentCollaborationResearchDraft, scope: AgentCollaborationToolEvidenceScope,
                   database: AgentTeamHistoryDatabase, changed: Set<String> = []) throws -> Rule {
    let reference = AgentCollaborationExperimentPlanIntake.reference
    var loaded: [String: AgentCollaborationResearchRevision] = [:]
    func exact(_ ref: AgentCollaborationResearchReference) throws -> AgentCollaborationResearchRevision? {
      if let row = loaded[ref.objectId] { return row.reference == ref ? row : nil }
      guard loaded.count < 128, let row = try current(ref, scope: scope, database: database, changed: changed) else { return nil }
      loaded[ref.objectId] = row
      return row
    }
    guard draft.kind == .workflowSelectionRule, draft.objectId?.isBlank != false, draft.baseRevision == 0,
          draft.observations?.isEmpty != false,
          let value = draft.body[kind]?.objectValue,
          draft.parents.count <= 128,
          ["purpose", "domain", "condition_basis", "limitations", "prospective_test"].allSatisfy({
            value[$0]?.strictStringValue?.isBlank == false
          }), let lessonRef = reference(value["lesson"]), draft.parents.contains(lessonRef),
          let lesson = try exact(lessonRef), lesson.draft.kind == .capabilityLesson,
          let decision = lesson.draft.body["capability_lesson"]?.objectValue, decision["decision"] == .string("retain"),
          let resultRef = reference(decision["result"]), lesson.draft.parents.contains(resultRef),
          let result = try exact(resultRef), result.draft.kind == .experimentResult,
          let cases = result.measuredCases, AgentCollaborationMeasuredCase.supportsRetention(cases),
          let originalReads = result.frozenCloudReads, !originalReads.isEmpty, let retainedReads = lesson.frozenCloudReads,
          originalReads.allSatisfy({ original in retainedReads.contains {
            $0.evidenceId == original.evidenceId && $0.sha256 == original.sha256 && $0.totalCharacters == original.totalCharacters
          } }),
          let authors = result.trialAuthors, !authors.isEmpty,
          !authors.map(AgentTeamProgressPolicy.stableCollaborationMemberId)
            .contains(AgentTeamProgressPolicy.stableCollaborationMemberId(lesson.authorId)),
          let planRef = reference(result.draft.body["experiment_result"]?.objectValue?["plan"]),
          result.draft.parents.contains(planRef),
          let plan = try exact(planRef), plan.draft.kind == .experimentPlan, plan.registeredAtMillis != nil,
          let stored = try database.researchRecord(StoredPlan.self, conversationId: scope.conversationId,
            key: "object:" + planRef.objectId, revision: planRef.revision),
          let comparison = stored.workflowComparison, comparison.baseline != comparison.candidate,
          plan.draft.parents.contains(comparison.dataset), try exact(comparison.dataset)?.draft.kind == .artifact,
          let baseline = try exact(comparison.baseline), let candidate = try exact(comparison.candidate),
          baseline.draft.kind == .workflowMethod, candidate.draft.kind == .workflowMethod,
          let base = baseline.draft.body["workflow_method"]?.objectValue,
          let next = candidate.draft.body["workflow_method"]?.objectValue,
          base["domain"] == value["domain"], next["domain"] == value["domain"],
          let inputs = names(base["inputs"]), names(next["inputs"]) == inputs,
          let roles = names(base["roles"]), !roles.isEmpty, names(next["roles"]) == roles
    else { throw AgentTeamHistoryDatabase.Failure.stale }

    var visited: [String: AgentCollaborationResearchReference] = [:]
    var pending = try draft.parents.map { ref -> AgentCollaborationResearchRevision in
      guard let parent = try exact(ref) else { throw AgentTeamHistoryDatabase.Failure.stale }
      return parent
    }
    while let item = pending.popLast() {
      if let prior = visited[item.reference.objectId] {
        guard prior == item.reference else { throw AgentTeamHistoryDatabase.Failure.stale }
        continue
      }
      visited[item.reference.objectId] = item.reference
      guard visited.count <= 128, item.draft.parents.count <= 128 else { throw AgentTeamHistoryDatabase.Failure.stale }
      for ref in item.draft.parents {
        guard let parent = try exact(ref) else { throw AgentTeamHistoryDatabase.Failure.stale }
        pending.append(parent)
      }
    }
    guard visited[comparison.baseline.objectId] == comparison.baseline,
          visited[comparison.candidate.objectId] == comparison.candidate else { throw AgentTeamHistoryDatabase.Failure.stale }

    func conditions(_ key: String) throws -> [AgentCollaborationWorkflowConditions.Condition] {
      guard let rows = value[key]?.arrayValue, rows.count <= 64 else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      let parsed = rows.compactMap { AgentCollaborationWorkflowConditions.Condition($0, inputNames: inputs) }
      guard parsed.count == rows.count else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      return parsed
    }
    let required = try conditions("when_all"), excluded = try conditions("unless_any")
    let ids = (required + excluded).map(\.id)
    guard !required.isEmpty, Set(ids).count == ids.count else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    return Rule(comparison: comparison, inputNames: inputs, whenAll: required, unlessAny: excluded)
  }

  static func inspect(_ input: AgentMcpJSONObject, scope: AgentCollaborationToolEvidenceScope,
                      database: AgentTeamHistoryDatabase) throws -> AgentMcpJSONObject {
    let required: Set<String> = ["mode", "object_id", "revision", "sha256", "inputs"]
    let selector = input.filter { ["object_id", "revision", "sha256"].contains($0.key) }
    guard input["mode"] == .string(mode), required.isSubset(of: input.keys),
          Set(input.keys).isSubset(of: required.union(["offset"])),
          AgentMcpJSONCodec.stringify(input).utf16.count <= 4_096,
          let ref = AgentCollaborationExperimentPlanIntake.reference(.object(selector)), valid(ref),
          let values = input["inputs"]?.objectValue, case .int(let offset) = input["offset"] ?? .int(0), offset >= 0
    else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    guard let saved = try current(ref, scope: scope, database: database),
          saved.draft.kind == .workflowSelectionRule else { throw AgentTeamHistoryDatabase.Failure.stale }
    let rule = try rule(saved.draft, scope: scope, database: database)
    guard Set(values.keys).isSubset(of: rule.inputNames) else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    return try page(report(rule, reference: ref, values: values), offset: offset)
  }

  static func report(_ rule: Rule, reference ref: AgentCollaborationResearchReference,
                     values: AgentMcpJSONObject) -> AgentMcpJSONObject {
    let positive = rule.whenAll.map { $0.evaluate(values) }, negative = rule.unlessAny.map { $0.evaluate(values) }
    let unknown = (positive + negative).filter { $0.state == "unknown" }
    let excluded = negative.filter { $0.state == "matched" }
    let blockers = positive.filter { $0.state == "not_matched" } + excluded
    let candidate = unknown.isEmpty && blockers.isEmpty
    let mayChange = !unknown.isEmpty && blockers.isEmpty
    let reason = !excluded.isEmpty ? "countercondition_matched" : !unknown.isEmpty ? "insufficient_condition_data" :
      candidate ? "applicability_matched" : "outside_applicability"
    let identity = reference(ref)
    let baseline = reference(rule.comparison.baseline), alternative = reference(rule.comparison.candidate)
    return [
      "rule": .object(identity), "baseline_method": .object(baseline), "candidate_method": .object(alternative),
      "selection": .object(["rule": .object(identity), "variant": .string(candidate ? "candidate" : "baseline"),
        "reason": .string(reason), "method": .object(candidate ? alternative : baseline),
        "when_all": .array(positive.map(\.selection)), "unless_any": .array(negative.map(\.selection)),
        "input_evidence": .string("declared_workflow_inputs_not_independently_verified"),
        "quality_effect": .null, "causality_proven": .bool(false)]),
      "when_all": .array(positive.map { $0.report(mayChange: mayChange) }),
      "unless_any": .array(negative.map { $0.report(mayChange: mayChange) }),
      "unknown_conditions": .array(unknown.map { .string($0.condition.id) }),
      "known_blockers": .array(blockers.map { .string($0.condition.id) }), "unknowns_may_change_selection": .bool(mayChange),
      "decision_scope": .string("Known predicates only; no joint satisfiability, probe cost or information-value estimate"),
      "input_evidence": .string("declared_unverified_not_a_tool_observation"), "lineage": .string("current_at_read"),
      "baseline_applicability_verified": .bool(false), "quality_effect": .null,
      "executes_work": .bool(false), "grants_permissions": .bool(false),
      "next_action": .string("Inspect original evidence, acquire relevant data, revise the rule or use alternatives. Missing data does not make the baseline suitable.")
    ]
  }

  static func reference(_ value: AgentCollaborationResearchReference) -> AgentMcpJSONObject {
    ["object_id": .string(value.objectId), "revision": .int(value.revision), "sha256": .string(value.sha256)]
  }

  static func cloudSchema(_ original: [String: Any]) -> [String: Any] {
    guard var properties = original["properties"] as? [String: Any],
          var selector = properties["mode"] as? [String: Any], var modes = selector["enum"] as? [String] else { return original }
    if !modes.contains(mode) { modes.append(mode) }
    selector["enum"] = modes
    properties["mode"] = selector
    properties["inputs"] = ["type": "object", "description": instructions]
    var schema = original
    schema["properties"] = properties
    return schema
  }

  static func nativeTool(_ original: AgentNativeToolExecutableDefinition,
                         read: @escaping (AgentMcpJSONObject) -> AgentMcpJSONObject?) -> AgentNativeToolExecutableDefinition {
    var tool = original
    var schema = tool.definition.descriptor.inputSchema
    guard var properties = schema["properties"]?.objectValue,
          var selector = properties["mode"]?.objectValue, var modes = selector["enum"]?.arrayValue else { return original }
    if !modes.contains(.string(mode)) { modes.append(.string(mode)) }
    selector["enum"] = .array(modes)
    properties["mode"] = .object(selector)
    properties["inputs"] = .object(["type": .string("object"), "description": .string(instructions)])
    schema["properties"] = .object(properties)
    tool.definition.descriptor.inputSchema = schema
    tool.executor = { invocation in
      guard invocation.input["mode"] == .string(mode) else { return try original.executor(invocation) }
      try invocation.checkpoint()
      guard let page = read(invocation.input) else {
        return .failure(code: "workflow_check_unavailable", message: "The scoped workflow check is unavailable")
      }
      return .success(output: page)
    }
    return tool
  }

  private static func valid(_ value: AgentCollaborationResearchReference) -> Bool {
    value.revision > 0 && [value.objectId, value.sha256].allSatisfy { digest in
      digest.utf8.count == 64 && digest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
  }

  private static func names(_ raw: AgentMcpJSONValue?) -> Set<String>? {
    guard let rows = raw?.arrayValue else { return nil }
    let values = Set(rows.compactMap(\.strictStringValue).filter { !$0.isBlank })
    return values.count == rows.count ? values : nil
  }

  private static func page(_ report: AgentMcpJSONObject, offset: Int64) throws -> AgentMcpJSONObject {
    let units = Array(AgentMcpJSONCodec.stringify(report).utf16)
    guard offset <= Int64(units.count) else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    let start = Int(offset)
    func isTrailingSurrogate(_ index: Int) -> Bool {
      index < units.count && (0xDC00...0xDFFF).contains(units[index])
    }
    guard !isTrailingSurrogate(start) else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    var end = min(start + 8_000, units.count)
    if isTrailingSurrogate(end) { end -= 1 }
    return ["status": .string("returned"), "content": .string(String(decoding: units[start..<end], as: UTF16.self)),
      "total_characters": .int(Int64(units.count)), "next_offset": end < units.count ? .int(Int64(end)) : .null,
      "offset_unit": .string("utf16_code_units"), "trust": .string(trust)]
  }
}
