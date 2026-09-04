import Foundation

extension AgentHomeView {
  func handleAgentRichForm(_ block: AgentRichBlock, _ values: [String: String]) {
    let formID = block.id.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !formID.isEmpty else {
      richActionStatus = t("galaxyssi.agent.form.invalid", "This Agent form is invalid.")
      return
    }
    let payload: [String: Any] = [
      "form_id": formID,
      "task_id": block.metadata["task_id"] ?? activeAgentTasks.first?.taskId ?? "",
      "values": values
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
          let encoded = String(data: data, encoding: .utf8) else {
      richActionStatus = t("galaxyssi.agent.form.invalid", "This Agent form is invalid.")
      return
    }
    draft = "\(block.title.ifBlank(t("galaxyssi.agent.form.response", "Form response"))): \(encoded)"
    attachments.removeAll()
    actionTrayPresented = false
    attachmentError = ""
    sendAgentMessage()
    richActionStatus = t("galaxyssi.agent.form.submitted", "Form submitted to Agent.")
  }

  func cancelRemoteAgentTask(_ snapshot: AgentRemoteTaskStatusSnapshot) {
    guard cancellingRemoteTaskIDs.insert(snapshot.id).inserted else { return }
    richActionStatus = t(
      "galaxyssi.agent.remote_status.cancelling",
      "Sending cancellation..."
    )
    Task { @MainActor in
      let sent = await coordinator.cancelRemoteAgentTask(snapshot)
      cancellingRemoteTaskIDs.remove(snapshot.id)
      richActionStatus = sent
        ? t("galaxyssi.agent.remote_status.cancel_sent", "Cancellation sent.")
        : t("galaxyssi.agent.remote_status.cancel_failed", "The cancellation could not be sent.")
    }
  }

  func voiceRunRemoteTask(_ run: VoiceAgentRunSnapshot) -> AgentRemoteTaskStatusSnapshot? {
    coordinator.remoteAgentTaskStatuses.values
      .filter { snapshot in
        snapshot.conversationId == run.conversationId &&
          (snapshot.taskId == run.taskId ||
            snapshot.turnId == run.turnId ||
            String(snapshot.sourceMessageId) == run.sourceMessageId) &&
          !AgentRemoteTaskStatusPolicy.isTerminal(snapshot.status)
      }
      .max { $0.updatedAtMillis < $1.updatedAtMillis }
  }

  func cancelVoiceAgentRun(_ run: VoiceAgentRunSnapshot) {
    guard cancellingVoiceRunIDs.insert(run.runId).inserted else { return }
    richActionStatus = t(
      "galaxyssi.agent.remote_status.cancelling",
      "Sending cancellation..."
    )
    Task { @MainActor in
      let sent: Bool
      if let remoteTask = voiceRunRemoteTask(run) {
        sent = await coordinator.cancelRemoteAgentTask(remoteTask)
      } else {
        sent = await coordinator.cancelVoiceAgentRun(run)
      }
      if sent {
        _ = VoiceAgentRunBridgeRegistry.shared.markCancellationRequested(sessionId: run.sessionId)
      }
      cancellingVoiceRunIDs.remove(run.runId)
      richActionStatus = sent
        ? t("galaxyssi.agent.remote_status.cancel_sent", "Cancellation sent.")
        : t("galaxyssi.agent.remote_status.cancel_failed", "The cancellation could not be sent.")
    }
  }

}
