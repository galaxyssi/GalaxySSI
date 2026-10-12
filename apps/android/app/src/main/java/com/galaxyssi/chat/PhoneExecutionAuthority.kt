package com.galaxyssi.chat

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.locks.ReentrantLock

/**
 * Process-wide authority for phone side effects.
 *
 * Reasoning and read-only observations may run concurrently. Actions that can
 * change Android, another app, local data, or a remote device are serialized so
 * independent Agent tasks cannot race the same phone surface.
 */
object PhoneExecutionAuthority {
    private const val TASK_ID_PARAMETER = "_galaxyssi_task_id"
    private val sideEffectLock = ReentrantLock(true)
    private val activeSideEffectTask = AtomicReference<String?>(null)
    private val cancelledTasks = ConcurrentHashMap.newKeySet<String>()
    private val cancellationLock = Any()
    private val cancellationListeners = mutableMapOf<String, MutableMap<Any, () -> Unit>>()

    fun guarded(delegate: AgentActionExecutor): AgentActionExecutor = object : AgentActionExecutor {
        override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult {
            val taskId = action.parameters[TASK_ID_PARAMETER].orEmpty().ifBlank { action.id }
            if (isCancelled(taskId)) return cancelledResult(action, taskId)
            if (action.runsOutsidePhoneSideEffectLock()) {
                return delegate.execute(action, screen).withAuthorityMetadata(
                    taskId = taskId,
                    serialized = false
                )
            }

            try {
                sideEffectLock.lockInterruptibly()
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                return cancelledResult(action, taskId)
            }
            activeSideEffectTask.set(taskId)
            return try {
                if (isCancelled(taskId)) cancelledResult(action, taskId)
                else delegate.execute(action, screen).withAuthorityMetadata(taskId = taskId, serialized = true)
            } finally {
                activeSideEffectTask.compareAndSet(taskId, null)
                sideEffectLock.unlock()
            }
        }
    }

    fun requestCancellation(taskId: String) {
        if (taskId.isBlank()) return
        val listeners = synchronized(cancellationLock) {
            if (cancelledTasks.add(taskId)) cancellationListeners[taskId]?.values?.toList().orEmpty()
            else emptyList()
        }
        listeners.forEach { runCatching(it) }
    }

    fun clearCancellation(taskId: String) {
        synchronized(cancellationLock) { if (taskId.isNotBlank()) cancelledTasks -= taskId }
    }

    /** Subscribe before queueing work so STOP cannot be lost between dispatch and execution. */
    internal fun observeCancellation(taskId: String, listener: () -> Unit): AgentNativeToolCancellationRegistration {
        require(taskId.isNotBlank())
        val key = Any()
        val alreadyCancelled = synchronized(cancellationLock) {
            if (taskId in cancelledTasks) true else {
                cancellationListeners.getOrPut(taskId) { linkedMapOf() }[key] = listener
                false
            }
        }
        if (alreadyCancelled) listener()
        return AgentNativeToolCancellationRegistration {
            synchronized(cancellationLock) {
                cancellationListeners[taskId]?.let {
                    it.remove(key)
                    if (it.isEmpty()) cancellationListeners.remove(taskId)
                }
            }
        }
    }

    internal fun cancellationListenerCount(taskId: String): Int = synchronized(cancellationLock) {
        cancellationListeners[taskId]?.size ?: 0
    }

    fun isCancelled(taskId: String): Boolean =
        taskId.isNotBlank() && (taskId in cancelledTasks || Thread.currentThread().isInterrupted)

    fun snapshot(): PhoneExecutionAuthoritySnapshot = PhoneExecutionAuthoritySnapshot(
        activeSideEffectTaskId = activeSideEffectTask.get().orEmpty(),
        queuedSideEffectTasks = sideEffectLock.queueLength,
        cancelledTaskCount = cancelledTasks.size
    )

    private fun cancelledResult(action: AgentAction, taskId: String): AgentActionResult = AgentActionResult(
        actionId = action.id,
        success = false,
        message = "Phone tool execution was cancelled",
        metadata = mapOf(
            "execution_location" to "phone",
            "execution_authority" to "galaxyssi-phone",
            "task_id" to taskId,
            "cancelled" to "true"
        )
    )

    private fun AgentActionResult.withAuthorityMetadata(
        taskId: String,
        serialized: Boolean
    ): AgentActionResult = copy(
        metadata = metadata + mapOf(
            "execution_location" to "phone",
            "execution_authority" to "galaxyssi-phone",
            "task_id" to taskId,
            "serialized_side_effect" to serialized.toString()
        )
    )

    private fun AgentAction.runsOutsidePhoneSideEffectLock(): Boolean =
        kind == AgentActionKind.READ_SCREEN ||
            kind == AgentActionKind.DRAFT_PLAN ||
            kind == AgentActionKind.CALL_CONNECTOR
}

data class PhoneExecutionAuthoritySnapshot(
    val activeSideEffectTaskId: String,
    val queuedSideEffectTasks: Int,
    val cancelledTaskCount: Int
)
