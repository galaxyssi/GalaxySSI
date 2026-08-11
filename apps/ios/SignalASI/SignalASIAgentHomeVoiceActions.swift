import SwiftUI

extension AgentHomeView {
  func sendAgentVoiceTranscript(_ transcript: String) {
    let cleanTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
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
    voiceTranscriptionPending = true
    voicePendingAttachments = capturedAttachments
    draft = cleanTranscript
    sendAgentMessage(voiceAttachmentSnapshot: capturedAttachments)
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
