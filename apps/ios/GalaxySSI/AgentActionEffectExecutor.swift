import Foundation

struct AgentEffectRecoveryRecord: Codable, Equatable {
  struct Query: Codable, Equatable {
    enum Kind: String, Codable { case audio, browser }
    let kind: Kind
    let toolId: String
    let version: String
    let input: AgentMcpJSONObject
    let subject: String
  }

  struct Observation: Codable, Equatable {
    let scope: AgentNativeEffectScope
    let toolId: String
    let version: String
    let receipt: AgentNativeToolReceipt
    let output: AgentMcpJSONObject
  }

  static let metadataKey = "host_effect_recovery"
  static let browserObserver = AgentIOSWebMediaNativeToolCatalog.browserSessionOperationStatus
  static let nativeCaller = "galaxyssi.mobile_agent.plan"
  static let browserMutationTools: Set<String> = [
    AgentIOSWebMediaNativeToolCatalog.browserSessionCreate,
    AgentIOSWebMediaNativeToolCatalog.browserSessionNavigate,
    AgentIOSWebMediaNativeToolCatalog.browserSessionBack,
    AgentIOSWebMediaNativeToolCatalog.browserSessionClose
  ]
  let scope: AgentNativeEffectScope
  let actionId: String
  let toolId: String
  let version: String
  let inputDigest: String
  let invocationId: String
  let uncertainAt: Int64
  let query: Query?
  var observation: Observation?

  static func fromNativeResult(
    _ result: AgentNativeToolResult, action: AgentAction, descriptor: AgentNativeToolDescriptor
  ) -> AgentEffectRecoveryRecord? {
    guard descriptor.requiresEffectClaim,
          ["effect_outcome_unknown", "invalid_output", "missing_output_validation"].contains(result.error?.code ?? "") ||
          result.status == .verificationFailed ||
          (result.isSuccess && AgentIOSDeviceStateEvidence.tools.contains(descriptor.id) &&
            !AgentIOSDeviceStateEvidence.verified(descriptor.id, output: result.output, input: parseInput(action))) ||
          result.output["state_verified"] == .bool(false) ||
          result.output["delivery_verified"] == .bool(false) ||
          result.output["outcome"]?.stringValue == "unknown" ||
          result.output["outcome"]?.stringValue == "unverified" ||
          result.output["outcome"]?.stringValue == "uncertain" else { return nil }
    let scope = AgentNativeEffectScope(
      sessionId: action.parameters["_galaxyssi_session_id"] ?? "",
      conversationId: action.parameters["_galaxyssi_conversation_id"] ?? "",
      taskId: action.parameters["_galaxyssi_task_id"] ?? "",
      turnId: action.parameters["_galaxyssi_turn_id"] ?? "")
    let invocation = result.receipt.originalInvocationId ?? result.receipt.invocationId
    let input = parseInput(action) ?? [:]
    let query: Query?
    switch descriptor.id {
    case AgentIOSSystemNativeToolCatalog.audioVolumeSet, AgentIOSSystemNativeToolCatalog.audioMuteSet:
      let stream = input.string("stream").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      query = ["media", "music"].contains(stream) && !AgentIOSDeviceStateEvidence.unavailableAudioControl(result.output)
        ? Query(kind: .audio, toolId: AgentIOSSystemNativeToolCatalog.audioStatus,
                version: descriptor.version, input: [:], subject: "media") : nil
    case AgentIOSWebMediaNativeToolCatalog.browserSessionCreate,
         AgentIOSWebMediaNativeToolCatalog.browserSessionNavigate,
         AgentIOSWebMediaNativeToolCatalog.browserSessionBack,
         AgentIOSWebMediaNativeToolCatalog.browserSessionClose:
      query = Query(kind: .browser, toolId: browserObserver, version: descriptor.version,
                    input: ["request_id": .string(invocation)], subject: invocation)
    default:
      query = nil
    }
    return AgentEffectRecoveryRecord(scope: scope, actionId: action.id, toolId: descriptor.id,
      version: descriptor.version, inputDigest: result.receipt.inputSha256, invocationId: invocation,
      uncertainAt: result.receipt.finishedAtEpochMillis, query: query)
  }

