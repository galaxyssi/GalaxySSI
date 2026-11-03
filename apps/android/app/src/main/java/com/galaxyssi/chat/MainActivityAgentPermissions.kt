package com.galaxyssi.chat

import android.content.pm.PackageManager

internal fun MainActivity.requestMissingAgentNativePermissions(state: AgentUiState, runtime: MobileNativeAgent,
    conversationId: String, turnId: String): Boolean {
    val pending = AgentRuntimePermissionContinuation.parse(state.lastActionResult) ?: return false
    if (!pending.matches(state.sessionId, conversationId, turnId.ifBlank { state.sessionId }, state.phase, state.plan) ||
        isFinishing || isDestroyed || runtimePlaintextCleared || activeMainTab != PAGE_AGENT ||
        !AppForegroundTracker.isActivityForeground(this) || agentTranscriptStore.activeConversation().id != conversationId) return false
    val missing = pending.permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
    if (missing.isEmpty()) {
        continueAgentPermissionGate(runtime, pending)
        return true
    }
    if (pendingAgentRuntimePermission != null || pendingDirectSystemAction != null ||
        !offeredAgentRuntimePermissions.add(pending.key)) return false
    pendingAgentRuntimePermission = runtime to pending
    requestPermissions(missing.toTypedArray(), REQUEST_AGENT_NATIVE_PERMISSIONS)
    return true
}

internal fun MainActivity.continueAgentPermissionGate(runtime: MobileNativeAgent, pending: AgentRuntimePermissionContinuation) {
    val state = runtime.snapshot()
    if (!pending.matches(state.sessionId, pending.conversationId, pending.turnId, state.phase, state.plan) ||
        pending.permissions.any { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }) return
    val entry = agentTranscriptStore.entriesForTurn(pending.turnId)
        .lastOrNull { it.conversationId == pending.conversationId } ?: return
    runAgentTimelineOperation(entry, runtime, onComplete = { result ->
        requestMissingAgentNativePermissions(result, runtime, pending.conversationId, pending.turnId)
    }) { runtime.continueAfterAndroidPermission(pending) }
}

internal fun MainActivity.continueVisibleAgentPermissionGate() {
    if (initialAgentHydrationPending || runtimePlaintextCleared || !isMobileNativeAgentInitialized()) return
    val runtime = mobileNativeAgent
    if (AgentRuntimePermissionContinuation.parse(runtime.lastActionResult) == null) return
    val state = runtime.snapshot()
    val turn = agentRuntimeTurnIds[runtime].orEmpty().ifBlank {
        state.plan?.let { AgentPlanContinuationScope.resolve(it, runtime.activeConversationContext.conversationId,
            runtime.activeConversationTurnId, state.sessionId)?.turnId }.orEmpty()
    }
    requestMissingAgentNativePermissions(state, runtime, agentTranscriptStore.activeConversation().id, turn)
}
