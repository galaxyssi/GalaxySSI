import Foundation

extension AgentHomeView {
  func refreshAgentRuntimeAuditRecords() {
    agentRuntimeAuditRecords = AgentNativeToolDefaultStores
      .makePersistentStores()
      .auditStore
      .list(limit: 12, toolId: "", status: nil)
  }

  func refreshAgentRouteState() {
    modelSelection = AgentModelSelectionSettings.selection(
      for: store.activeAgentConversationId
    )
    refreshAgentRuntimeAuditRecords()
    refreshAgentScreenContext()
  }

  func resetAgentSessionPresentation() {
    agentScreenContextCapturedAtMillis = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    draft = ""
    attachments.removeAll()
    voiceAttachmentSnapshot.removeAll()
    voicePendingAttachments.removeAll()
    agentVoiceDraftSnapshot = nil
    voiceTranscriptionPending = false
    actionTrayPresented = false
    attachmentError = ""
    selectedMessageForDetails = nil
    visibleAgentMessageLimit = Self.agentTranscriptPageSize
    olderTranscriptAnchor = nil
    transcriptTopLoadTriggered = false
    transcriptAutoFollow = true
    transcriptShowLatestButton = false
    retryingAgentMessageIDs.removeAll()
    retryingAgentTaskIDs.removeAll()
    runtimeArtifactPreview = nil
    runtimeArtifactDocument = nil
    runtimeArtifactExportPresented = false
    runtimeArtifactExportFilename = ""
    runtimeArtifactExportSourceURI = ""
    runtimeArtifactError = ""
    runtimeArtifactStatus = ""
    richActionStatus = ""
    recoveringAgentTaskIDs.removeAll()
    approvalActionsInFlight.removeAll()
    cancellingRemoteTaskIDs.removeAll()
    cancellingVoiceRunIDs.removeAll()
    pendingHighRiskApprovalTask = nil
    modelSelection = AgentModelSelectionSettings.selection(for: store.activeAgentConversationId)
    refreshAgentRuntimeAuditRecords()
  }

  func createAgentConversation() {
    coordinator.endLocalAgentSession(sessionId: store.activeAgentConversationId)
    _ = store.createAgentSession(title: t("signalasi.agent_session.new", "New session"))
    resetAgentSessionPresentation()
  }

}
