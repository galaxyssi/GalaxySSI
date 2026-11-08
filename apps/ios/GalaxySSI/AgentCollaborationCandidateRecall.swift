import CryptoKit
import Foundation

enum AgentCollaborationCandidateRecall {
  static let mode = "method_history"
  static let prefix = "native-evidence:"
  static let instructions = "Use capabilities to find unfinished tools and test plans. Follow usage_recall for exact test history and read_original for diagnostics. Discovery, a replay or a passing test does not release a candidate."

  static func isCandidate(_ kind: AgentCollaborationResearchDraft.Kind) -> Bool {
    kind == .executableTool || kind == .toolTestPlan
  }

  static func isHistoryCall(_ tool: String, _ input: AgentMcpJSONObject) -> Bool {
    tool == CloudModelStreamMutableConversation.collaborationRecallName &&
      input["mode"] == .string(mode) && input["view"] == nil
  }

  static func cloudProperties(_ properties: [String: Any], enabled: Bool) -> [String: Any] {
    guard enabled, var selector = properties["mode"] as? [String: Any],
          var values = selector["enum"] as? [String] else { return properties }
    if !values.contains(mode) { values.append(mode) }
    selector["enum"] = values
    var result = properties
    result["mode"] = selector
    result["query"] = ["type": "string", "description": instructions]
    return result
  }

  static func nativeSchema(_ schema: AgentMcpJSONObject, enabled: Bool) -> AgentMcpJSONObject {
    guard enabled, var properties = schema["properties"]?.objectValue,
          var selector = properties["mode"]?.objectValue, var values = selector["enum"]?.arrayValue else { return schema }
    if !values.contains(.string(mode)) { values.append(.string(mode)) }
    selector["enum"] = .array(values)
    properties["mode"] = .object(selector)
    properties["query"] = .object(["type": .string("string"), "description": .string(instructions)])
    var result = schema
    result["properties"] = .object(properties)
    return result
  }

