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
      ? t("agent_attachment_default_goal", "Inspect and understand the attached content first. Infer the user's most likely goal from its content, type, conversation context, and common use cases, then directly complete the most helpful relevant action. If several interpretations are reasonable, act on the most probable reversible one and briefly state the assumption. Ask one minimal question only when the content cannot be read or no reasonable intent can be inferred.")
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
