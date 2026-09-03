package com.signalasi.chat

import android.content.Context
import java.util.concurrent.CopyOnWriteArraySet

/** Process-lifetime owner for durable mobile Agent tasks. */
object AgentTaskRuntime {
    @Volatile private var supervisor: AgentTaskSupervisor? = null
    private val livenessListeners = CopyOnWriteArraySet<AgentTaskLivenessListener>()

    fun supervisor(context: Context): AgentTaskSupervisor {
        supervisor?.let { return it }
        return synchronized(this) {
            val applicationContext = context.applicationContext
            AgentAdaptiveConcurrencyRuntime.initialize(applicationContext)
            supervisor ?: AgentTaskSupervisor(
                workspaceStore = EncryptedAgentWorkspaceStore(applicationContext),
                maxConcurrentReadReasoningTasks = AgentAdaptiveConcurrencyPolicy.MAX_CONCURRENCY,
                readReasoningLimitProvider = {
                    AgentAdaptiveConcurrencyRuntime.currentLimit(
                        AgentConcurrencyWorkload.READ_REASONING
                    )
                },
                livenessListener = AgentTaskLivenessListener { signal ->
                    publishLivenessSignal(signal)
                    if (signal.kind == AgentTaskLivenessSignalKind.ASSESSMENT_REQUIRED) {
                        AgentLongTaskRecoveryScheduler.enqueue(
                            applicationContext,
                            signal.workspace.workspaceId,
                            signal.reason
                        )
                    }
                },
                memoryObserver = { workspace -> AgentMemoryPssRuntime.requestCapture(workspace) }
            ).also { created ->
                AgentMemoryPssRuntime.start(applicationContext, created::activeWorkspaces)
                supervisor = created
            }
        }
    }

    fun recoverable(context: Context): List<AgentWorkspace> = supervisor(context).recoverableTasks()

    fun addLivenessListener(listener: AgentTaskLivenessListener) {
        livenessListeners += listener
    }

    fun removeLivenessListener(listener: AgentTaskLivenessListener) {
        livenessListeners -= listener
    }

    private fun publishLivenessSignal(signal: AgentTaskLivenessSignal) {
        livenessListeners.forEach { listener -> runCatching { listener.onSignal(signal) } }
    }
}

internal fun AgentPhase.toWorkspaceStatus(): AgentWorkspaceStatus = when (this) {
    AgentPhase.OBSERVING,
    AgentPhase.PLANNING,
    AgentPhase.EXECUTING,
    AgentPhase.VERIFYING -> AgentWorkspaceStatus.RUNNING
    AgentPhase.WAITING_CONFIRMATION -> AgentWorkspaceStatus.WAITING_CONFIRMATION
    AgentPhase.WAITING_RESPONSE -> AgentWorkspaceStatus.WAITING_RESPONSE
    AgentPhase.PAUSED -> AgentWorkspaceStatus.PAUSED
    AgentPhase.BLOCKED -> AgentWorkspaceStatus.BLOCKED
    AgentPhase.COMPLETED -> AgentWorkspaceStatus.COMPLETED
    AgentPhase.FAILED -> AgentWorkspaceStatus.FAILED
    AgentPhase.CANCELLED -> AgentWorkspaceStatus.CANCELLED
}