  static func fromActionResult(_ result: AgentActionResult) -> AgentEffectRecoveryRecord? {
    guard let data = result.metadata[metadataKey]?.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(Self.self, from: data)
  }

  static func parseInput(_ action: AgentAction) -> AgentMcpJSONObject? {
    let text = (action.parameters["input_json"] ?? "").ifBlank("{}")
    return try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(text.utf8))
  }

  func isSameEffect(_ action: AgentAction) -> Bool {
    guard action.kind == .callNativeTool,
          (action.parameters["tool_id"] ?? action.target) == toolId else { return false }
    if action.id == actionId { return true }
    return Self.parseInput(action).map { AgentMcpJSONCodec.sha256($0) == inputDigest } ?? false
  }

  func matches(taskId: String, sessionId: String, outgoing: ChatMessage) -> Bool {
    !scope.taskId.isEmpty && !scope.sessionId.isEmpty && !scope.conversationId.isEmpty && !scope.turnId.isEmpty &&
      outgoing.isMine && scope.taskId == taskId && scope.sessionId == sessionId &&
      scope.conversationId == outgoing.conversationId && scope.turnId == outgoing.turnId.ifBlank(outgoing.id.uuidString)
  }

  func verifies(_ value: Observation) -> Bool {
    guard let query, !invocationId.isEmpty, uncertainAt > 0, value.scope == scope,
          value.toolId == query.toolId, value.version == query.version,
          value.receipt.status == .succeeded, !value.receipt.replayed,
          !value.receipt.invocationId.isEmpty, value.receipt.invocationId != invocationId,
          value.receipt.originalInvocationId == nil,
          value.receipt.inputSha256 == AgentMcpJSONCodec.sha256(query.input),
          value.receipt.outputSha256 == AgentMcpJSONCodec.sha256(value.output),
          value.receipt.startedAtEpochMillis >= uncertainAt,
          value.receipt.finishedAtEpochMillis >= value.receipt.startedAtEpochMillis,
          value.receipt.finishedAtEpochMillis > uncertainAt,
          let sampledAt = value.output["observed_at_epoch_ms"]?.intValue,
          sampledAt >= value.receipt.startedAtEpochMillis,
          sampledAt <= value.receipt.finishedAtEpochMillis else { return false }
    switch query.kind {
    case .audio:
      guard let stream = value.output["streams"]?.objectValue?[query.subject]?.objectValue else { return false }
      return stream.string("stream") == query.subject && stream["current"]?.intValue != nil &&
        stream.string("scope") == "app_visible_output_volume"
    case .browser:
      return value.output.string("request_id") == query.subject &&
        value.output.string("operation") == String(toolId.split(separator: ".").last ?? "")
    }
  }

  var hasObservation: Bool { observation.map(verifies) ?? false }

  func permitsFollowUp(_ actions: [AgentAction]) -> Bool {
    hasObservation && !actions.contains(where: isSameEffect)
  }

  static func shortcutReviewIndex(
    plan: AgentPlan?, actionId: String, effects: [AgentEffectRecoveryRecord]
  ) -> Int? {
    guard let plan, plan.executionMode != .planOnly,
          plan.plannerProfile == "rule-based-direct-native-tool",
          plan.actions.contains(where: {
            $0.id == actionId && $0.kind == .callNativeTool && [.completed, .failed].contains($0.status)
          }) else { return nil }
    return effects.firstIndex {
      $0.actionId == actionId && $0.query != nil && !$0.hasObservation
    }
  }

  static func permitsReviewProvider(
    _ snapshot: AgentPlannerModelSnapshot, localOnly: Bool, privateMode: Bool, connectorsAllowed: Bool
  ) -> Bool {
    if snapshot.localProfileId != nil {
      return snapshot.route == nil && snapshot.pairedPhonePlanner == nil
    }
    return !localOnly && !privateMode && connectorsAllowed &&
      (snapshot.route != nil || snapshot.pairedPhonePlanner != nil)
  }
}

