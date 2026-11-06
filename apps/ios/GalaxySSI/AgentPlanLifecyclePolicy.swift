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
            !hasUnverifiedOutcome(action),
            let descriptor = descriptorFor(toolId(action)) else { return false }
      // These fixed iOS tools only change an isolated browser session, not the website.
      return descriptor.effect == .readOnly || browserContextTools.contains(descriptor.id)
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
    answerOnly: Bool = false,
    observationHistory: [AgentAction]? = nil
  ) -> [String] {
    guard let requirements else {
      return answerOnly ? [] : ["model-declared completion_requirements (publication and phone_linux)"]
    }
    let completedTools = Set(history.filter(hasVerifiedCompletionReceipt).map(toolId))
    var missing = observationDiagnostics(requirements: requirements, history: observationHistory ?? history).map {
      "Observed outcome \($0.string("outcome_id")): \($0.string("code"))"
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
  private static let browserContextTools: Set<String> = [
    AgentIOSWebMediaNativeToolCatalog.browserSessionCreate,
    AgentIOSWebMediaNativeToolCatalog.browserSessionNavigate,
    AgentIOSWebMediaNativeToolCatalog.browserSessionClose
  ]
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

  static func observationDiagnostics(
    requirements: AgentCompletionRequirements?, history: [AgentAction]
  ) -> [AgentMcpJSONObject] {
    guard let outcomes = requirements?.outcomes, !outcomes.isEmpty else { return [] }
    let snapshots = AgentDurablePlanHistoryPolicy.latestSnapshots(history)
    return outcomes.compactMap { missingObservedOutcome($0, history: snapshots) }
  }

  static func priorRequirementsAfterPointerRepair(
    _ previous: AgentCompletionRequirements?,
    candidate: AgentCompletionRequirements?,
    diagnostics: [AgentMcpJSONObject]
  ) -> AgentCompletionRequirements? {
    guard var previous, let candidate, !candidate.reason.isBlank, candidate.canReplace(previous) else { return previous }
    previous.outcomes = previous.outcomes?.map { old in
      guard let replacement = candidate.outcomes?.first(where: { $0.id == old.id }),
            replacement.toolId == old.toolId, replacement.afterToolId == old.afterToolId,
            let diagnostic = diagnostics.first(where: { $0.string("outcome_id") == old.id }),
            diagnostic["fields_partial"] == .bool(false),
            let fields = diagnostic["fields"]?.arrayValue, !fields.isEmpty,
            fields.allSatisfy({ $0.objectValue?.string("issue") == "field_missing_or_null" })
      else { return old }
      let alternatives = fields.compactMap(\.objectValue)
      func preservesValues(_ prior: AgentMcpJSONObject, _ revised: AgentMcpJSONObject) -> Bool {
        let unchanged = Set(prior.keys.filter { prior[$0] == revised[$0] })
        var used = unchanged
        for path in prior.keys.sorted() where !unchanged.contains(path) {
          guard let field = alternatives.first(where: { $0.string("path") == path }),
                let newPath = field["alternative_paths"]?.arrayValue?.compactMap(\.strictStringValue)
                  .first(where: { !used.contains($0) && revised[$0] == prior[path] })
          else { return false }
          used.insert(newPath)
        }
        return true
      }
      guard preservesValues(old.subject.mapValues(AgentMcpJSONValue.string), replacement.subject.mapValues(AgentMcpJSONValue.string)),
            preservesValues(old.checks, replacement.checks)
      else { return old }
      return replacement
    }
    return previous
  }

  static func recordObservationEnvelope(_ result: AgentActionResult, action: inout AgentAction) {
    for key in ["native_tool_id", "native_tool_status", "native_tool_receipt_status"] {
      action.parameters["_galaxyssi_observed_" + key] = result.metadata[key]
    }
  }

  private static func missingObservedOutcome(
    _ outcome: AgentObservedCompletion, history: [AgentAction]
  ) -> AgentMcpJSONObject? {
    func failure(_ code: String, _ action: AgentAction? = nil, fields: [AgentMcpJSONObject] = []) -> AgentMcpJSONObject {
      let next: String
      switch code {
      case "required_action_not_observed":
        next = "Inspect execution history; remove after_tool_id only for a genuinely read-only goal. Do not replay an effect for evidence."
      case "required_action_still_pending", "required_action_superseded_unresolved":
        next = "Reconcile the existing action receipt and current state without dispatching again."
      case "required_action_rolled_back":
        next = "Inspect current state and the latest user goal; do not reapply the rolled-back effect without a current request."
      case "subject_not_matched", "checks_not_satisfied":
        next = "Paths are relative to receipt output. Repair missing pointers from the existing receipt without repeating tools. Candidate paths are hints, not proof. For state mismatches, obtain a fresh read without weakening checks or repeating a mutation."
      default:
        next = "Obtain a fresh read-only observation of the requested subject; do not repeat mutations blindly."
      }
      var issue: AgentMcpJSONObject = ["code": .string(code), "outcome_id": .string(outcome.id),
        "tool_id": .string(outcome.toolId), "next_action": .string(next)]
      if !outcome.afterToolId.isEmpty { issue["after_tool_id"] = .string(outcome.afterToolId) }
      if let action {
        issue["action_id"] = .string(String(action.id.prefix(128)))
        issue["action_status"] = .string(action.status.rawValue)
      }
      if !fields.isEmpty {
        issue["fields"] = .array(fields.prefix(8).map { .object($0) })
        issue["fields_partial"] = .bool(fields.count > 8)
      }
      return issue
    }
    func differentSubject(_ output: AgentMcpJSONObject?) -> Bool {
      outcome.subject.contains { path, expected in
        guard let actual = AgentObservedOutputFields.value(at: path, in: output)?.stringValue else { return false }
        return actual != expected
      }
    }
    func interrupted(_ action: AgentAction) -> Bool {
      ["interrupted", "agent_interrupted_execution", agentPlanNodeObservationPendingEvidence].contains(action.evidence)
    }
    func undispatched(_ action: AgentAction) -> Bool {
      if interrupted(action) { return false }
      let open = [AgentActionStatus.proposed.rawValue, AgentActionStatus.pendingConfirmation.rawValue]
      let source = action.parameters[AgentDurablePlanHistoryPolicy.supersededStatusParameter]
      return open.contains(action.status.rawValue) ||
        (action.status == .rolledBack && open.contains(source ?? ""))
    }
    let latestMutation: Int
    if outcome.afterToolId.isEmpty {
      latestMutation = -1
    } else {
      guard let index = history.lastIndex(where: {
        $0.kind == .callNativeTool && !undispatched($0) && $0.status != .blocked &&
          toolId($0) == outcome.afterToolId &&
          (outcome.afterToolId != outcome.toolId ||
            !differentSubject(AgentObservedOutputFields.output(decodeObject($0.evidence))))
      }) else { return failure("required_action_not_observed") }
      let mutation = history[index]
      if mutation.status == .rolledBack {
        let superseded = mutation.parameters[AgentDurablePlanHistoryPolicy.supersededStatusParameter] != nil ||
          mutation.evidence.hasPrefix("superseded_by_plan_revision:")
        return failure(superseded ? "required_action_superseded_unresolved" : "required_action_rolled_back", mutation)
      }
      if interrupted(mutation) || hasUnverifiedOutcome(mutation) {
        return failure("required_action_still_pending", mutation)
      }
      latestMutation = index
    }
    var latestMismatch: AgentMcpJSONObject?
    var stale = false
    for index in history.indices.reversed() {
      let action = history[index]
      guard action.kind == .callNativeTool, !undispatched(action), toolId(action) == outcome.toolId else { continue }
      if index < latestMutation { stale = true; continue }
      guard let raw = decodeObject(action.evidence), let observed = AgentObservedOutputFields.output(raw) else {
        return failure("invalid_receipt", action)
      }
      let wrapped = raw["output"]?.objectValue != nil
      let tools = [action.parameters["_galaxyssi_observed_native_tool_id"],
        wrapped ? raw["tool_id"].map { $0.strictStringValue ?? "" } : nil]
      if tools.compactMap({ $0 }).contains(where: { $0 != outcome.toolId }) {
        return failure("receipt_tool_mismatch", action)
      }
      let identityIssues = AgentObservedOutputFields.issues(expected: outcome.subject.mapValues(AgentMcpJSONValue.string),
        in: observed, comparesIdentity: true)
      if !identityIssues.isEmpty {
        let mismatch = failure("subject_not_matched", action, fields: identityIssues)
        guard differentSubject(observed) else { return mismatch }
        if latestMismatch == nil { latestMismatch = mismatch }
        continue
      }
      guard action.status == .completed else { return failure("observation_not_completed", action) }
      let statuses = [action.parameters["_galaxyssi_observed_native_tool_status"],
        action.parameters["_galaxyssi_observed_native_tool_receipt_status"],
        wrapped ? raw["status"].map { $0.strictStringValue ?? "" } : nil,
        wrapped ? raw["receipt"]?.objectValue?["status"].map { $0.strictStringValue ?? "" } : nil]
      if statuses.compactMap({ $0 }).contains(where: { $0 != "succeeded" }) {
        return failure("receipt_not_succeeded", action)
      }
      if hasUnverifiedOutcome(action) || isUnverifiedObservation(raw) || isUnverifiedObservation(observed) {
        return failure("state_unverified", action)
      }
      let checkIssues = AgentObservedOutputFields.issues(expected: outcome.checks, in: observed, comparesIdentity: false)
      return checkIssues.isEmpty ? nil : failure("checks_not_satisfied", action, fields: checkIssues)
    }
    return latestMismatch ?? failure(stale ? "observation_stale" : "observation_missing")
  }

  private static func isUnverifiedObservation(_ output: AgentMcpJSONObject) -> Bool {
    let metadata = output["metadata"]?.objectValue
    return output["state_verified"] == .bool(false) || output["delivery_verified"] == .bool(false) ||
      metadata?.string("business_success_verified") == "false" || metadata?.string("completion_verified") == "false" ||
      ["dispatched", "blocked", "unknown", "failed"].contains(metadata?.string("goal_status") ?? "") ||
      output.string("code").lowercased() == "effect_outcome_unknown" ||
      ["unknown", "uncertain", "unverified"].contains(output.string("outcome").lowercased())
  }

}

enum AgentObservedOutputFields {
  struct Index {
    var fields: [(path: String, type: String)] = []
    var partial = false

    func alternatives(for path: String) -> [String] {
      let name = path.split(separator: "/").last
      return Array(fields.lazy.filter { $0.path != path && $0.path.split(separator: "/").last == name }
        .prefix(4).map(\.path))
    }
  }

  static func output(_ receipt: AgentMcpJSONObject?) -> AgentMcpJSONObject? {
    receipt?["output"]?.objectValue ?? receipt
  }

  static func isValidPointer(_ path: String) -> Bool {
    path.utf8.count <= 512 &&
      path.range(of: #"^(/(?:[A-Za-z0-9_.-]|~[01])+)+$"#, options: .regularExpression) != nil
  }

  static func value(at pointer: String, in output: AgentMcpJSONObject?) -> AgentMcpJSONValue? {
    guard let output, isValidPointer(pointer) else { return nil }
    let result = pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
      .reduce(Optional(AgentMcpJSONValue.object(output))) { value, segment in
        let key = segment.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        if let array = value?.arrayValue, let index = Int(key), String(index) == key, array.indices.contains(index) {
          return array[index]
        }
        return value?.objectValue?[key]
      }
    return result == .null ? nil : result
  }

  static func index(_ output: AgentMcpJSONObject) -> Index {
    var result = Index()
    var visited = 0
    func visit(_ value: AgentMcpJSONValue, path: String, depth: Int) {
      guard depth <= 12, visited < 512, result.fields.count < 96 else { result.partial = true; return }
      visited += 1
      switch value {
      case .object(let object):
        for key in object.keys.sorted() {
          guard visited < 512, result.fields.count < 96 else { result.partial = true; break }
          visited += 1
          let escaped = key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
          let childPath = path + "/" + escaped
          guard isValidPointer(childPath), let child = object[key] else { result.partial = true; continue }
          visit(child, path: childPath, depth: depth + 1)
        }
      case .array(let array):
        for (offset, child) in array.enumerated() {
          guard visited < 512, result.fields.count < 96 else { result.partial = true; break }
          let childPath = path + "/\(offset)"
          guard isValidPointer(childPath) else { result.partial = true; break }
          visit(child, path: childPath, depth: depth + 1)
        }
      default:
        result.fields.append((path, scalarType(value)))
      }
    }
    visit(.object(output), path: "", depth: 0)
    return result
  }

  static func issues(
    expected: AgentMcpJSONObject, in output: AgentMcpJSONObject, comparesIdentity: Bool
  ) -> [AgentMcpJSONObject] {
    var cachedIndex: Index?
    return expected.keys.sorted().compactMap { path in
      guard let target = expected[path] else { return nil }
      let actual = value(at: path, in: output)
      if comparesIdentity ? actual?.stringValue == target.strictStringValue : actual == target { return nil }
      var issue: AgentMcpJSONObject = ["path": .string(path)]
      if let actual {
        let actualType = scalarType(actual)
        let expectedType = scalarType(target)
        issue["issue"] = .string(actualType == expectedType ? "value_mismatch" : "type_mismatch")
        issue["actual_type"] = .string(actualType)
        issue["expected_type"] = .string(expectedType)
      } else {
        if cachedIndex == nil { cachedIndex = index(output) }
        issue["issue"] = .string("field_missing_or_null")
        issue["alternative_paths"] = .array((cachedIndex?.alternatives(for: path) ?? []).map { .string($0) })
        issue["index_partial"] = .bool(cachedIndex?.partial == true)
      }
      return issue
    }
  }

  private static func scalarType(_ value: AgentMcpJSONValue) -> String {
    switch value {
    case .string: return "string"
    case .int, .double: return "number"
    case .bool: return "boolean"
    case .null: return "null"
    case .array: return "array"
    case .object: return "object"
    }
  }
}
