import Foundation

extension AgentHomeView {
  func sendAgentMessage(
    voiceAttachmentSnapshot: [GalaxySSIDraftAttachment]? = nil
  ) {
    guard !screenAssistantStopping else { return }
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
    if screenAssistantRunID == nil, !screenAssistantConversationID.isEmpty,
       screenAssistantConversationID == store.activeAgentConversationId {
      screenAssistantRunID = UUID()
      screenAssistantStartedAt = Date()
      screenAssistantOwnedTurns = []
    }
    let submissionID = UUID()
    let assistantRunID = screenAssistantConversationID == store.activeAgentConversationId
      ? screenAssistantRunID : nil
    let submission = Task { @MainActor in
      var sensitiveAttachments = outgoingAttachments
      defer {
        sensitiveAttachments.wipeSensitive()
        screenAssistantSubmissions.removeValue(forKey: submissionID)
      }
      guard !Task.isCancelled, assistantRunID == nil || screenAssistantRunID == assistantRunID else { return }
      let sent = await coordinator.send(
        text,
        to: contact,
        attachments: sensitiveAttachments,
        agentGoalOverride: agentGoal,
        onOutgoing: { outgoing in
          guard let assistantRunID, screenAssistantRunID == assistantRunID else { return }
          screenAssistantOwnedTurns.append(outgoing)
        }
      )
      guard !Task.isCancelled, assistantRunID == nil || screenAssistantRunID == assistantRunID else { return }
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
    if assistantRunID != nil { screenAssistantSubmissions[submissionID] = submission }
  }

  func stopScreenAnalysis() {
    guard screenAssistantRunID != nil, !screenAssistantStopping else { return }
    screenAssistantStopping = true
    screenAssistantVoiceCancellationRequest &+= 1
    screenAssistantRunID = nil
    screenAssistantStartedAt = nil
    screenshotPickerPresented = false
    for submission in screenAssistantSubmissions.values { submission.cancel() }
    screenAssistantSubmissions = [:]
    attachments.removeAll { screenAssistantAttachmentIDs.contains($0.id) }
    screenAssistantAttachmentIDs = []
    let ownedTurns = screenAssistantOwnedTurns
    screenAssistantOwnedTurns = []
    Task { @MainActor in
      let sent = await coordinator.cancelScreenAnalysis(ownedTurns)
      screenAssistantStopping = false
      richActionStatus = sent
        ? t("galaxyssi.screen_assistant.stopped", "Analysis stopped. Partial output has been preserved.")
        : t("galaxyssi.screen_assistant.stop_failed", "Analysis stopped locally, but remote cancellation could not be confirmed.")
    }
  }

}