/// Durably claims legacy Agent actions before dispatching their external effects.
final class AgentActionEffectExecutor {
  private let store: AgentNativeToolReplayStore
  private let nowMillis: () -> Int64

  init(
    store: AgentNativeToolReplayStore,
    nowMillis: @escaping () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) {
    self.store = store
    self.nowMillis = nowMillis
  }

  func dispatchedResult(
    action: AgentAction,
    context: AgentNativeToolInvocationContext
  ) -> AgentActionResult? {
    guard action.kind == .callConnector else { return nil }
    let key = AgentNativeToolReplayKey(
      toolId: Self.toolId,
      toolVersion: Self.toolVersion,
      idempotencyKey: AgentConnectorHandoffRecovery.effectAttemptKey(action),
      scope: AgentNativeEffectScope(context: context)
    )
    guard let claim = store.observe(key), claim.result != nil else { return nil }
    return Self.observedResult(action: action, digest: Self.inputDigest(action), claim: claim)
  }

  func execute(
    action: AgentAction,
    screen: AgentScreenContext,
    context: AgentNativeToolInvocationContext,
    delegate: AgentActionExecutor
  ) -> AgentActionResult {
    if action.kind == .readScreen {
      return AgentLatencyTelemetry.runtime.measure(
        taskId: Self.taskId(context, action: action),
        phase: .screenObserve,
        outcome: Self.runtimeOutcome
      ) {
        delegate.execute(action: action, screen: screen)
      }
    }
    guard action.kind != .callNativeTool else {
      return Self.failure(
        action,
        code: "action_effect_native_tool_conflict",
        message: "Native tool calls already use the native effect journal."
      )
    }
    guard !action.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return Self.failure(
        action,
        code: "action_effect_identity_missing",
        message: "A durable action requires a stable action ID."
      )
    }

    let key = AgentNativeToolReplayKey(
      toolId: Self.toolId,
      toolVersion: Self.toolVersion,
      idempotencyKey: AgentConnectorHandoffRecovery.effectAttemptKey(action),
      scope: AgentNativeEffectScope(context: context)
    )
    let digest = Self.inputDigest(action)
    let startedAt = nowMillis()

    let observed = AgentLatencyTelemetry.runtime.measure(
      taskId: Self.taskId(context, action: action),
      phase: .receiptObserve,
      operation: { store.observe(key) }
    )
    if let observed {
      return Self.observedResult(action: action, digest: digest, claim: observed)
    }
    let claim: AgentNativeEffectClaim
    do {
      claim = try store.claim(key, inputSha256: digest, invocationId: context.invocationId)
    } catch {
      return Self.failure(
        action,
        code: "action_effect_journal_unavailable",
        message: "Action was not dispatched because its execution journal could not be claimed: \(error.localizedDescription)"
      )
    }
    guard claim.acquired else {
      return Self.observedResult(action: action, digest: digest, claim: claim)
    }