  static func validDigest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }

  static func reference(_ object: AgentMcpJSONObject) -> AgentCollaborationResearchReference? {
    guard let id = object["object_id"]?.strictStringValue, validDigest(id),
          let hash = object["sha256"]?.strictStringValue, validDigest(hash),
          case .int(let revision)? = object["revision"], revision > 0 else { return nil }
    return .init(objectId: id, revision: revision, sha256: hash)
  }

  static func reference(_ value: AgentCollaborationResearchReference) -> AgentMcpJSONObject {
    ["object_id": .string(value.objectId), "revision": .int(value.revision), "sha256": .string(value.sha256)]
  }

  static func selector(_ value: AgentCollaborationResearchReference) -> AgentMcpJSONObject {
    var input = reference(value)
    input["mode"] = .string(mode)
    return input
  }

  static func visible(_ record: AgentCollaborationResearchRevision, scope: AgentCollaborationToolEvidenceScope) -> Bool {
    record.turnId != scope.turnId || (record.runId == scope.runId && record.authorId == scope.memberId)
  }

  static func linkedTool(_ plan: AgentCollaborationResearchRevision) -> AgentCollaborationResearchReference? {
    guard let link = plan.draft.body["tool_test_plan"]?.objectValue?["executable_tool"]?.objectValue,
          let ref = reference(link), plan.draft.parents.contains(ref) else { return nil }
    return ref
  }

  static func searchableMetadata(_ body: AgentMcpJSONObject, tool: Bool) -> [String] {
    let fields = tool
      ? ["name", "purpose", "environment", "dependencies", "applies_when", "avoid_when", "side_effects"]
      : ["purpose", "environment", "coverage_gaps", "oracle_basis"]
    return fields.flatMap { key in
      if let value = body[key]?.strictStringValue { return [value] }
      return body[key]?.arrayValue?.compactMap(\.strictStringValue) ?? []
    }
  }

  static func encoded(_ observation: AgentCollaborationNativeToolObservation) throws -> (id: String, hash: String, bytes: Data) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let bytes = try encoder.encode(observation)
    let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    let id = AgentMcpJSONCodec.sha256([
      "run": .string(observation.runId), "source": .string(observation.sourceId),
      "invocation": .string(observation.result.receipt.invocationId), "sha256": .string(hash)
    ])
    return (id, hash, bytes)
  }

  static func visible(_ row: AgentCollaborationNativeToolObservation, scope: AgentCollaborationToolEvidenceScope) -> Bool {
    row.conversationId == scope.conversationId && (row.turnId != scope.turnId ||
      (row.runId == scope.runId && row.memberId == scope.memberId && row.sourceId == scope.sourceId))
  }

  struct Test {
    let plan: AgentCollaborationResearchReference
    let candidate: AgentCollaborationResearchReference?
    let runtimeReportedPassed: Bool?
  }

  static func test(_ observation: AgentCollaborationNativeToolObservation) -> Test? {
    guard observation.result.provenance.toolId == AgentIOSOnDeviceRuntimeNativeToolCatalog.execute,
          observation.result.provenance.executorId == AgentIOSOnDeviceRuntimeNativeToolCatalog.brokerExecutorId,
          observation.result.provenance.location == .application,
          let request = observation.input["collaboration_tool"]?.objectValue, request["mode"] == .string("test"),
          let plan = request["tool_test_plan"]?.objectValue.flatMap(reference) else { return nil }
    guard let report = observation.result.output["collaboration_tool_receipt"] else {
      guard !observation.result.isSuccess else { return nil }
      return Test(plan: plan, candidate: nil, runtimeReportedPassed: nil)
    }
    guard let runtime = report.objectValue, runtime["mode"] == .string("test"),
          runtime["tool_test_plan"]?.objectValue.flatMap(reference) == plan,
          let source = runtime["executable_tool"]?.objectValue.flatMap(reference) else { return nil }
    return Test(plan: plan, candidate: source, runtimeReportedPassed: runtime["passed"]?.boolValue)
  }

  static func match(_ test: Test, subject: AgentCollaborationResearchRevision,
                    visiblePlan: AgentCollaborationResearchRevision?) -> String? {
    if subject.draft.kind == .toolTestPlan, subject.reference == test.plan { return "requested_test_plan" }
    guard subject.draft.kind == .executableTool, test.candidate == subject.reference,
          let visiblePlan, visiblePlan.draft.kind == .toolTestPlan, visiblePlan.reference == test.plan,
          linkedTool(visiblePlan) == subject.reference else { return nil }
    return "runtime_resolved_candidate"
  }

  static func describe(_ observation: AgentCollaborationNativeToolObservation, test: Test, binding: String,
                       id: String, hash: String) -> AgentMcpJSONValue {
    let receipt = observation.result.receipt
    return .object([
      "evidence_id": .string(id), "sha256": .string(hash), "origin": .string("ios_native_tool"),
      "subject_binding": .string(binding), "test_plan": .object(reference(test.plan)),
      "runtime_report_available": .bool(test.candidate != nil),
      "runtime_reported_passed": test.runtimeReportedPassed.map(AgentMcpJSONValue.bool) ?? .null,
      "native_status": .string(observation.result.status.rawValue), "replayed": .bool(receipt.replayed),
      "native_invocation_id": .string(receipt.invocationId),
      "original_invocation_id": receipt.originalInvocationId.map(AgentMcpJSONValue.string) ?? .null,
      "started_at": .int(receipt.startedAtEpochMillis), "finished_at": .int(receipt.finishedAtEpochMillis),
      "read_original": .object(["mode": .string("evidence"), "evidence_id": .string(id), "sha256": .string(hash)]),
      "quality_effect": .null, "grants_execution": .bool(false)
    ])
  }

  static func exact(_ ref: AgentCollaborationResearchReference, scope: AgentCollaborationToolEvidenceScope,
                    database: AgentTeamHistoryDatabase) throws -> AgentCollaborationResearchRevision? {
    guard let row = try database.researchRecord(AgentCollaborationResearchRevision.self,
      conversationId: scope.conversationId, key: "object:" + ref.objectId, revision: ref.revision),
      row.reference == ref, visible(row, scope: scope) else { return nil }
    return row
  }

  static func history(_ input: AgentMcpJSONObject, scope: AgentCollaborationToolEvidenceScope, dependencies: [String],
                      database: AgentTeamHistoryDatabase) throws -> AgentMcpJSONObject? {
    guard Set(input.keys).isSubset(of: ["mode", "object_id", "revision", "sha256", "cursor"]),
          let ref = reference(input), case .string(let cursor) = input["cursor"] ?? .string(""),
          cursor.utf8.count <= 130 else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    guard let subject = try exact(ref, scope: scope, database: database) else { throw AgentTeamHistoryDatabase.Failure.stale }
    guard isCandidate(subject.draft.kind) else { return nil }
    let binding = AgentMcpJSONCodec.sha256([
      "scope": .string(scope.ownershipDigest), "subject": .object(reference(ref)),
      "kind": .string(subject.draft.kind.rawValue),
      "dependencies": .array(dependencies.sorted().map(AgentMcpJSONValue.string))
    ])
    var after = ""
    if !cursor.isEmpty {
      let parts = cursor.split(separator: ":", omittingEmptySubsequences: false)
      guard parts.count == 2, String(parts[0]) == binding, validDigest(String(parts[1]))
      else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      after = prefix + String(parts[1])
    }
    let keys = try database.milestoneKeys(conversationId: scope.conversationId, prefix: prefix, after: after)
    var records: [AgentMcpJSONValue] = []
    var scanned = 0
    for key in keys.prefix(32) {
      scanned += 1
      guard let row = try database.researchRecord(AgentCollaborationNativeToolObservation.self,
        conversationId: scope.conversationId, key: key, revision: 0),
        visible(row, scope: scope), let test = test(row),
        test.plan == ref || test.candidate == ref,
        let plan = try exact(test.plan, scope: scope, database: database),
        let matched = match(test, subject: subject, visiblePlan: plan),
        try runtimeSourceVisible(test, plan: plan, scope: scope, database: database) else { continue }
      let identity = try encoded(row)
      guard key == prefix + identity.id else { throw AgentTeamHistoryDatabase.Failure.corrupt }
      records.append(describe(row, test: test, binding: matched, id: identity.id, hash: identity.hash))
      if records.count == 12 { break }
    }
    let next = scanned < keys.count && scanned > 0 ? binding + ":" + String(keys[scanned - 1].dropFirst(prefix.count)) : nil
    return [
      "status": .string("returned"), "method": .object(reference(ref)), "records": .array(records),
      "record_kind": .string("original_native_tool_observation"), "subject_kind": .string(subject.draft.kind.rawValue),
      "next_cursor": next.map(AgentMcpJSONValue.string) ?? .null, "snapshot": .bool(false), "scan_complete": .bool(next == nil),
      "quality_effect": .null, "causal_contribution": .null, "grants_execution": .bool(false),
      "trust": .string("host_execution_observations_not_method_effectiveness"),
      "guidance": .string(instructions + " Empty history is unknown. Follow next_cursor even on empty pages.")
    ]
  }

  static func readOriginal(id: String, hash: String, scope: AgentCollaborationToolEvidenceScope,
                           database: AgentTeamHistoryDatabase) throws -> Data? {
    guard let row = try database.researchRecord(AgentCollaborationNativeToolObservation.self,
      conversationId: scope.conversationId, key: prefix + id, revision: 0) else { return nil }
    guard visible(row, scope: scope), let test = test(row),
          let plan = try exact(test.plan, scope: scope, database: database), plan.draft.kind == .toolTestPlan,
          try runtimeSourceVisible(test, plan: plan, scope: scope, database: database)
    else { throw AgentTeamHistoryDatabase.Failure.stale }
    let identity = try encoded(row)
    guard identity.id == id, identity.hash == hash else { throw AgentTeamHistoryDatabase.Failure.corrupt }
    return identity.bytes
  }

  private static func runtimeSourceVisible(_ test: Test, plan: AgentCollaborationResearchRevision,
                                           scope: AgentCollaborationToolEvidenceScope,
                                           database: AgentTeamHistoryDatabase) throws -> Bool {
    guard let source = test.candidate else { return true }
    guard linkedTool(plan) == source else { return false }
    return try exact(source, scope: scope, database: database)?.draft.kind == .executableTool
  }
}
