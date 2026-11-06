import Foundation

struct AgentPlanLifecycleNormalization: Equatable {
  var plan: AgentPlan
  var removedActions: [AgentAction]

  var changed: Bool {
    !removedActions.isEmpty
  }

  func recoverResult(previous: AgentActionResult?) -> AgentActionResult? {
    guard changed else {
      return previous
    }
    let removedIds = Set(removedActions.map(\.id))
    if let previous,
      !removedIds.contains(previous.actionId),
      !previous.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return previous
    }
    guard let action = plan.actions.reversed().first(where: {
      !$0.result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        Self.resultStatuses.contains($0.status)
    }) else {
      return previous
    }
    return AgentActionResult(
      actionId: action.id,
      success: action.status == .completed,
      message: action.result
    )
  }

  private static let resultStatuses: Set<AgentActionStatus> = [
    .completed,
    .failed,
    .blocked
  ]
}

struct AgentSessionLifecycleNormalization: Equatable {
  var session: AgentSessionSnapshot
  var removedActions: [AgentAction]

  var changed: Bool {
    !removedActions.isEmpty
  }
}

enum AgentPlanLifecyclePolicy {
  static func normalize(_ plan: AgentPlan) -> AgentPlanLifecycleNormalization {
    let legacyRuntimeDrafts = !plan.actions.isEmpty &&
      plan.actions.allSatisfy {
        $0.kind == .draftPlan &&
          $0.target.caseInsensitiveCompare(localAgentRuntimeTarget) == .orderedSame
      } ? plan.actions : []

    if !legacyRuntimeDrafts.isEmpty {
      let recovered = recoverCompletedHistory(plan: plan, drafts: legacyRuntimeDrafts)
      if recovered.changed {
        return recovered
      }
      return retireLegacyRuntimeFallback(plan: plan, drafts: legacyRuntimeDrafts)
    }

    let trailingDrafts = trailingRetirableDrafts(plan.actions)
    if trailingDrafts.isEmpty {
      return AgentPlanLifecycleNormalization(plan: plan, removedActions: [])
    }
    if trailingDrafts.count == plan.actions.count {
      return recoverCompletedHistory(plan: plan, drafts: trailingDrafts)
    }
    let retainedActions = Array(plan.actions.dropLast(trailingDrafts.count))
    if !retainedActions.contains(where: { $0.kind != .draftPlan }) {
      return AgentPlanLifecycleNormalization(plan: plan, removedActions: [])
    }
    let removedIds = Set(trailingDrafts.map(\.id))
    var normalized = plan
    normalized.actions = retainedActions
    normalized.verificationResults = plan.verificationResults.filter { !removedIds.contains($0.actionId) }
    normalized.checkpoints = plan.checkpoints.filter { !removedIds.contains($0.actionId) }
    normalized.validation = AgentPlanValidator.validate(normalized)
    return AgentPlanLifecycleNormalization(plan: normalized, removedActions: trailingDrafts)
  }

  static func normalize(_ session: AgentSessionSnapshot) -> AgentSessionLifecycleNormalization {
    guard let plan = session.currentPlan else {
      return AgentSessionLifecycleNormalization(session: session, removedActions: [])
    }
    let planNormalization = normalize(plan)
    guard planNormalization.changed else {
      return AgentSessionLifecycleNormalization(session: session, removedActions: [])
    }
    var normalizedSession = session
    normalizedSession.phase = resolvedPhase(plan: planNormalization.plan, fallback: session.phase)
    normalizedSession.currentPlan = planNormalization.plan
    normalizedSession.lastActionResult = planNormalization.recoverResult(previous: session.lastActionResult)
    return AgentSessionLifecycleNormalization(
      session: normalizedSession,
      removedActions: planNormalization.removedActions
    )
  }

