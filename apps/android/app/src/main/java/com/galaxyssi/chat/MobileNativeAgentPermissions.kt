package com.galaxyssi.chat

import android.content.pm.PackageManager
import android.os.Build

internal fun supportedAgentRuntimePermission(permission: String): Boolean =
    permission in AgentRuntimePermissionContinuation.runtimePermissions && when (permission) {
        "android.permission.BLUETOOTH_CONNECT", "android.permission.BLUETOOTH_SCAN" -> Build.VERSION.SDK_INT >= 31
        "android.permission.POST_NOTIFICATIONS" -> Build.VERSION.SDK_INT >= 33
        else -> true
    }

/** Persist before effect claims, so granting access never replays a dispatched side effect. */
internal fun MobileNativeAgent.waitForNativePermissions(action: AgentAction): Boolean {
    if (action.kind != AgentActionKind.CALL_NATIVE_TOOL) return false
    val missing = nativeToolRegistry.lookup(action.parameters["tool_id"].orEmpty())?.descriptor
        ?.requiredPermissions.orEmpty().filter { it.required && supportedAgentRuntimePermission(it.id) }
        .map { it.id }.filter { appContext.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }.distinct()
    if (missing.isEmpty()) return false
    val plan = currentPlan ?: return false
    val scope = AgentPlanContinuationScope.resolve(plan, activeConversationContext.conversationId,
        activeConversationTurnId, sessionId) ?: return false
    val pending = AgentRuntimePermissionContinuation(sessionId, scope.conversationId, scope.turnId.ifBlank { sessionId },
        plan.planId, plan.revision, action.id, missing)
    phase = AgentPhase.BLOCKED
    lastActionResult = pending.result(currentGoal.any { it in '\u3400'..'\u9fff' })
    recordAudit(AgentAuditEvent.ACTION_BLOCKED, "android_permission_before_dispatch:${action.id}")
    saveTaskRecord()
    persistSession()
    return true
}

internal fun MobileNativeAgent.continueAfterAndroidPermission(expected: AgentRuntimePermissionContinuation): AgentUiState {
    val pending = AgentRuntimePermissionContinuation.parse(lastActionResult) ?: return snapshot()
    val plan = currentPlan ?: return snapshot()
    val scope = AgentPlanContinuationScope.resolve(plan, activeConversationContext.conversationId,
        activeConversationTurnId, sessionId) ?: return snapshot()
    if (pending != expected || !pending.matches(sessionId, scope.conversationId, scope.turnId.ifBlank { sessionId }, phase, plan) ||
        pending.permissions.any { appContext.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED } ||
        safetySettingsStore.load().executionPaused) return snapshot()
    // Clearing the gate and persisting the ready plan is idempotent; the existing node journal owns dispatch.
    val loop = executionLoop.snapshot
    if (loop?.phase == AgentExecutionLoopPhase.PAUSED) return snapshot()
    if (loop?.phase == AgentExecutionLoopPhase.BLOCKED) {
        if (!advanceExecutionLoop(AgentExecutionLoopPhase.PLAN, "Android permission granted; rechecking original action",
                pending.actionId, retry = loop.phase.isTerminal)) return snapshot()
    } else if (loop?.phase?.isTerminal == true) return snapshot()
    lastActionResult = null
    phase = AgentPhase.PLANNING
    persistSession()
    recordAudit(AgentAuditEvent.TASK_RESUMED, "android_permission_granted:${pending.actionId}")
    return reconcileExecutionLoop(executeFirstPendingAction())
}
