package com.signalasi.chat

import android.view.View

internal fun MainActivity.clearRuntimePlaintextForBackground() {
    if (runtimePlaintextCleared || isChangingConfigurations) return
    runtimePlaintextCleared = true
    agentSessionsDialog?.dismiss()
    runtimePlaintextContactId = selectedContact?.id.orEmpty()
    runtimePlaintextConversationId = agentTranscriptWindow.conversationId.ifBlank {
        agentTranscriptStore.activeConversation().id
    }

    flushChatHistoryForRuntimeBoundary()
    PeerImageThumbnailRepository.clearRuntimeCache()
    messages.values.forEach(MutableList<ChatMessage>::clear)
    summaries.clear()
    messageAdapter?.syncMessages(currentMessages)
    messageList.recycledViewPool.clear()

    agentTranscriptStore.clearRuntimeDecodeCache()
    resetAgentTranscriptRendering(runtimePlaintextConversationId)
    agentTurnGoals.clear()
    agentContextBeforeTurn.clear()
    latestAgentScreenContext = null
    lastRenderedAgentState = null

    agentAttachmentPreviewList.removeAllViews()
    agentAttachmentPreviewScroll.visibility = View.GONE
    agentRecordingTranscript.text = ""
    chatRecordingTranscript.text = ""
    wakeTranscriptText?.text = ""
    wakeReplyPanel?.visibility = View.GONE

    clearRuntimeAsrPlaintext()
    AgentEncryptedPreferenceCache.clearAll()
    RuntimePlaintextProtection.clearKnownTemporaryFiles(applicationContext)
}

internal fun MainActivity.restoreRuntimePlaintextAfterForeground(): Boolean {
    if (!runtimePlaintextCleared) return false
    runtimePlaintextCleared = false
    AgentEncryptedPreferenceCache.clearAll()

    loadChatOverview(force = true)
    runtimePlaintextContactId
        .takeIf(String::isNotBlank)
        ?.let { contactId ->
            loadLatestChatHistory(contactId, force = true, scrollAfterLoad = false)
        }
    resetAgentTranscriptRendering(runtimePlaintextConversationId)
    renderAgentInputAttachments()
    runtimePlaintextContactId = ""
    return true
}

internal fun MainActivity.clearRuntimeAsrPlaintext() {
    liveWhisperSessions.values.forEach { session -> session.close() }
    liveWhisperSessions.clear()
    highAccuracyAsrTurns.values.forEach { turn -> turn.cancel() }
    highAccuracyAsrTurns.clear()
    highAccuracyAsrFinals.clear()
    onlineRealtimeAsrTurns.values.forEach { turn -> turn.close() }
    onlineRealtimeAsrTurns.clear()
    onlineRealtimeAsrFinals.clear()
    voiceSecondPassCoordinator.cancelForInteractiveVoice()
    agentVoiceDraftSnapshot = null
    voiceTraceIdsByTurn.clear()
    voiceTurnContextsByTraceId.clear()
    recordingFile?.delete()
    recordingFile = null
}