  static func recoverCompletedConnector(
    session: AgentSessionSnapshot,
    persistedTask: AgentTaskRecord?,
    missingResult: String
  ) -> AgentSessionSnapshot {
    guard let plan = session.currentPlan else {
      return session
    }
    let receivedConnectorResponse = session.auditTrail.contains {
      $0.event == .connectorResponseReceived
    }
    let staleRuntimeDrafts = !plan.actions.isEmpty &&
      plan.actions.allSatisfy {
        $0.kind == .draftPlan &&
          $0.target.caseInsensitiveCompare(localAgentRuntimeTarget) == .orderedSame
      }
    guard receivedConnectorResponse, staleRuntimeDrafts else {
      return session
    }

    let durableResult = durableConnectorResult(from: persistedTask)
    let previousResult = session.lastActionResult.flatMap { result -> String? in
      guard !isBlank(result.message),
        plan.actions.allSatisfy({ $0.id != result.actionId }) else {
        return nil
      }
      return result.message
    } ?? ""
    let resultText = firstNonBlank(durableResult, previousResult, missingResult.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !isBlank(resultText) else {
      return session
    }

    let recoveredAction: AgentAction
    if var historicalConnector = plan.actionHistory.reversed().first(where: { $0.kind == .callConnector }) {
      historicalConnector.status = .completed
      historicalConnector.result = resultText
      historicalConnector.evidence = restoredConnectorEvidence
      recoveredAction = historicalConnector
    } else {
      recoveredAction = AgentAction(
        id: "restored-connector-result",
        kind: .callConnector,
        target: firstNonBlank(persistedTask?.targetTitle ?? "", plan.route.targetTitle, "remote-agent"),
        risk: persistedTask?.risk ?? .low,
        status: .completed,
        description: "Restore completed remote Agent result",
        requiresConfirmation: false,
        result: resultText,
        evidence: restoredConnectorEvidence
      )
    }

    var normalizedPlan = plan
    normalizedPlan.actions = [recoveredAction]
    normalizedPlan.selectedAgentOrModel = recoveredAction.target
    normalizedPlan.expectedResult = resultText
    normalizedPlan.actionHistory = plan.actionHistory.filter { $0.id != recoveredAction.id }
    normalizedPlan.confirmationRequired = false
    normalizedPlan.validation = AgentPlanValidator.validate(normalizedPlan)

    var normalizedSession = session
    normalizedSession.phase = .completed
    normalizedSession.currentPlan = normalizedPlan
    normalizedSession.lastActionResult = AgentActionResult(
      actionId: recoveredAction.id,
      success: true,
      message: resultText
    )
    return normalizedSession
  }

  private static func recoverCompletedHistory(
    plan: AgentPlan,
    drafts: [AgentAction]
  ) -> AgentPlanLifecycleNormalization {
    guard let recoveredIndex = plan.actionHistory.lastIndex(where: {
      $0.kind != .draftPlan &&
        $0.status == .completed &&
        !isBlank($0.result)
    }) else {
      return AgentPlanLifecycleNormalization(plan: plan, removedActions: [])
    }
    let recoveredAction = plan.actionHistory[recoveredIndex]
    var retainedHistory = plan.actionHistory
    retainedHistory.remove(at: recoveredIndex)
    let removedIds = Set(drafts.map(\.id))
    var normalized = plan
    normalized.actions = [recoveredAction]
    normalized.actionHistory = retainedHistory
    normalized.selectedAgentOrModel = recoveredAction.target
    normalized.expectedResult = recoveredAction.result
    normalized.verificationResults = plan.verificationResults.filter { !removedIds.contains($0.actionId) }
    normalized.checkpoints = plan.checkpoints.filter { !removedIds.contains($0.actionId) }
    normalized.validation = AgentPlanValidator.validate(normalized)
    return AgentPlanLifecycleNormalization(plan: normalized, removedActions: drafts)
  }

  private static func retireLegacyRuntimeFallback(
    plan: AgentPlan,
    drafts: [AgentAction]
  ) -> AgentPlanLifecycleNormalization {
    guard var retired = drafts.last else {
      return AgentPlanLifecycleNormalization(plan: plan, removedActions: [])
    }
    retired.target = taskCompleteTarget
    retired.status = .failed
    retired.description = "Task routing failed"
    retired.requiresConfirmation = false
    retired.result = "No Agent or model accepted this task. Send it again to retry with current resources."
    retired.evidence = "retired_legacy_runtime_fallback"
    var normalized = plan
    normalized.actions = [retired]
    normalized.selectedAgentOrModel = ""
    normalized.expectedResult = retired.result
    normalized.confirmationRequired = false
    normalized.route = AgentRoute()
    normalized.routeRationale = "Legacy internal planner fallback retired."
    let removedIds = Set(drafts.map(\.id))
    normalized.verificationResults = plan.verificationResults.filter { !removedIds.contains($0.actionId) }
    normalized.checkpoints = plan.checkpoints.filter { !removedIds.contains($0.actionId) }
    normalized.validation = AgentPlanValidator.validate(normalized)
    return AgentPlanLifecycleNormalization(plan: normalized, removedActions: drafts)
  }

  private static func resolvedPhase(plan: AgentPlan, fallback: AgentPhase) -> AgentPhase {
    if plan.actions.contains(where: { $0.status == .waitingResponse }) {
      return .waitingResponse
    }
    if plan.actions.contains(where: { $0.status == .running }) {
      return .paused
    }
    if plan.actions.contains(where: { $0.status == .pendingConfirmation || $0.status == .proposed }) {
      return .waitingConfirmation
    }
    if plan.actions.contains(where: { $0.status == .failed }) {
      return .failed
    }
    if plan.actions.contains(where: { $0.status == .blocked }) {
      return .blocked
    }
    if !plan.actions.isEmpty && plan.actions.allSatisfy({ terminalStatuses.contains($0.status) }) {
      return .completed
    }
    return fallback
  }

  private static func trailingRetirableDrafts(_ actions: [AgentAction]) -> [AgentAction] {
    var drafts: [AgentAction] = []
    for action in actions.reversed() {
      guard action.kind == .draftPlan,
        action.target.caseInsensitiveCompare(taskCompleteTarget) != .orderedSame else {
        break
      }
      drafts.append(action)
    }
    return Array(drafts.reversed())
  }

  private static func durableConnectorResult(from task: AgentTaskRecord?) -> String {
    guard let task,
      !isBlank(task.result),
      task.targetTitle.caseInsensitiveCompare(localAgentRuntimeTarget) != .orderedSame,
      connectorRouteKinds.contains(task.routeKind) else {
      return ""
    }
    return task.result
  }

  private static func firstNonBlank(_ values: String...) -> String {
    values.first { !isBlank($0) } ?? ""
  }

  private static func isBlank(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private static let terminalStatuses: Set<AgentActionStatus> = [
    .completed,
    .failed,
    .blocked,
    .rolledBack
  ]
  private static let connectorRouteKinds: Set<AgentRouteKind> = [
    .desktopAgent,
    .cloudModel,
    .localModel
  ]
  private static let taskCompleteTarget = "task-complete"
  private static let localAgentRuntimeTarget = "local-agent-runtime"
  private static let restoredConnectorEvidence = "restored_connector_terminal_result"
}

enum AgentSupervisorRecoveryPolicy {
  static let maximumFormatRepairs = 3
  static let maximumConsecutiveFailures = 2
  private static let bindingKeys: Set<String> = [
    "connector_id", "connector_kind", "connector_adapter_type", "connector_failure_domain",
    "manual_target_locked", "manual_model_id", "agent_model_id", "agent_reasoning_effort", "model_id"
  ]

  static func isSupervisor(_ action: AgentAction) -> Bool {
    action.kind == .callConnector &&
      action.parameters["connector_task_mode"] == "phone_supervised_project_plan_v1"
  }

  static func restoreBinding(_ action: AgentAction, history: [AgentAction]) -> AgentAction {
    guard isSupervisor(action) else { return action }
    let original = history.first { isSupervisor($0) && $0.parameters["manual_target_locked"] == "true" }
    guard let binding = original ?? (action.parameters["manual_target_locked"] == "true" ? action : nil)
    else { return action }
    var restored = action
    restored.target = binding.target
    for key in bindingKeys { restored.parameters[key] = binding.parameters[key] }
    restored.parameters["manual_target_locked"] = "true"
    restored.parameters["auto_reroute_on_failure"] = "false"
    restored.parameters["routing_fallback_ids"] = ""
    return restored
  }

  static func stopReason(action: AgentAction, result: AgentActionResult?, history: [AgentAction]) -> String? {
    guard isSupervisor(action), let result, result.actionId == action.id, !result.success else { return nil }
    if result.metadata["non_retriable"] == "true" || result.metadata["recovery_exhausted"] == "true" {
      return "supervisor_failure_non_retriable"
    }
    if result.metadata["failure_kind"] == "invalid_supervised_project_plan",
       (Int(result.metadata["structured_repair_attempts"] ?? "") ?? 0) >= maximumFormatRepairs {
      return "supervisor_format_repair_exhausted"
    }
    var seen: Set<String> = [action.id]
    var failures = 1
    for step in history.reversed() where [.completed, .failed].contains(step.status) && seen.insert(step.id).inserted {
      guard isSupervisor(step), step.status == .failed else { break }
      failures += 1
      if failures >= maximumConsecutiveFailures { return "supervisor_consecutive_failures" }
    }
    return nil
  }
}

enum AgentRollingPlanPolicy {
  static let replanReasonPrefix = "rolling_batch_completed:"

  static func shouldRequestNextBatch(
    plan: AgentPlan?,
    result: AgentActionResult?
  ) -> Bool {
    guard let plan,
          result?.success == true,
          result?.metadata["awaiting_response"] != "true",
          plan.executionMode != .planOnly,
          !isSupervisedProjectPlan(plan),
          plan.plannerProfile.hasPrefix("guarded-model:"),
          !plan.actions.contains(where: isOpenForRollingBatch),
          !plan.actions.contains(where: closesFromVerifiedEvidence) else {
      return false
    }
    return true
  }

  static func reason(plan: AgentPlan, result: AgentActionResult?) -> String {
    var value = replanReasonPrefix
    value += "revision=\(plan.revision)"
    value += ";completed=\(plan.actions.filter { $0.status == .completed }.count)"
    if let actionId = result?.actionId.trimmingCharacters(in: .whitespacesAndNewlines),
       !actionId.isEmpty {
      value += ";last_action=\(String(actionId.prefix(160)))"
    }
    return value + ";decide=continue_or_finalize_from_verified_evidence"
  }

  static func isBatchBoundaryReason(_ reason: String) -> Bool {
    reason.hasPrefix(replanReasonPrefix)
  }

  static func closesFromVerifiedEvidence(_ action: AgentAction) -> Bool {
    action.kind == .draftPlan &&
      action.target.caseInsensitiveCompare("task-complete") == .orderedSame
  }

  private static func isOpenForRollingBatch(_ action: AgentAction) -> Bool {
    [.proposed, .pendingConfirmation, .running, .waitingResponse].contains(action.status)
  }

  private static func isSupervisedProjectPlan(_ plan: AgentPlan) -> Bool {
    if plan.plannerProfile.localizedCaseInsensitiveContains("supervised") {
      return true
    }
    return (plan.actionHistory + plan.actions).contains { action in
      let mode = action.parameters["connector_task_mode"] ?? ""
      return mode.localizedCaseInsensitiveContains("supervised")
    }
  }
}

struct AgentVerifiedWorkspaceVideo: Equatable, Sendable {
  let workspaceId: String
  let path: String
  let sha256: String
  let size: Int64
}

enum AgentCompletionEvidencePolicy {
  static func isAnswerOnly(
    history: [AgentAction],
    descriptorFor: (String) -> AgentNativeToolDescriptor?
  ) -> Bool {
    history.allSatisfy { action in
      if AgentRollingPlanPolicy.closesFromVerifiedEvidence(action) { return action.status == .completed }
      guard action.kind == .callNativeTool, action.status == .completed,
            descriptorFor(toolId(action))?.effect == .readOnly else { return false }
      return !hasUnverifiedOutcome(action)
    }
  }

  static func hasUnverifiedOutcome(_ action: AgentAction) -> Bool {
    if [.proposed, .pendingConfirmation, .running, .waitingResponse].contains(action.status) { return true }
    return [action.evidence, action.result].contains { value in
      let decoded = decodeObject(value)
      return decoded?.string("code").lowercased() == "effect_outcome_unknown" ||
        ["unknown", "uncertain", "unverified"].contains(decoded?.string("outcome").lowercased() ?? "")
    }
  }

  static func missingEvidence(
    requirements: AgentCompletionRequirements?,
    history: [AgentAction],
    answerOnly: Bool = false
  ) -> [String] {
    guard let requirements else {
      return answerOnly ? [] : ["model-declared completion_requirements (publication and phone_linux)"]
    }
    let completedTools = Set(history.filter(hasVerifiedCompletionReceipt).map(toolId))
    var missing: [String] = []
    for outcome in requirements.outcomes ?? [] {
      if let reason = missingObservedOutcome(outcome, history: history) {
        missing.append("Observed outcome \(outcome.id): \(reason). Inspect the existing receipt or obtain a fresh read-only observation; do not blindly repeat a mutation.")
      }
    }
    let timerTool = AgentNativeToolAgentActionAdapter.defaultToolId(.setAlarm)
    if let timer = history.last(where: { action in
      guard action.kind == .callNativeTool, toolId(action) == timerTool,
            ![.proposed, .pendingConfirmation, .blocked].contains(action.status) else { return false }
      let input = decodeObject(action.parameters["input_json"] ?? "")
      let arguments = input?["parameters"]?.objectValue ?? input
      return arguments?["timer_operation"] != nil || arguments?["timer_seconds"] != nil ||
        decodeObject(action.evidence)?["metadata"]?.objectValue?.string("schedule") == "timer"
    }) {
      let metadata = decodeObject(timer.evidence)?["metadata"]?.objectValue
      if timer.status != .completed || metadata?.string("completion_verified") != "true" ||
          UUID(uuidString: metadata?.string("operation_id") ?? "") == nil {
        missing.append("a verified phone timer receipt with the observed operation ID and current state")
      }
    }
    if requirements.phoneLinux && !completedTools.contains(runtimeExecute) {
      missing.append("a successful galaxyssi.runtime.execute receipt from the phone Linux guest")
    }
    switch requirements.publication {
    case .none:
      break
    case .commit where !completedTools.contains(repositoryCommit):
      missing.append("a successful commit of the verified phone project")
    case .push where !completedTools.contains(repositoryPush):
      missing.append("a successful push of the verified project branch")
    case .pullRequest where completedTools.isDisjoint(with: pullRequestTools):
      missing.append("a successfully created pull request with its URL")
    default:
      break
    }
    for artifact in requirements.artifacts ?? [] where verifiedVideo(artifact, history: history) == nil {
      missing.append("a verified MP4 export for \(artifact.path) in the current workspace")
    }
    return missing
  }

  static func verifiedVideo(_ artifact: AgentVideoArtifactRequirement, history: [AgentAction]) -> AgentVerifiedWorkspaceVideo? {
    for action in history.reversed() where action.kind == .callNativeTool &&
      toolId(action) == AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode {
      guard let output = decodeObject(action.evidence),
            output.string("workspace_id") == artifact.workspaceId,
            output.string("destination_path") == artifact.path else { continue }
      guard action.status == .completed, output.string("mime_type") == "video/mp4",
            let evidence = output["video_openability"]?.objectValue,
            (evidence["duration_ms"]?.intValue ?? 0) > 0,
            (evidence["decoded_frame_width"]?.intValue ?? 0) > 0,
            (evidence["decoded_frame_height"]?.intValue ?? 0) > 0,
            let size = output["size_bytes"]?.intValue, (16...268_435_456).contains(size),
            let sha = output["sha256"]?.stringValue,
            sha.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else { return nil }
      return AgentVerifiedWorkspaceVideo(workspaceId: artifact.workspaceId, path: artifact.path, sha256: sha, size: size)
    }
    return nil
  }

  static func compactVideoEvidence(toolId: String, output: String) -> String? {
    guard toolId == AgentIOSMediaNativeToolCatalog.mediaFFmpegTranscode,
          let object = decodeObject(output), object.string("mime_type") == "video/mp4",
          object["video_openability"]?.objectValue != nil else { return nil }
    let keys: Set<String> = ["workspace_id", "destination_path", "mime_type", "size_bytes", "sha256", "video_openability"]
    return AgentMcpJSONCodec.stringify(object.filter { keys.contains($0.key) })
  }

  private static func hasVerifiedCompletionReceipt(_ action: AgentAction) -> Bool {
    guard action.status == .completed else { return false }
    let id = toolId(action)
    guard terminalEvidenceTools.contains(id) else { return true }
    guard let output = decodeObject(action.evidence) else { return false }
    switch id {
    case runtimeExecute:
      return output["exit_code"]?.intValue == 0
    case repositoryCommit:
      return isGitCommit(output.string("commit"))
    case repositoryPush:
      return !output.string("branch").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case createPullRequest:
      return hasValidPullRequest(output, numberKey: "number", urlKey: "url")
    case publishPullRequest:
      return hasValidPullRequest(
        output,
        numberKey: "pull_request_number",
        urlKey: "pull_request_url"
      )
    case finalizePullRequest:
      return isGitCommit(output.string("commit")) && hasValidPullRequest(
        output,
        numberKey: "pull_request_number",
        urlKey: "pull_request_url"
      )
    default:
      return true
    }
  }

  private static func toolId(_ action: AgentAction) -> String {
    let parameter = action.parameters["tool_id"]?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return parameter.isEmpty ? action.target : parameter
  }

  private static func decodeObject(_ value: String) -> AgentMcpJSONObject? {
    guard let data = value.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(AgentMcpJSONObject.self, from: data)
  }

  private static func isGitCommit(_ value: String) -> Bool {
    value.range(of: #"^[0-9a-fA-F]{7,64}$"#, options: .regularExpression) != nil
  }

  private static func hasValidPullRequest(
    _ output: AgentMcpJSONObject,
    numberKey: String,
    urlKey: String
  ) -> Bool {
    guard (output[numberKey]?.intValue ?? 0) > 0 else { return false }
    return output.string(urlKey).range(
      of: #"^https://github\.com/[^/\s]+/[^/\s]+/pull/[1-9][0-9]*$"#,
      options: .regularExpression
    ) != nil
  }

  private static let runtimeExecute = AgentIOSOnDeviceRuntimeNativeToolCatalog.execute
  private static let repositoryCommit = AgentIOSProjectRepositoryMutationToolCatalog.commit
  private static let repositoryPush = AgentIOSProjectRepositoryMutationToolCatalog.push
  private static let createPullRequest = "galaxyssi.project.github.pull_request.create"
  private static let publishPullRequest = "galaxyssi.project.github.pull_request.publish"
  private static let finalizePullRequest = "galaxyssi.project.github.pull_request.finalize"
  private static let pullRequestTools: Set<String> = [
    createPullRequest,
    publishPullRequest,
    finalizePullRequest
  ]
  private static let terminalEvidenceTools = pullRequestTools.union([
    runtimeExecute,
    repositoryCommit,
    repositoryPush
  ])

  private static func missingObservedOutcome(_ outcome: AgentObservedCompletion, history: [AgentAction]) -> String? {
    func receipt(_ action: AgentAction) -> AgentMcpJSONObject? { decodeObject(action.evidence) }
    func isDifferentSubject(_ output: AgentMcpJSONObject?) -> Bool {
      outcome.subject.contains { path, expected in
        guard case let .string(actual) = value(at: path, in: output) else { return false }
        return actual != expected
      }
    }
    func dispatched(_ action: AgentAction) -> Bool {
      action.kind == .callNativeTool &&
        ![.proposed, .pendingConfirmation, .blocked].contains(action.status)
    }
    let latestMutation: Int
    if outcome.afterToolId.isEmpty {
      latestMutation = -1
    } else {
      guard let index = history.lastIndex(where: {
        dispatched($0) && toolId($0) == outcome.afterToolId &&
          (outcome.afterToolId != outcome.toolId || !isDifferentSubject(receipt($0)))
      }) else { return "required action has no receipt" }
      guard history[index].status != .rolledBack, !hasUnverifiedOutcome(history[index]) else {
        return "required action is unsettled or rolled back"
      }
      latestMutation = index
    }
    for index in history.indices.reversed() where index >= latestMutation {
      let action = history[index]
      guard dispatched(action), toolId(action) == outcome.toolId else { continue }
      let output = receipt(action)
      if isDifferentSubject(output) { continue }
      guard let output, outcome.subject.allSatisfy({ value(at: $0.key, in: output) == .string($0.value) }) else {
        return "latest receipt does not identify the requested subject"
      }
      let metadata = output["metadata"]?.objectValue
      guard action.status == .completed, !hasUnverifiedOutcome(action),
            output["state_verified"] != .bool(false), output["delivery_verified"] != .bool(false),
            metadata?.string("business_success_verified") != "false",
            metadata?.string("completion_verified") != "false" else {
        return "latest matching receipt is not verified"
      }
      return outcome.checks.allSatisfy { value(at: $0.key, in: output) == $0.value }
        ? nil : "latest matching receipt does not satisfy the required state"
    }
    return "no observation at or after the required action"
  }

  private static func value(at pointer: String, in output: AgentMcpJSONObject?) -> AgentMcpJSONValue? {
    guard let output, pointer.hasPrefix("/") else { return nil }
    return pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
      .reduce(Optional(AgentMcpJSONValue.object(output))) { value, segment in
        let key = segment.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        if let array = value?.arrayValue, let index = Int(key), String(index) == key, array.indices.contains(index) {
          return array[index]
        }
        return value?.objectValue?[key]
      }
  }
}
