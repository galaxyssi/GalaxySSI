package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.provider.AlarmClock
import java.util.concurrent.locks.ReentrantLock

/** Native dispatch first; observations and grounded controls never replay an uncertain creation. */
internal class AgentTimerExecutor(private val context: Context) {
    private val store = AgentDeviceOperationStore(context)

    fun execute(action: AgentAction): AgentActionResult {
        if (!lock.tryLock()) return AgentGoalEvidence.result(action, AgentGoalEvidenceStatus.BLOCKED,
            context.getString(R.string.device_operation_busy), extra = mapOf("error_code" to "device_resource_busy"))
        return try { executeLocked(action) } finally { lock.unlock() }
    }

    private fun executeLocked(action: AgentAction): AgentActionResult {
        val conversation = action.parameters[INTERNAL_CONVERSATION_ID].orEmpty()
        if (conversation.isBlank()) return AgentGoalEvidence.result(action, AgentGoalEvidenceStatus.BLOCKED,
            context.getString(R.string.device_operation_scope_missing), extra = mapOf("error_code" to "missing_operation_scope"))
        val command = action.parameters["timer_operation"].orEmpty().ifBlank { "start" }
        if (command !in setOf("start", "pause", "resume", "cancel", "replace", "inspect"))
            return AgentGoalEvidence.result(action, AgentGoalEvidenceStatus.FAILED, context.getString(R.string.device_operation_invalid))
        val rawSeconds = action.parameters["timer_seconds"]
        val seconds = rawSeconds?.toIntOrNull()
        if (rawSeconds != null && (seconds == null || seconds <= 0))
            return AgentGoalEvidence.result(action, AgentGoalEvidenceStatus.FAILED, context.getString(R.string.device_operation_duration_invalid))
        if (command == "replace" && seconds == null)
            return AgentGoalEvidence.result(action, AgentGoalEvidenceStatus.FAILED, context.getString(R.string.device_operation_replace_duration))
        val previous = store.get(conversation)?.takeIf { it.kind == "timer" }
        val explicitId = action.parameters["operation_id"].orEmpty()
        if (explicitId.isNotEmpty() && previous?.id != explicitId)
            return AgentGoalEvidence.result(action, AgentGoalEvidenceStatus.BLOCKED, context.getString(R.string.device_operation_stale))
        var operation = previous
        if (operation == null || operation.status == "cancelled") {
            if (command != "start" || seconds == null) return AgentGoalEvidence.result(action,
                AgentGoalEvidenceStatus.BLOCKED, context.getString(R.string.device_operation_missing))
            operation = store.save(AgentDeviceOperation(conversation, seconds = seconds))
        } else if (seconds != null && seconds != operation.seconds && command != "replace") {
            return AgentGoalEvidence.result(action, AgentGoalEvidenceStatus.BLOCKED,
                context.getString(R.string.device_operation_replacement_required),
                extra = mapOf("error_code" to "timer_replacement_required", "operation_id" to operation.id))
        }
        operation = store.save(operation.copy(desired = command,
            replacementSeconds = if (command == "replace") seconds else null))
        var justDispatched = false
        if (!operation.dispatched && command == "start") {
            // Claim before the external effect. A crash in startActivity becomes UNKNOWN, never a duplicate.
            operation = store.save(operation.copy(dispatched = true, status = "dispatching", dispatchedAt = System.currentTimeMillis()))
            try {
                context.startActivity(Intent(AlarmClock.ACTION_SET_TIMER)
                    .putExtra(AlarmClock.EXTRA_LENGTH, operation.seconds)
                    .putExtra(AlarmClock.EXTRA_MESSAGE, operation.label)
                    .putExtra(AlarmClock.EXTRA_SKIP_UI, !GalaxySSIAccessibilityService.isActive())
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                justDispatched = true
            } catch (error: Exception) {
                store.save(operation.copy(status = "unknown", evidence = error.javaClass.simpleName))
                return AgentGoalEvidence.result(action, AgentGoalEvidenceStatus.UNKNOWN,
                    context.getString(R.string.device_operation_unknown), error.javaClass.simpleName)
            }
        }
        if (!GalaxySSIAccessibilityService.isActive()) {
            store.save(operation.copy(status = "waiting_accessibility"))
            return AgentGoalEvidence.result(action,
                if (command == "start") AgentGoalEvidenceStatus.DISPATCHED else AgentGoalEvidenceStatus.BLOCKED,
                if (command == "start") context.getString(R.string.device_operation_dispatched, operation.seconds) else context.getString(R.string.device_operation_access_needed),
                extra = mapOf("required_capability" to "accessibility", "operation_id" to operation.id))
        }
        // Samsung handles SET_TIMER and SHOW_TIMERS in the same Activity. Let creation
        // finish before another intent can replace it; never resend SET_TIMER here.
        var frame = if (justDispatched) awaitFrame(operation.label) else GalaxySSIAccessibilityService.readTargetUi()
        if (AgentTimerObservation.read(frame, operation.label) == null) {
            context.startActivity(Intent(AlarmClock.ACTION_SHOW_TIMERS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            frame = awaitFrame(operation.label)
        }
        var sample = AgentTimerObservation.read(frame, operation.label)
        if (sample == null || frame == null) return unverified(action, operation, context.getString(R.string.device_operation_not_found))
        val needsControl = when (command) {
            "start", "resume" -> sample.paused
            "pause" -> !sample.paused
            "cancel", "replace" -> true
            else -> false
        }
        if (needsControl) {
            val node = AgentTimerObservation.control(frame, operation.label, command)
                ?: return unverified(action, operation, context.getString(R.string.device_operation_control_missing))
            val observedFrame = frame
            val result = runCatching { GalaxySSIAccessibilityService.actOnTargetUi(
                observedFrame.windowId, observedFrame.revision, node.path, "click", "") }.getOrNull()
            if (result?.get("accepted") != true) return unverified(action, operation, context.getString(R.string.device_operation_ui_changed))
            if (command in setOf("cancel", "replace")) {
                if (!awaitRemoval(operation.label))
                    return unverified(action, operation, context.getString(R.string.device_operation_cancel_unknown))
                store.save(operation.copy(status = "cancelled", evidence = "label-bound cancel accepted; timer removed"))
                if (command == "replace") {
                    if (seconds == null) return AgentGoalEvidence.result(action, AgentGoalEvidenceStatus.BLOCKED, context.getString(R.string.device_operation_replace_duration))
                    return executeLocked(action.copy(parameters = action.parameters - "operation_id" +
                        mapOf("timer_operation" to "start", "timer_seconds" to seconds.toString())))
                }
                return AgentGoalEvidence.result(action, AgentGoalEvidenceStatus.VERIFIED, context.getString(R.string.device_operation_cancelled), "label-bound timer removed")
            }
            frame = awaitFrame(operation.label, paused = command == "pause")
            sample = AgentTimerObservation.read(frame, operation.label)
        }
        val first = sample
        val minimumRemaining = if (operation.durationVerified || operation.dispatchedAt <= 0) 0 else
            (operation.seconds.toLong() - ((System.currentTimeMillis() - operation.dispatchedAt).coerceAtLeast(0) / 1000) - 2)
                .coerceAtLeast(0).toInt()
        val deadline = SystemClock.elapsedRealtime() + 2500
        while (SystemClock.elapsedRealtime() < deadline) {
            SystemClock.sleep(250)
            val next = AgentTimerObservation.read(GalaxySSIAccessibilityService.readTargetUi(), operation.label)
            val paused = AgentTimerObservation.provesPaused(first, next) &&
                first != null && first.remaining in minimumRemaining..operation.seconds
            val running = AgentTimerObservation.provesRunning(first, next, operation.seconds, minimumRemaining)
            if ((command == "pause" && paused) || (command in setOf("start", "resume") && running) ||
                (command == "inspect" && (paused || running))) {
                val evidence = "label=${operation.label}; remaining=${first?.remaining}->${next?.remaining}; paused=$paused"
                store.save(operation.copy(status = if (paused) "paused" else "running", evidence = evidence, durationVerified = true))
                val message = when {
                    paused -> context.getString(R.string.device_operation_paused)
                    command == "inspect" -> context.getString(R.string.device_operation_running, next?.remaining)
                    command == "resume" -> context.getString(R.string.device_operation_resumed)
                    else -> context.getString(R.string.device_operation_started, operation.seconds)
                }
                return AgentGoalEvidence.result(action, AgentGoalEvidenceStatus.VERIFIED, message, evidence,
                    mapOf("operation_id" to operation.id))
            }
        }
        return unverified(action, operation, context.getString(R.string.device_operation_unverified))
    }

    private fun awaitFrame(label: String, paused: Boolean? = null): PhoneUiSnapshot? {
        val deadline = SystemClock.elapsedRealtime() + 2500
        do {
            val frame = GalaxySSIAccessibilityService.readTargetUi()
            val sample = AgentTimerObservation.read(frame, label)
            if (sample != null && (paused == null || sample.paused == paused)) return frame
            SystemClock.sleep(150)
        } while (SystemClock.elapsedRealtime() < deadline)
        return null
    }

    private fun awaitRemoval(label: String): Boolean {
        val deadline = SystemClock.elapsedRealtime() + 2500
        var previous: PhoneUiSnapshot? = null
        do {
            val frame = GalaxySSIAccessibilityService.readTargetUi()
            if (AgentTimerObservation.provesRemoved(frame, label)) {
                if (previous != null && frame != null && frame.observedAt > previous.observedAt) return true
                previous = frame
            } else previous = null
            SystemClock.sleep(150)
        } while (SystemClock.elapsedRealtime() < deadline)
        return false
    }

    private fun unverified(action: AgentAction, op: AgentDeviceOperation, message: String): AgentActionResult {
        store.save(op.copy(status = "unknown", evidence = message))
        return AgentGoalEvidence.result(action, AgentGoalEvidenceStatus.UNKNOWN, message,
            extra = mapOf("operation_id" to op.id, "next_action" to "inspect_phone_ui_before_recovery"))
    }

    companion object { private val lock = ReentrantLock() }
}
