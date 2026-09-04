import SwiftUI

extension AgentHomeView {
  @ViewBuilder
  func recoverableAgentTaskBanner(_ task: AgentTaskRecord) -> some View {
    Button {
      openRecoverableAgentTask(task)
    } label: {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: task.phase == .waitingConfirmation ? "exclamationmark.shield" : "arrow.clockwise.circle")
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(task.phase == .waitingConfirmation ? .orange : .galaxySSIAccent)
          .frame(width: 28, height: 28)
        VStack(alignment: .leading, spacing: 3) {
          Text(t("galaxyssi.agent.recovery.title", "Recoverable Agent task"))
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.galaxySSITextPrimary)
          Text(task.goal.ifBlank(t("galaxyssi.agent_tasks.title", "Agent task")))
            .font(.system(size: 12))
            .foregroundColor(.galaxySSITextSecondary)
            .lineLimit(2)
          Text(agentPhaseLabel(task.phase))
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(task.phase == .waitingConfirmation ? .orange : .galaxySSIAccent)
        }
        Spacer(minLength: 8)
        Image(systemName: "arrow.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundColor(.galaxySSIAccent)
          .frame(width: 28, height: 28)
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.galaxySSIInsightBackground)
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(Color.galaxySSIInsightStroke, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      Text(
        String(
          format: t(
            "galaxyssi.agent.recovery.accessibility",
            "Open recoverable Agent task: %@"
          ),
          task.goal.ifBlank(t("galaxyssi.agent_tasks.title", "Agent task"))
        )
      )
    )
  }

  func openRecoverableAgentTask(_ task: AgentTaskRecord) {
    let sessionID = task.sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionID.isEmpty else {
      recentTasksShortcutActive = true
      return
    }
    guard store.switchAgentSession(sessionID) else {
      recentTasksShortcutActive = true
      return
    }
    resetAgentSessionPresentation()
  }

  func recoverAgentTask(_ rawPayload: String, sourceMessage: ChatMessage? = nil) {
    guard let payload = AgentFailureRecoveryPayload.decode(rawPayload) else {
      richActionStatus = t("galaxyssi.agent.action_status.invalid", "This Agent action is invalid.")
      return
    }
    let conversationID = payload.conversationId.trimmingCharacters(in: .whitespacesAndNewlines)
    let taskID = payload.taskId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !conversationID.isEmpty, !taskID.isEmpty else {
      richActionStatus = t("galaxyssi.agent.action_status.invalid", "This Agent action is invalid.")
      return
    }
    if let sourceMessage {
      let sourceConversationID = sourceMessage.conversationId
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let sourceTurnID = sourceMessage.turnId
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard sourceConversationID == conversationID,
            !sourceTurnID.isEmpty,
            sourceTurnID == payload.turnId.trimmingCharacters(in: .whitespacesAndNewlines) else {
        richActionStatus = t(
          "galaxyssi.agent.action_status.invalid",
          "This Agent action is invalid."
        )
        return
      }
    }
    guard store.switchAgentSession(conversationID) else {
      richActionStatus = t(
        "galaxyssi.agent.action_status.conversation_unavailable",
        "That Agent conversation is no longer available."
      )
      return
    }
    guard !recoveringAgentTaskIDs.contains(taskID) else { return }
    recoveringAgentTaskIDs.insert(taskID)
    let resolvedLanguage = LanguagePolicySettings.resolve(store.languagePolicy.responseLanguage)
    let chinese = resolvedLanguage.lowercased().hasPrefix("zh")
    let instruction = AgentFailureRecoveryPolicy.instruction(payload: payload, chinese: chinese)
    richActionStatus = t("galaxyssi.agent.action_status.recovery_started", "Recovery request started.")
    Task { @MainActor in
      let sent = await coordinator.send(instruction, to: contact)
      recoveringAgentTaskIDs.remove(taskID)
      if !sent {
        richActionStatus = t(
          "galaxyssi.agent.action_status.recovery_failed",
          "The recovery request could not be sent."
        )
      }
    }
  }

  func handleLocalPermissionAction(_ rawChoice: String) {
    guard let choice = AgentPermissionChoice.fromWireValue(rawChoice) else {
      richActionStatus = t("galaxyssi.agent.approval_status.invalid", "This Agent action is invalid.")
      return
    }
    guard let task = pendingConfirmationTask else {
      richActionStatus = t(
        "galaxyssi.agent.approval_status.unavailable",
        "This local approval is no longer available."
      )
      return
    }
    if choice == .denyAlways {
      coordinator.denyLocalNativeAction(taskId: task.taskId)
      richActionStatus = t("galaxyssi.agent.approval_status.denied", "The Agent action was denied.")
    } else {
      coordinator.approveLocalNativeAction(
        taskId: task.taskId,
        remember: choice == .allowAlways,
        sessionScoped: choice == .allowSession
      )
      richActionStatus = t("galaxyssi.agent.approval_status.approved", "The Agent action was approved.")
    }
    resumePendingAgentDeliveryAfterTaskAction()
  }

  func handleRemotePermissionAction(_ rawDecision: String) {
    guard let decision = AgentRemoteApprovalDecision.decode(rawDecision) else {
      richActionStatus = t("galaxyssi.agent.approval_status.invalid", "This Agent action is invalid.")
      return
    }
    let activeConversationID = store.activeAgentConversationId
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !activeConversationID.isEmpty,
          decision.conversationId == activeConversationID else {
      richActionStatus = t(
        "galaxyssi.agent.approval_status.unavailable",
        "This remote approval is not part of the active Agent conversation."
      )
      return
    }
    let operationKey = "\(decision.taskId):\(decision.approvalId):\(decision.actionHash)"
    guard approvalActionsInFlight.insert(operationKey).inserted else {
      richActionStatus = t(
        "galaxyssi.agent.approval_status.pending",
        "This approval request is already being sent."
      )
      return
    }
    richActionStatus = t("galaxyssi.agent.approval_status.sending", "Sending approval decision...")
    Task { @MainActor in
      let published = await coordinator.publishRemoteAgentApproval(decision)
      approvalActionsInFlight.remove(operationKey)
      richActionStatus = published
        ? t("galaxyssi.agent.approval_status.sent", "Approval decision sent.")
        : t("galaxyssi.agent.approval_status.failed", "The approval decision could not be sent.")
    }
  }

}
