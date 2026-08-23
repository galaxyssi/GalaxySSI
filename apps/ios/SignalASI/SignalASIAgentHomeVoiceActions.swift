import SwiftUI

struct AgentHomeVoiceRiskConfirmation: Identifiable {
  let id = UUID()
  var transcript: String
  var attachments: [SignalASIDraftAttachment]
  var risk: VoiceCommandRisk
  var correctionReview: VoiceTranscriptCorrectionReview?
  var sessionId: String
}

extension AgentHomeView {
  func sendAgentVoiceTranscript(_ submission: SignalASIVoiceTranscriptSubmission) {
    let cleanTranscript = submission.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let draftSnapshot = agentVoiceDraftSnapshot
    agentVoiceDraftSnapshot = nil
    let capturedAttachments = voiceAttachmentSnapshot
    voiceAttachmentSnapshot.removeAll()
    guard !cleanTranscript.isEmpty else {
      voiceTranscriptionPending = false
      voicePendingAttachments.removeAll()
      restoreAgentVoiceAttachments(capturedAttachments)
      attachmentError = t("voice_no_speech", "No speech captured.")
      return
    }
    if let draftSnapshot {
      voiceTranscriptionPending = false
      voicePendingAttachments.removeAll()
      guard draftSnapshot.conversationID == store.activeAgentConversationId else { return }
      let risk = DefaultVoiceCommandRiskClassifier.classify(cleanTranscript)
      let sessionId = registerAgentVoiceExecution(submission, risk: risk)
      VoiceExecutionLedgerBridge.markUserEdited(sessionId: sessionId)
      persistAgentVoiceCorrection(
        submission.correctionReview,
        risk: risk,
        userEdited: true
      )
      let currentDraft = draft.ifBlank(draftSnapshot.text)
      let mergedDraft = AgentVoiceTranscriptPolicy.mergeDraftWithTranscript(
        draft: currentDraft,
        transcript: cleanTranscript
      )
      guard !mergedDraft.isEmpty else { return }
      draft = mergedDraft
      actionTrayPresented = false
      attachmentError = ""
      return
    }
    let risk = DefaultVoiceCommandRiskClassifier.classify(cleanTranscript)
    let sessionId = registerAgentVoiceExecution(submission, risk: risk)
    persistAgentVoiceCorrection(submission.correctionReview, risk: risk)
    if risk >= .high {
      voiceTranscriptionPending = false
      voicePendingAttachments.removeAll()
      draft = cleanTranscript
      actionTrayPresented = false
      pendingVoiceRiskConfirmation = AgentHomeVoiceRiskConfirmation(
        transcript: cleanTranscript,
        attachments: capturedAttachments,
        risk: risk,
        correctionReview: submission.correctionReview,
        sessionId: sessionId
      )
      return
    }
    guard VoiceExecutionLedgerBridge.claimPrimaryDispatch(sessionId: sessionId) else {
      voiceTranscriptionPending = false
      voicePendingAttachments.removeAll()
      restoreAgentVoiceAttachments(capturedAttachments)
      return
    }
    voiceTranscriptionPending = true
    voicePendingAttachments = capturedAttachments
    draft = cleanTranscript
    sendAgentMessage(voiceAttachmentSnapshot: capturedAttachments)
  }

  func executeAgentVoiceRiskConfirmation(_ confirmation: AgentHomeVoiceRiskConfirmation) {
    guard VoiceExecutionLedgerBridge.claimPrimaryDispatch(sessionId: confirmation.sessionId) else {
      return
    }
    voiceTranscriptionPending = true
    voicePendingAttachments = confirmation.attachments
    draft = confirmation.transcript
    sendAgentMessage(voiceAttachmentSnapshot: confirmation.attachments)
  }

  func editAgentVoiceRiskConfirmation(_ confirmation: AgentHomeVoiceRiskConfirmation) {
    VoiceExecutionLedgerBridge.markUserEdited(sessionId: confirmation.sessionId)
    if let sessionId = confirmation.correctionReview?.sessionId {
      _ = VoiceCorrectionJournal.shared.markUserEdited(sessionId: sessionId)
    }
    voiceTranscriptionPending = false
    voicePendingAttachments.removeAll()
    draft = confirmation.transcript
    restoreAgentVoiceAttachments(confirmation.attachments)
    actionTrayPresented = false
    attachmentError = ""
    composerFocusRequest += 1
  }

  private func registerAgentVoiceExecution(
    _ submission: SignalASIVoiceTranscriptSubmission,
    risk: VoiceCommandRisk
  ) -> String {
    VoiceExecutionLedgerBridge.register(
      sessionId: submission.sessionId,
      text: submission.text,
      correctionReview: submission.correctionReview,
      risk: risk
    )
  }

  private func persistAgentVoiceCorrection(
    _ review: VoiceTranscriptCorrectionReview?,
    risk: VoiceCommandRisk,
    userEdited: Bool = false
  ) {
    guard let review else { return }
    _ = VoiceCorrectionJournal.shared.persist(
      review: review,
      conversationId: store.activeAgentConversationId,
      turnId: review.sessionId,
      risk: risk,
      userEdited: userEdited
    )
  }

  func voiceRiskLabel(_ risk: VoiceCommandRisk) -> String {
    switch risk {
    case .critical:
      return t("signalasi.voice.risk_critical", "critical")
    case .high:
      return t("signalasi.voice.risk_high", "high")
    case .medium:
      return t("signalasi.voice.risk_medium", "medium")
    case .low:
      return t("signalasi.voice.risk_low", "low")
    case .conversation:
      return t("signalasi.voice.risk_conversation", "conversation")
    }
  }

  func beginAgentVoiceCapture() {
    voiceAttachmentSnapshot.removeAll()
    agentVoiceDraftSnapshot = AgentVoiceTranscriptPolicy.draftSnapshot(
      conversationID: store.activeAgentConversationId,
      text: draft
    )
    guard agentVoiceDraftSnapshot == nil else { return }
    voiceAttachmentSnapshot = attachments
    let capturedIDs = Set(attachments.map(\.id))
    attachments.removeAll { capturedIDs.contains($0.id) }
  }

  func restoreAgentVoiceAttachments(_ captured: [SignalASIDraftAttachment]? = nil) {
    let values = captured ?? voiceAttachmentSnapshot
    guard !values.isEmpty else {
      voiceAttachmentSnapshot.removeAll()
      return
    }
    let existingIDs = Set(attachments.map(\.id))
    let restored = values.filter { !existingIDs.contains($0.id) }
    if !restored.isEmpty {
      attachments.insert(contentsOf: restored, at: 0)
    }
    voiceAttachmentSnapshot.removeAll()
  }
}
