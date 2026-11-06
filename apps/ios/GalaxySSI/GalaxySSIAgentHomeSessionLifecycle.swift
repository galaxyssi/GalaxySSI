import Foundation

extension AgentHomeView {
  func isCurrentTranscriptWindow(_ owner: AgentTranscriptWindow.Owner?) -> Bool {
    homeVisible && scenePhase == .active && store.canReadAgentTranscript && !transcriptRuntimeCleared &&
      owner?.conversationID == store.activeAgentConversationId && transcriptWindow.owns(owner)
  }

  func refreshTranscriptWindow() {
    guard homeVisible, scenePhase == .active, store.canReadAgentTranscript, !transcriptRuntimeCleared else { return }
    let conversationID = store.activeAgentConversationId
    if transcriptWindow.snapshot.owner?.conversationID == conversationID {
      transcriptWindow.requestRefresh()
    } else {
      let database = store.chatHistoryDatabase
      transcriptWindow.activate(conversationID, pageSize: Self.agentTranscriptPageSize) { id, limit in
        await database.agentTranscriptWindow(conversationId: id, limit: limit)
      }
    }
  }

  func clearAgentTranscriptWindow() {
    transcriptWindow.clear()
    visibleAgentMessageLimit = Self.agentTranscriptPageSize
    olderTranscriptAnchor = nil
    transcriptTopLoadTriggered = false
    transcriptAutoFollow = true
    transcriptShowLatestButton = false
    transcriptContentMinY = 0
  }

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
    cancelScreenPagePDFImport()
    agentScreenContextCapturedAtMillis = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    draft = ""
    attachments.wipeSensitive()
    voiceAttachmentSnapshot.wipeSensitive()
    voicePendingAttachments.wipeSensitive()
    agentVoiceDraftSnapshot = nil
    voiceTranscriptionPending = false
    actionTrayPresented = false
    attachmentError = ""
    clearAgentTranscriptWindow()
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

  func clearAgentRuntimePlaintextPresentation() {
    clearAgentTranscriptWindow()
    committedTurnProgress = AgentCommittedTurnProgress()
    cancelScreenPagePDFImport()
    draft.removeAll(keepingCapacity: false)
    attachments.wipeSensitive()
    voiceAttachmentSnapshot.wipeSensitive()
    voicePendingAttachments.wipeSensitive()
    agentVoiceDraftSnapshot = nil
    voiceTranscriptionPending = false
    actionTrayPresented = false
    attachmentError.removeAll(keepingCapacity: false)
    runtimeArtifactPreview = nil
    runtimeArtifactDocument = nil
    runtimeArtifactExportPresented = false
    runtimeArtifactExportFilename.removeAll(keepingCapacity: false)
    runtimeArtifactExportSourceURI.removeAll(keepingCapacity: false)
    runtimeArtifactError.removeAll(keepingCapacity: false)
    runtimeArtifactStatus.removeAll(keepingCapacity: false)
    richActionStatus.removeAll(keepingCapacity: false)
    pendingHighRiskApprovalTask = nil
    agentClipboardContext = AgentClipboardContext()
    agentNotificationContext = AgentNotificationContext()
    retryingAgentMessageIDs.removeAll(keepingCapacity: false)
    retryingAgentTaskIDs.removeAll(keepingCapacity: false)
    approvalActionsInFlight.removeAll(keepingCapacity: false)
  }

  func createAgentConversation() {
    coordinator.endLocalAgentSession(sessionId: store.activeAgentConversationId)
    _ = store.createAgentSession(title: t("galaxyssi.agent_session.new", "New session"))
    resetAgentSessionPresentation()
  }

}
