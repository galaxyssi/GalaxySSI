import Foundation

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
      idempotencyKey: AgentConnectorFallbackAction.effectAttemptKey(action),
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
