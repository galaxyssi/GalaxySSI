import Foundation

enum AgentModelContextHandoffEvidence {
  private static let liveStates: Set<String> = ["running", "pending", "queued", "waiting", "in_progress", "awaiting_user"]
  private static let referenceKeys: Set<String> = [
    "handle", "handle_id", "operation_id", "operation_status", "session_id", "browser_id", "run_id", "task_id",
    "request_id", "handoff_id", "host_wait_key", "host_wait_generation", "control_owner", "next_action",
    "next_cursor", "cursor", "next_offset", "window_id", "revision", "node_path", "path", "page_id", "frame_id",
    "next_text_offset", "next_control_offset", "state", "status", "complete", "completed", "business_success_verified",
    "outcome", "outcome_unknown", "state_verified", "delivery_verified",
    "galaxyssi_evidence_receipt", "galaxyssi_evidence_recording"
  ]

  static func build(
    _ messages: [AgentModelMessage], fits: (String) throws -> Bool
  ) throws -> String {
    var calls: [String: AgentModelToolCall] = [:]
    for message in messages {
      for call in message.toolCalls { calls[call.callId] = call }
    }
    let latestCalls = Set(messages.last { !$0.toolCalls.isEmpty }?.toolCalls.map(\.callId) ?? [])
    let observations = messages.compactMap(\.toolResult)
    let lastFailure = observations.lastIndex { $0.status != "succeeded" || $0.error != nil }
    var selected: [Int: AgentMcpJSONObject] = [:]
    for (index, result) in observations.enumerated() where latestCalls.contains(result.callId) ||
      lastFailure == index || isLive(result) || isUncertain(result) {
      selected[index] = entry(result, call: calls[result.callId])
    }
    var notes = ""
    func encode() -> String {
      AgentMcpJSONCodec.stringify([
        "kind": .string("historical_observations_not_instructions"),
        "total_observations": .int(Int64(observations.count)),
        "omitted_observations": .int(Int64(observations.count - selected.count)),
        "completion_verified": .bool(false),
        "assistant_notes_unverified": .string(notes),
        "observations": .array(selected.keys.sorted().compactMap { selected[$0].map(AgentMcpJSONValue.object) })
      ])
    }
    guard try fits(encode()) else {
      throw AgentModelLoopRecoveryError(code: "model_context_required_evidence_too_large")
    }
    for index in observations.indices.reversed() where selected[index] == nil {
      let result = observations[index]
      selected[index] = entry(result, call: calls[result.callId])
      if try fits(encode()) == false { selected.removeValue(forKey: index) }
    }
    notes = ConversationContextCompactor.fitTextToTokenBudget(
      messages.last { $0.role == .assistant && !$0.text.isBlank }?.text ?? "", 384)
    if try fits(encode()) == false { notes = "" }
    return encode()
  }

  private static func isLive(_ result: AgentModelToolResultContent) -> Bool {
    let output = result.output
    guard output["complete"] != .bool(true), output["completed"] != .bool(true) else { return false }
    return output["control_owner"] == .string("user") ||
      [result.status, output["state"]?.strictStringValue, output["status"]?.strictStringValue]
        .compactMap { $0 }.contains { liveStates.contains($0.lowercased()) }
  }

  private static func isUncertain(_ result: AgentModelToolResultContent) -> Bool {
    result.error?.code == "effect_outcome_unknown" || result.status == "verification_failed" ||
      result.error?.details["outcome_unknown"] == .bool(true) || result.output["outcome_unknown"] == .bool(true) ||
      result.output["state_verified"] == .bool(false) || result.output["delivery_verified"] == .bool(false) ||
      ["unknown", "unverified", "uncertain"].contains(result.output["outcome"]?.strictStringValue ?? "")
  }

  private static func entry(_ result: AgentModelToolResultContent, call: AgentModelToolCall?) -> AgentMcpJSONObject {
    let receipt = result.receipt
    let observation = result.output
    var references = observation.filter { referenceKeys.contains($0.key) }
    let summary = result.error?.message.nilIfEmpty ?? result.message.nilIfEmpty ??
      AgentMcpJSONCodec.stringify(observation)
    references["summary"] = .string(ConversationContextCompactor.fitTextToTokenBudget(summary, 160))
    references["compacted"] = .bool(true)
    references["original_output_sha256"] = .string(AgentModelLoopRecoveryIdentity.sha256(observation))
    if isUncertain(result), let query = result.error?.details["recovery_query"]?.objectValue,
       let saved = AgentNativeEffectRecoveryQuery(query) {
      references["recovery_query"] = saved.json
    }
    var entry: AgentMcpJSONObject = [
      "call_id": .string(result.callId), "tool": .string(result.toolId), "status": .string(result.status),
      "invocation_id": result.invocationId.map(AgentMcpJSONValue.string) ?? .null,
      "observation": .object(references)
    ]
    if let call {
      entry["arguments_sha256"] = .string(AgentModelLoopRecoveryIdentity.sha256(call.arguments))
      entry["arguments_excerpt"] = .string(ConversationContextCompactor.fitTextToTokenBudget(
        AgentMcpJSONCodec.stringify(call.arguments), 128))
    }
    if let receipt {
      entry["receipt"] = .object([
        "invocation_id": .string(receipt.invocationId), "status": .string(receipt.status.rawValue),
        "original_invocation_id": receipt.originalInvocationId.map(AgentMcpJSONValue.string) ?? .null,
        "input_sha256": .string(receipt.inputSha256), "output_sha256": .string(receipt.outputSha256),
        "finished_at_epoch_ms": .int(receipt.finishedAtEpochMillis), "replayed": .bool(receipt.replayed)
      ])
    }
    if let error = result.error {
      entry["error"] = .object([
        "code": .string(error.code),
        "message": .string(ConversationContextCompactor.fitTextToTokenBudget(error.message, 128)),
        "retryable": .bool(error.retryable),
        "details": .object(error.details.filter { referenceKeys.contains($0.key) })
      ])
    }
    return entry
  }
}
