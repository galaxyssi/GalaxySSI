import Foundation

enum AgentVerifiedTimerStart {
  static let toolId = AgentNativeToolAgentActionAdapter.defaultToolId(.setAlarm)
  static let terminalParameter = "_galaxyssi_model_completes_goal"
  static let argumentsContract = "For a 60-second start use action.parameters.arguments={\"target\":\"timer\",\"parameters\":{\"timer_operation\":\"start\",\"timer_seconds\":60}}. Set action.completes_goal=true only if starting the timer is the entire request. iOS verifies the actual running receipt and duration before closing; a model claim or notification submission alone is not proof."

  static func isReviewer(_ action: AgentAction, timerId: String) -> Bool {
    AgentSupervisorRecoveryPolicy.isSupervisor(action) &&
      ids(action, "depends_on") == [timerId] && ids(action, "use_outputs_from") == [timerId]
  }

  static func waitingStart(_ actions: [AgentAction], waitingId: String) -> AgentAction? {
    let timers = actions.filter { $0.kind == .callNativeTool && $0.parameters["tool_id"] == toolId && $0.status == .completed }
    guard actions.count == 2, timers.count == 1, let timer = timers.first,
          actions.contains(where: { $0.id == waitingId && $0.status == .waitingResponse && isReviewer($0, timerId: timer.id) }) else { return nil }
    return timer
  }

  static func permits(plan: AgentPlan, action: AgentAction, result: AgentActionResult,
    legacyCheckpoint: AgentIOSTimerCheckpoint? = nil) -> Bool {
    let matches = plan.actions.filter { $0.id == action.id }
    guard plan.executionMode != .planOnly, action.kind == .callNativeTool, action.parameters["tool_id"] == toolId,
          result.actionId == action.id, result.success,
          result.metadata["awaiting_response"] != "true", result.metadata["effect_outcome_unknown"] != "true",
          result.metadata["native_tool_id"] == toolId, result.metadata["native_tool_status"] == "succeeded",
          !(result.metadata["invocation_id"] ?? "").isBlank,
          matches.count == 1, let observed = matches.first, observed.kind == .callNativeTool,
          observed.parameters["tool_id"] == toolId, observed.status == .completed,
          observed.parameters["input_json"] == action.parameters["input_json"],
          plan.actions.allSatisfy({ $0.id == action.id ||
            (isReviewer($0, timerId: action.id) && [.proposed, .pendingConfirmation, .waitingResponse].contains($0.status)) }),
          (plan.completionRequirements?.results ?? []).isEmpty,
          plan.completionRequirements?.publication == nil || plan.completionRequirements?.publication == AgentPublicationRequirement.none,
          plan.completionRequirements?.phoneLinux != true,
          (plan.completionRequirements?.artifacts ?? []).isEmpty, (plan.completionRequirements?.fileArtifacts ?? []).isEmpty,
          let input = action.parameters["input_json"].flatMap(decode), let args = input["parameters"]?.objectValue,
          args.string("timer_operation").ifBlank("start") == "start",
          let seconds = parseSeconds(args["timer_seconds"]),
          (1...604_800).contains(seconds), let raw = result.metadata["native_tool_output"], let output = decode(raw),
          output["success"] == .bool(true), !output.string("message").isBlank,
          let metadata = output["metadata"]?.objectValue,
          metadata.string("completion_verified") == "true", metadata.string("timer_state") == "running",
          !metadata.string("operation_id").isBlank,
          args.string("operation_id").isBlank || args.string("operation_id") == metadata.string("operation_id") else { return false }
    let currentReceipt = metadata.string("execution_authority") == "galaxyssi-phone" &&
      Int(metadata.string("duration_seconds")) == seconds
    // Old local receipts did not include duration/authority. Bind their immutable timer identity;
    // a checkpoint without the original verified running receipt never qualifies.
    let legacyReceipt = metadata["execution_authority"] == nil && metadata["duration_seconds"] == nil &&
      result.metadata["provenance"] == AgentPhoneNativeToolCatalog.actionExecutorId &&
      legacyCheckpoint?.id.uuidString == metadata.string("operation_id") &&
      legacyCheckpoint?.sourceTurnId == metadata.string("source_turn_id") && legacyCheckpoint?.durationSeconds == seconds
    guard currentReceipt || legacyReceipt else { return false }
    if let requested = AgentDirectNativeToolPlanner.exactTimerStartSeconds(plan.goal) {
      guard requested == seconds else { return false }
    } else if action.parameters[terminalParameter] != "true" { return false }
    return AgentCompletionEvidencePolicy.observationDiagnostics(requirements: plan.completionRequirements,
      history: plan.actionHistory + plan.actions).isEmpty
  }

  private static func decode(_ text: String) -> AgentMcpJSONObject? {
    try? JSONDecoder().decode(AgentMcpJSONObject.self, from: Data(text.utf8))
  }

  private static func parseSeconds(_ value: AgentMcpJSONValue?) -> Int? {
    switch value {
    case .int(let value): return Int(exactly: value)
    case .string(let value): return Int(value)
    default: return nil
    }
  }

  private static func ids(_ action: AgentAction, _ key: String) -> [String] {
    (action.parameters[key] ?? "").split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
  }
}
