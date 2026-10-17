package com.galaxyssi.chat

import android.os.SystemClock
import android.util.Log

internal fun MainActivity.requestForegroundAgentReload() {
    if (initialAgentHydrationPending || !isMobileNativeAgentInitialized()) return
    val runtime = mobileNativeAgent
    val conversationId = agentTranscriptWindow.conversationId
    val turnId = runtime.activeConversationTurnId
    val renderedBeforeLoad = lastRenderedAgentState
    val started = SystemClock.elapsedRealtime()
    fun ownerMatches() = runtime === mobileNativeAgent &&
        conversationId == agentTranscriptWindow.conversationId && turnId == runtime.activeConversationTurnId
    foregroundAgentReload.request(load = { current ->
        val state = runtime.reloadSession { current() && ownerMatches() }
        if (current() && ownerMatches() && state.runningTaskCount == 0 && ScreenPerceptionState.hasRecentVisualCapture()) {
            runtime.observeCurrentScreen()
        } else state
    }, deliver = { result ->
        if (!isDestroyed && !isFinishing && !runtimePlaintextCleared && ownerMatches() &&
            AppForegroundTracker.isActivityForeground(this)) {
            result.onSuccess { state ->
                // A newer stream/task update must win over an older restoration snapshot.
                if (activeMainTab == PAGE_AGENT && !initialAgentHydrationPending && lastRenderedAgentState === renderedBeforeLoad) {
                    renderAgentState(state, conversationId, syncTranscript = false)
                }
                Log.i("GalaxySSIStartup", "resume_agent_async total=${SystemClock.elapsedRealtime() - started}ms")
            }.onFailure { Log.w("GalaxySSIStartup", "resume_agent_async_failed", it) }
        }
    })
}
