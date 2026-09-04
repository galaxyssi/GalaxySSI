import SwiftUI

// The Android Agent page keeps routing, transcript, and task state in one
// screen controller. This extension keeps the same projection boundary while
// leaving the SwiftUI layout focused on presentation.
extension AgentHomeView {
  var hasManualSelection: Bool {
    modelSelection.mode == .manual &&
      !modelSelection.targetId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var manualRouteWarning: (title: String, subtitle: String)? {
    guard hasManualSelection else { return nil }
    let targetId = modelSelection.targetId.trimmingCharacters(in: .whitespacesAndNewlines)
    if targetId == "local-llm" {
      let profile = LocalModelRuntimeCatalog.find(modelSelection.modelId)
      let enabled = LocalModelRuntimeSettings.isProfileEnabled(profile)
      let ready = enabled &&
        LocalModelInferenceRuntime.shared.ready(profile: profile)
      guard !ready else { return nil }
      if enabled && LocalModelWhisperResourceArbiter.shared.asrHasPriority() {
        return (
          t("galaxyssi.agent.route.voice_priority_title", "Voice input has priority"),
          t(
            "galaxyssi.agent.route.voice_priority",
            "Local Whisper is kept ready for instant voice input. Choose another route or finish voice input before using the local model."
          )
        )
      }
      return (
        t("galaxyssi.agent.route.unavailable_title", "Selected route unavailable"),
        t(
          "galaxyssi.agent.route.local_unavailable",
          "The selected on-device model is not enabled. Choose another route before sending."
        )
      )
    }

    let callableTargets = AgentCallableTargetCatalog.build(
      contacts: store.visibleContacts,
      apiKey: { store.apiKey(for: $0) }
    )
    guard let target = callableTargets.first(where: { $0.id == targetId }),
          AgentConnectorRouteSelector.isDeliverable(target) else {
      return (
        t("galaxyssi.agent.route.unavailable_title", "Selected route unavailable"),
        t(
          "galaxyssi.agent.route.remote_unavailable",
          "The selected Agent or model is offline. Choose another route before sending."
        )
      )
    }
    return nil
  }

  var automaticRouteWarning: (title: String, subtitle: String)? {
    guard !hasManualSelection else { return nil }

    let hasReadyLocalModel = LocalModelRuntimeSettings.activeProfiles().contains { profile in
      LocalModelRuntimeSettings.isProfileEnabled(profile) &&
        LocalModelInferenceRuntime.shared.ready(profile: profile)
    }
    let hasReadyRemoteTarget = AgentCallableTargetCatalog.build(
      contacts: store.visibleContacts,
      apiKey: { store.apiKey(for: $0) }
    ).contains { target in
      guard target.kind != .device,
            AgentConnectorRouteSelector.isDeliverable(target) else {
        return false
      }
      return target.capabilities.contains { capability in
        capability == .chat || capability == .reasoning || capability == .research
      }
    }
    let hasReadyNativeTool = nativeToolSummary.available > 0
    guard !hasReadyLocalModel && !hasReadyRemoteTarget && !hasReadyNativeTool else {
      return nil
    }

    return (
      t("galaxyssi.agent.model_selection.no_models", "No ready models"),
      t(
        "galaxyssi.agent.model_selection.no_models_subtitle",
        "Configure a cloud model, install a local model, or connect an Agent in Settings."
      )
    )
  }

  var messages: [ChatMessage] {
    let allMessages = store.messages(for: contact.id)
    guard let session = activeAgentSession else {
      return allMessages
    }
    let scopedMessages = store.agentSessionMessages(session.id)
    guard scopedMessages.isEmpty else {
      return scopedMessages
    }
    return allMessages.filter {
      $0.conversationId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  static let agentTranscriptPageSize = 24

  var transcriptMessages: [ChatMessage] {
    guard messages.count > visibleAgentMessageLimit else { return messages }
    return Array(messages.suffix(visibleAgentMessageLimit))
  }

  var hasOlderTranscriptMessages: Bool {
    messages.count > visibleAgentMessageLimit
  }

  var waitingMessageIDs: Set<UUID> {
    AgentReplyWaitingIndicatorPolicy.waitingMessageIDs(
      messages: transcriptMessages,
      pendingTurnIds: activeSessionPendingTurnIds,
      stoppedTurnIds: stoppedAgentReplyTurnIds
    )
  }

  var unboundWaitingTurnIDs: [String] {
    AgentReplyWaitingIndicatorPolicy.unboundTurnIDs(
      messages: transcriptMessages,
      pendingTurnIds: activeSessionPendingTurnIds,
      stoppedTurnIds: stoppedAgentReplyTurnIds
    )
  }

  private var activeSessionPendingTurnIds: Set<String> {
    let pending = coordinator.pendingAgentReplyTurnIds
    guard !pending.isEmpty else { return [] }
    let sessionID = store.activeAgentConversationId
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionID.isEmpty else { return pending }

    let visibleTurnIDs = Set(
      messages.map { AgentReplyWaitingIndicatorPolicy.turnKey(for: $0) }
    )
    let taskTurnIDs = Set(
      activeAgentTasks.map {
        $0.taskId.trimmingCharacters(in: .whitespacesAndNewlines)
      }
      .filter { !$0.isEmpty }
    )
    let sessionTurnIDs = visibleTurnIDs.union(taskTurnIDs)
    return pending.filter { sessionTurnIDs.contains($0) }
  }

  var stoppedAgentReplyTurnIds: Set<String> {
    Set(
      activeSessionTasks
        .filter { AgentReplyWaitingIndicatorPolicy.stopsFor($0.phase) }
        .map { $0.taskId.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    )
  }

  var waitingIndicatorCount: Int {
    waitingMessageIDs.count + unboundWaitingTurnIDs.count
  }

  var latestWaitingIndicatorID: String? {
    if let last = transcriptMessages.last, waitingMessageIDs.contains(last.id) {
      return AgentReplyWaitingIndicatorPolicy.viewID(for: last)
    }
    return unboundWaitingTurnIDs.last.map { turnID in
      AgentReplyWaitingIndicatorPolicy.viewID(forTurnID: turnID)
    }
  }

  var unreadTotal: Int {
    store.visibleContacts.reduce(0) { total, contact in
      total + store.conversationSummary(for: contact.id).unreadCount
    }
  }

  var nativeToolSummary: (total: Int, available: Int) {
    let tools = AgentPhoneNativeToolCatalog.descriptors()
    let available = tools.filter {
      $0.risk != .blocked && $0.availability.status == .available
    }.count
    return (tools.count, available)
  }

  private var callableAgentTargets: [AgentCallableTarget] {
    AgentCallableTargetCatalog.build(
      contacts: store.visibleContacts,
      apiKey: { store.apiKey(for: $0) }
    )
  }

  var availableCallableTargetCount: Int {
    callableAgentTargets.filter { AgentConnectorRouteSelector.isDeliverable($0) }.count
  }

  var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
  }

  var activeAgentTasks: [AgentTaskRecord] {
    activeSessionTasks.filter { task in
      guard taskBelongsToActiveSession(task) else { return false }
      switch task.phase {
      case .observing, .planning, .waitingConfirmation, .executing, .verifying, .waitingResponse, .paused:
        return true
      case .cancelled, .blocked, .completed, .failed:
        return false
      }
    }
  }

  private var activeSessionTasks: [AgentTaskRecord] {
    let sessionID = store.activeAgentConversationId
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionID.isEmpty else {
      return store.recentAgentTasks(limit: 24)
    }
    let scopedTasks = store.agentTasks(forSession: sessionID, limit: 24)
    return scopedTasks.isEmpty ? store.recentAgentTasks(limit: 24) : scopedTasks
  }

  var recoverableAgentTasksFromOtherSessions: [AgentTaskRecord] {
    let activeSessionID = store.activeAgentConversationId
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !activeSessionID.isEmpty else { return [] }
    let recoverablePhases: [AgentPhase] = [
      .observing,
      .planning,
      .waitingConfirmation,
      .executing,
      .verifying,
      .waitingResponse,
      .paused
    ]
    return store.recentAgentTasks(limit: 50)
      .filter { task in
        let sessionID = task.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        return !sessionID.isEmpty && sessionID != activeSessionID && recoverablePhases.contains(task.phase)
      }
      .prefix(3)
      .map { $0 }
  }

  func taskBelongsToActiveSession(_ task: AgentTaskRecord) -> Bool {
    let activeSessionId = store.activeAgentConversationId
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let taskSessionId = task.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !activeSessionId.isEmpty else {
      return taskSessionId.isEmpty
    }
    return taskSessionId.isEmpty || taskSessionId == activeSessionId
  }

  var activeAgentPhase: AgentPhase? {
    activeAgentTasks.first?.phase
  }

  var agentActionQueueItems: [GalaxySSIAgentActionQueueItem] {
    var seen = Set<String>()
    return activeAgentTasks.flatMap { task -> [GalaxySSIAgentActionQueueItem] in
      let actions: [AgentAction] = task.pendingActions.isEmpty
        ? task.pendingAction.map { [$0] } ?? []
        : task.pendingActions
      return actions.compactMap { action -> GalaxySSIAgentActionQueueItem? in
        let actionID = action.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !actionID.isEmpty, seen.insert("\(task.taskId)-\(actionID)").inserted else {
          return nil
        }
        return GalaxySSIAgentActionQueueItem(task: task, action: action)
      }
    }
  }

  var pendingConfirmationTask: AgentTaskRecord? {
    activeAgentTasks.first { task in
      task.phase == .waitingConfirmation && task.pendingAction != nil
    }
  }

  var activeExecutionTask: AgentTaskRecord? {
    guard pendingConfirmationTask == nil else { return nil }
    return activeAgentTasks.first
  }

  var activeRemoteAgentTask: AgentRemoteTaskStatusSnapshot? {
    guard let session = activeAgentSession else { return nil }
    return coordinator.remoteAgentTaskStatuses.values
      .filter {
        $0.conversationId == session.id &&
          !AgentRemoteTaskStatusPolicy.isTerminal($0.status)
      }
      .max { $0.updatedAtMillis < $1.updatedAtMillis }
  }

  var activeVoiceAgentRuns: [VoiceAgentRunSnapshot] {
    let sessionID = store.activeAgentConversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    return voiceAgentRunRecovery.activeSnapshots
      .filter { snapshot in
        guard !sessionID.isEmpty else { return true }
        return snapshot.conversationId == sessionID || snapshot.sessionId == sessionID
      }
      .sorted { lhs, rhs in
        if lhs.updatedAtMillis != rhs.updatedAtMillis {
          return lhs.updatedAtMillis > rhs.updatedAtMillis
        }
        return lhs.runId < rhs.runId
      }
      .prefix(3)
      .map { $0 }
  }

  var liveExecutionTargetLabel: String? {
    let candidates = [
      activeRemoteAgentTask?.target,
      activeExecutionTask?.targetTitle
    ]
    return candidates
      .map { $0?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
      .first { value in
        !value.isEmpty && !Self.genericExecutionTargetLabels.contains(value.lowercased())
      }
  }

  private static let genericExecutionTargetLabels: Set<String> = [
    "agent or model",
    "cloud models",
    "mobile executor",
    "selected resource",
    "galaxyssi",
    "agent"
  ]

  private var cancellableAgentTask: AgentTaskRecord? {
    activeAgentTasks.first(where: AgentTaskCenterPolicy.cancellable)
  }

  var primaryAgentTask: AgentTaskRecord? {
    activeAgentTasks.first(where: AgentTaskCenterPolicy.resumable) ?? cancellableAgentTask
  }

  var primaryActionResumesTask: Bool {
    primaryAgentTask?.phase == .paused
  }

  var primaryActionApprovesTask: Bool {
    guard let task = primaryAgentTask,
          task.phase == .waitingConfirmation,
          let action = task.pendingAction else {
      return false
    }
    return action.risk.weight < AgentRisk.high.weight
  }

  var primaryActionWaitingForResponse: Bool {
    primaryAgentTask?.phase == .waitingResponse
  }

  var primaryActionNeedsHighRiskConfirmation: Bool {
    guard let task = primaryAgentTask,
          task.phase == .waitingConfirmation,
          let action = task.pendingAction else {
      return false
    }
    return action.risk.weight >= AgentRisk.high.weight
  }

  var blockedAgentTask: AgentTaskRecord? {
    let sessionId = activeAgentSession?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return activeSessionTasks.first { task in
      let taskSessionId = task.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
      let belongsToSession = sessionId.isEmpty || taskSessionId.isEmpty || taskSessionId == sessionId
      return belongsToSession &&
        (task.blocked || task.phase == .blocked) &&
        AgentTaskCenterPolicy.isReusableGoal(task.goal)
    }
  }

  static let voiceTranscriptionPendingViewId = "galaxyssi-voice-transcription-pending"

  var deviceInputPolicy: AgentDeviceInputTargetPolicy {
    AgentDeviceProfileDetector.detect().inputTargetPolicy
  }

  var waitingForAgentReply: Bool {
    guard let latest = messages.last,
          latest.isMine,
          !latest.isSystem else {
      return false
    }
    return latest.deliveryStatus != .failed && !waitingMessageIDs.contains(latest.id)
  }

  static let replyWaitingViewId = "galaxyssi-agent-reply-waiting"
}
