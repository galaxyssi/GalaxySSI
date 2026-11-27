import Foundation
import UIKit

extension AgentHomeView {
  func sendAgentMessage(
    voiceAttachmentSnapshot: [GalaxySSIDraftAttachment]? = nil,
    voiceAppAnchor: VoiceAppCaptureAnchor? = nil
  ) {
    guard !screenAssistantStopping, screenPageImportTask == nil else { return }
    if let voiceAppAnchor {
      guard coordinator.voiceAppContexts.isForegroundOwner(voiceAppAnchor),
            store.activeAgentConversationId == voiceAppAnchor.conversationID else { return }
    }
    let cleanDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    let outgoingAttachments = AgentVoiceAttachmentSubmissionPolicy.select(
      goalOverride: voiceAttachmentSnapshot == nil ? nil : cleanDraft,
      composerAttachments: attachments,
      attachmentSnapshot: voiceAttachmentSnapshot
    )
    if offerConversationGoal(cleanDraft, hasAttachments: !outgoingAttachments.isEmpty) { return }
    if let session = store.agentSession(id: store.activeAgentConversationId),
       GalaxySSIHealthCareAgentScope.requiresScopedSubmission(session) {
      do {
        guard homeVisible, scenePhase == .active, UIApplication.shared.isProtectedDataAvailable,
              store.canReadAgentTranscript, outgoingAttachments.isEmpty,
              healthCareSubmission == nil, screenAssistantRunID == nil else { throw GalaxySSIHealthRecords.Failure.permission }
        healthCareSubmission = try .init(records: .init(owner: store.profile.identityFingerprint, secrets: store.secrets),
          conversation: session, question: cleanDraft)
        attachmentError = ""
        actionTrayPresented = false
      } catch {
        attachmentError = t("galaxyssi.health.discussion.unavailable", "This discussion or request is no longer available.")
      }
      return
    }
    if offerLocalLabQuery(cleanDraft, hasAttachments: !outgoingAttachments.isEmpty) { return }
    coordinator.updateAgentScreenContext(agentScreenSnapshot.screen)
    if let configuration = AgentDoorAccessConfiguration.enabled(automatic: true),
       let command = configuration.command(cleanDraft) {
      guard outgoingAttachments.isEmpty, homeVisible, scenePhase == .active, UIApplication.shared.isProtectedDataAvailable,
            screenAssistantRunID == nil, screenAssistantConversationID != store.activeAgentConversationId, doorAccessLaunch == nil,
            !store.profile.identityFingerprint.isBlank, !store.activeAgentConversationId.isBlank else {
        attachmentError = GalaxySSIDoorAccessView.text("local_only", "Open the door panel from an active conversation without attachments.",
          language: interfaceLanguage)
        return
      }
      doorAccessLaunch = .init(owner: store.profile.identityFingerprint, conversation: store.activeAgentConversationId,
        configuration: configuration, command: command, automatic: true)
      draft = ""; attachmentError = ""; actionTrayPresented = false
      return
    }
    guard !outgoingAttachments.contains(where: \.requiresInitialComposerImageReview) else {
      attachmentError = t("composer_attachment_review_required", "Review the selected images before sending.")
      return
    }
    let submissionScope = AgentMessageSubmissionScope(owner: store.profile.identityFingerprint,
      conversationId: store.activeAgentConversationId)
    guard submissionScope.matches(owner: store.profile.identityFingerprint,
      conversationId: store.activeAgentConversationId) else { return }
    let submittingContact = contact
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
    let submissionID = submissionScope.requestId
    composerSubmissionID = submissionID
    let submittingConversation = submissionScope.conversationId
    let assistantRunID = screenAssistantConversationID == store.activeAgentConversationId
      ? screenAssistantRunID : nil
    let submission = Task { @MainActor in
      var sensitiveAttachments = outgoingAttachments
      defer {
        sensitiveAttachments.wipeSensitive()
        screenAssistantSubmissions.removeValue(forKey: submissionID)
      }
      guard !Task.isCancelled, assistantRunID == nil || screenAssistantRunID == assistantRunID else { return }
      guard submissionScope.matches(owner: store.profile.identityFingerprint,
        conversationId: store.activeAgentConversationId), homeVisible, scenePhase == .active,
        store.canReadAgentTranscript, UIApplication.shared.isProtectedDataAvailable else { return }
      let sent = await coordinator.send(
        text,
        to: submittingContact,
        attachments: sensitiveAttachments,
        agentGoalOverride: agentGoal,
        voiceAppAnchor: voiceAppAnchor,
        requiredAgentConversationID: submittingConversation,
        requestKind: assistantRunID == nil ? .conversation : .screenAnalysis,
        readOnlyAnalysis: assistantRunID != nil,
        onOutgoing: { outgoing in
          if outgoing.conversationId == submittingConversation, store.activeAgentConversationId == submittingConversation {
            olderTranscriptAnchor = nil
            pendingAgentSwipeDirection = AgentIOSAgentSwipeDirection.down.rawValue
            agentSwipeRequest &+= 1
          }
          guard let assistantRunID, screenAssistantRunID == assistantRunID else { return }
          screenAssistantOwnedTurns.append(outgoing)
        }
      )
      guard !Task.isCancelled, assistantRunID == nil || screenAssistantRunID == assistantRunID else { return }
      guard composerSubmissionID == submissionID else { return }
      guard submissionScope.matches(owner: store.profile.identityFingerprint,
        conversationId: store.activeAgentConversationId), homeVisible, scenePhase == .active,
        store.canReadAgentTranscript, UIApplication.shared.isProtectedDataAvailable else { return }
      for id in outgoingAttachments.map(\.id) { voicePendingAttachments.removeAndWipe(id: id) }
      if !sent {
        if draft.isEmpty, !draftForRecovery.isEmpty {
          draft = draftForRecovery
        }
        let existingIDs = Set(attachments.map(\.id))
        attachments.insert(contentsOf: sensitiveAttachments.filter { !existingIDs.contains($0.id) }, at: 0)
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
    cancelScreenPagePDFImport()
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
