package com.galaxyssi.chat

import android.app.AlertDialog
import android.content.Intent
import android.provider.Settings
import java.util.UUID

/** Called on the existing routing worker, before schedule controls consume short follow-ups. */
internal fun MainActivity.handleConversationDeviceOperation(goal: String, conversationId: String, turnId: String): Boolean {
    if (AgentTurnMentionRegistry.peek(turnId).isNotEmpty() ||
        CollaborationGroupStore.cached(conversationId)?.members?.isNotEmpty() == true ||
        PhoneAssistantTaskControl.isReadOnly(turnId) ||
        AgentTaskExecutionModePolicy.resolve(goal, mobileNativeAgent.safetySettings().taskExecutionMode).mode == AgentTaskExecutionMode.PLAN_ONLY) return false
    val store = AgentDeviceOperationStore(applicationContext)
    val prior = store.get(conversationId)?.takeIf { it.kind == "timer" && it.status != "cancelled" }
    val seconds = AgentDeviceIntent.exactTimerSeconds(goal)
    val followup = AgentDeviceIntent.followup(goal)
    val action = when {
        seconds != null -> AgentDeviceIntent.action(seconds,
            if (prior != null && prior.seconds != seconds) "replace" else "start", prior?.id.orEmpty())
        prior != null && followup != null -> AgentDeviceIntent.action(
            if (followup == "replace") AgentDeviceIntent.seconds(goal) else null, followup, prior.id)
        else -> return false
    }
    runOnUiThread { executeDirectSystemAction(action, conversationId, turnId) }
    return true
}

internal fun MainActivity.offerDeviceOperationAccess(result: AgentActionResult, conversationId: String) {
    if (result.metadata["required_capability"] != "accessibility" || isFinishing || isDestroyed ||
        GalaxySSIAccessibilityService.isActive() || !AppForegroundTracker.isActivityForeground(this) ||
        runtimePlaintextCleared || activeMainTab != PAGE_AGENT ||
        conversationId != agentTranscriptStore.activeConversation().id) return
    val operationId = result.metadata["operation_id"].orEmpty()
    if (operationId.isBlank() || deviceOperationAccessDialog?.isShowing == true ||
        !offeredDeviceOperationAccessIds.add(operationId)) return
    deviceOperationAccessDialog = AlertDialog.Builder(this).setTitle(R.string.device_operation_access_title)
        .setMessage(R.string.device_operation_access_message)
        .setNegativeButton(android.R.string.cancel, null)
        .setPositiveButton(R.string.device_operation_enable) { _, _ -> startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)) }
        .create().also { dialog ->
            dialog.setOnDismissListener { if (deviceOperationAccessDialog === dialog) deviceOperationAccessDialog = null }
            dialog.show()
        }
}

internal fun MainActivity.offerPendingDeviceOperationAccess(conversationId: String) {
    if (GalaxySSIAccessibilityService.isActive() || isFinishing || isDestroyed || runtimePlaintextCleared ||
        !AppForegroundTracker.isActivityForeground(this) || activeMainTab != PAGE_AGENT ||
        conversationId != agentTranscriptStore.activeConversation().id) return
    agentRoutingExecutor.execute {
        val pending = AgentDeviceOperationStore(applicationContext).get(conversationId)
            ?.takeIf { it.kind == "timer" && it.status == "waiting_accessibility" } ?: return@execute
        runOnUiThread {
            offerDeviceOperationAccess(AgentActionResult(pending.id, false, "", mapOf(
                "required_capability" to "accessibility", "operation_id" to pending.id)), conversationId)
        }
    }
}

internal fun MainActivity.recoverDeviceOperation(action: AgentAction, conversationId: String,
    turnId: String, result: AgentActionResult): Boolean {
    if (action.kind != AgentActionKind.SET_ALARM || result.metadata["goal_status"] != "unknown" ||
        !GalaxySSIAccessibilityService.isActive()) return false
    agentRoutingExecutor.execute {
        val store = AgentDeviceOperationStore(applicationContext)
        val op = store.get(conversationId) ?: return@execute
        store.save(op.copy(status = "model_recovery"))
        val goal = "Continue the pending phone timer. Requested operation=${op.desired}; duration=${op.seconds}s. " +
            "Inspect the actual UI for ${op.label}, repair missing steps and verify the outcome. Never blindly create a duplicate."
        val original = agentTranscriptStore.context(conversationId = conversationId, excludeTurnId = turnId)
        val context = original.copy(summary = listOf(original.summary, op.context(), "Latest observed result: " + result.message)
            .filter(String::isNotBlank).joinToString("\n"))
        executeConcurrentAgentGoal(goal, context, conversationId, turnId)
    }
    return true
}

internal fun MainActivity.resumePendingDeviceOperation() {
    if (!GalaxySSIAccessibilityService.isActive()) {
        offerPendingDeviceOperationAccess(agentTranscriptStore.activeConversation().id)
        return
    }
    agentRoutingExecutor.execute {
        val conversationId = agentTranscriptStore.activeConversation().id
        val store = AgentDeviceOperationStore(applicationContext)
        val pending = store.get(conversationId)?.takeIf { it.status == "waiting_accessibility" } ?: return@execute
        // Claim the continuation before changing foreground windows; onResume must not repeatedly dispatch it.
        if (!store.claimContinuation(pending)) return@execute
        runOnUiThread {
            executeDirectSystemAction(AgentDeviceIntent.action(pending.replacementSeconds, pending.desired, pending.id),
                conversationId, "device-resume-${UUID.randomUUID()}")
        }
    }
}