    let outcome = delegate.execute(action: action, screen: screen)
    do {
      try AgentLatencyTelemetry.runtime.measure(
        taskId: Self.taskId(context, action: action),
        phase: .resultVerify
      ) {
        try store.complete(
          key,
          invocationId: context.invocationId,
          result: Self.pack(
            action: action,
            key: key,
            invocationId: context.invocationId,
            inputDigest: digest,
            startedAt: startedAt,
            finishedAt: nowMillis(),
            outcome: outcome
          )
        )
      }
      return outcome
    } catch {
      return Self.failure(
        action,
        code: "effect_outcome_unknown",
        message: "Action ran but its outcome could not be committed: \(error.localizedDescription). Observe external state before proposing a new action."
      )
    }
  }

  private static func observedResult(
    action: AgentAction,
    digest: String,
    claim: AgentNativeEffectClaim
  ) -> AgentActionResult {
    guard claim.inputSha256 == digest else {
      return failure(
        action,
        code: "idempotency_key_conflict",
        message: "The same action ID was already used with different execution input."
      )
    }
    guard let saved = claim.result else {
      return failure(
        action,
        code: "effect_outcome_unknown",
        message: "This action already started without a durable outcome. It was not dispatched again. Observe external state before deciding the next action.",
        details: ["original_invocation_id": claim.invocationId]
      )
    }
    guard let actionId = saved.output["action_id"]?.stringValue,
          let success = saved.output["success"]?.boolValue,
          let message = saved.output["message"]?.stringValue,
          let rawMetadata = saved.output["metadata"]?.objectValue,
          success == saved.isSuccess else {
      return failure(
        action,
        code: "action_effect_receipt_invalid",
        message: "The durable action receipt is invalid and the action was not dispatched again."
      )
    }
    let metadata = rawMetadata.reduce(into: [String: String]()) { output, entry in
      if let value = entry.value.stringValue {
        output[entry.key] = value
      }
    }
    guard metadata.count == rawMetadata.count else {
      return failure(
        action,
        code: "action_effect_receipt_invalid",
        message: "The durable action receipt metadata is invalid and the action was not dispatched again."
      )
    }
    return AgentActionResult(
      actionId: actionId,
      success: success,
      message: message,
      metadata: metadata.merging([
        "action_effect_replayed": "true",
        "original_invocation_id": claim.invocationId
      ]) { _, replay in replay }
    )
  }

  private static func inputDigest(_ action: AgentAction) -> String {
    AgentMcpJSONCodec.sha256([
      "kind": .string(action.kind.rawValue),
      "target": .string(action.target),
      "description": .string(action.description),
      "parameters": .object(action.parameters.reduce(into: AgentMcpJSONObject()) { output, entry in
        output[entry.key] = .string(entry.value)
      }),
      "risk": .string(action.risk.rawValue),
      "requires_confirmation": .bool(action.requiresConfirmation)
    ])
  }

  private static func pack(
    action: AgentAction,
    key: AgentNativeToolReplayKey,
    invocationId: String,
    inputDigest: String,
    startedAt: Int64,
    finishedAt: Int64,
    outcome: AgentActionResult
  ) -> AgentNativeToolResult {
    let execution = AgentNativeToolAgentActionAdapter.fromAgentActionResult(outcome)
    let status: AgentNativeToolResultStatus = outcome.success ? .succeeded : .failed
    let finish = max(startedAt, finishedAt)
    return AgentNativeToolResult(
      status: status,
      output: execution.output,
      message: outcome.message,
      error: execution.error,
      receipt: AgentNativeToolReceipt(
        invocationId: invocationId,
        idempotencyKey: key.idempotencyKey,
        startedAtEpochMillis: startedAt,
        finishedAtEpochMillis: finish,
        durationMillis: max(0, finish - startedAt),
        status: status,
        inputSha256: inputDigest,
        outputSha256: AgentMcpJSONCodec.sha256(execution.output)
      ),
      provenance: AgentNativeToolProvenance(
        toolId: key.toolId,
        toolVersion: key.toolVersion,
        location: .phone,
        executorId: "galaxyssi.action_effect",
        contractVersion: AgentNativeToolRegistry.contractVersion,
        legacyAgentActionId: action.id
      )
    )
  }

  private static func failure(
    _ action: AgentAction,
    code: String,
    message: String,
    details: [String: String] = [:]
  ) -> AgentActionResult {
    AgentActionResult(
      actionId: action.id,
      success: false,
      message: message,
      metadata: details.merging([
        "error_code": code,
        "action_effect_status": code
      ]) { _, status in status }
    )
  }

  private static func taskId(
    _ context: AgentNativeToolInvocationContext,
    action: AgentAction
  ) -> String {
    (context.attributes["task_id"] ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty ?? context.turnId.nilIfEmpty ?? action.id
  }

  private static func runtimeOutcome(_ result: AgentActionResult) -> String {
    result.success ? "completed" : "failed"
  }

  private static let toolId = "galaxyssi.action.dispatch"
  private static let toolVersion = "1.0.0"
}
