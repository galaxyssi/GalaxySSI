import Foundation

extension AgentHomeView {
  func sendAgentMessage(
    voiceAttachmentSnapshot: [GalaxySSIDraftAttachment]? = nil
  ) {
    coordinator.updateAgentScreenContext(agentScreenSnapshot.screen)
    let cleanDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    let outgoingAttachments = AgentVoiceAttachmentSubmissionPolicy.select(
      goalOverride: voiceAttachmentSnapshot == nil ? nil : cleanDraft,
      composerAttachments: attachments,
      attachmentSnapshot: voiceAttachmentSnapshot
    )
    let text = cleanDraft.ifBlank(attachmentLabel(for: outgoingAttachments))
    let isVoiceSubmission = voiceAttachmentSnapshot != nil
    let agentGoal = cleanDraft.isEmpty && !outgoingAttachments.isEmpty
      ? t("agent_attachment_default_goal", "The user attached files without stating a task. Ask one concise question about what to do and offer four to six concrete actions suited to the file types. Mention only the file names; do not inspect, summarize, or return the attachments.")
      : ""
    let draftForRecovery = cleanDraft
    draft = ""
    if let voiceAttachmentSnapshot {
      let consumedIDs = Set(outgoingAttachments.map(\.id))
      attachments.removeAll { consumedIDs.contains($0.id) }
    } else {
      attachments.removeAll()
    }
    actionTrayPresented = false
    attachmentError = ""
    Task { @MainActor in
      var sensitiveAttachments = outgoingAttachments
      defer { sensitiveAttachments.wipeSensitive() }
      let sent = await coordinator.send(
        text,
        to: contact,
        attachments: sensitiveAttachments,
        agentGoalOverride: agentGoal
      )
      voicePendingAttachments.wipeSensitive()
      if !sent {
        if !draftForRecovery.isEmpty {
          draft = draftForRecovery
        }
        restoreAgentVoiceAttachments(sensitiveAttachments)
        if isVoiceSubmission {
          voiceTranscriptionPending = false
        }
        attachmentError = coordinator.lastError
      }
    }
  }

}
