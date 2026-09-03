package com.signalasi.chat

import android.content.Context
import android.util.Log

internal object AgentColdBootRecoveryPolicy {
    private val interruptedStatuses = setOf(
        AgentWorkspaceStatus.CREATED,
        AgentWorkspaceStatus.QUEUED,
        AgentWorkspaceStatus.RUNNING
    )

    fun shouldPause(workspace: AgentWorkspace): Boolean =
        workspace.status in interruptedStatuses ||
            (workspace.status == AgentWorkspaceStatus.WAITING_RESPONSE && usesPhoneRuntime(workspace))

    internal fun usesPhoneRuntime(workspace: AgentWorkspace): Boolean {
        val evidence = buildString {
            append(workspace.currentPlanSnapshot)
            workspace.toolCalls.forEach { call ->
                append('\n')
                append(call.toolName)
                append('\n')
                append(call.argumentsJson)
            }
            workspace.eventJournal.forEach { event ->
                append('\n')
                append(event.kind)
                append('\n')
                append(event.payloadJson)
            }
        }.lowercase()
        return PHONE_RUNTIME_MARKERS.any(evidence::contains)
    }

    fun pauseSession(
        snapshot: AgentSessionSnapshot,
        processInstanceId: String,
        nowMillis: Long,
        reason: String
    ): AgentSessionSnapshot {
        val loop = snapshot.executionLoopSnapshot?.let { current ->
            if (!current.phase.isTerminal && current.phase != AgentExecutionLoopPhase.PAUSED) {
                current.copy(
                    phase = AgentExecutionLoopPhase.PAUSED,
                    resumePhase = current.phase.takeIf { it.isActive } ?: current.resumePhase,
                    usage = current.usage.copy(activeSinceMillis = 0L),
                    lastReason = reason,
                    updatedAtMillis = nowMillis,
                    revision = current.revision + 1L
                )
            } else {
                current
            }
        }
        return snapshot.copy(
            phase = AgentPhase.PAUSED,
            currentPlan = snapshot.currentPlan?.recoverInterruptedExecution(),
            lastActionResult = AgentActionResult(
                actionId = "agent-interrupted",
                success = false,
                message = reason
            ),
            executionLoopSnapshot = loop,
            processInstanceId = processInstanceId,
            updatedAtMillis = nowMillis
        )
    }

    private val PHONE_RUNTIME_MARKERS = listOf(
        "signalasi.project.",
        "signalasi.runtime.",
        PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
        PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE
    )
}

internal object AgentColdBootRecoveryCoordinator {
    fun pauseInterruptedTasks(context: Context, reason: String): Int {
        val appContext = context.applicationContext
        val now = System.currentTimeMillis()
        val store = EncryptedAgentWorkspaceStore(appContext)
        val interrupted = store.list().filter { workspace ->
            AgentColdBootRecoveryPolicy.shouldPause(workspace)
        }
        interrupted.forEach { workspace ->
            pauseSessionStore(
                SharedPreferencesAgentSessionStore(appContext, "task:${workspace.workspaceId}"),
                now,
                reason,
                force = true
            )
            val nextSequence = workspace.eventSequence + 1L
            store.upsert(
                workspace.copy(
                    status = AgentWorkspaceStatus.PAUSED,
                    errorMessage = "",
                    eventSequence = nextSequence,
                    eventJournal = (workspace.eventJournal + AgentWorkspaceEvent(
                        sequence = nextSequence,
                        kind = EVENT_KIND,
                        message = reason,
                        timestampMillis = now
                    )).takeLast(AgentWorkspaceLimits.MAX_EVENTS),
                    updatedAtMillis = now
                ),
                expectedRevision = workspace.revision
            )
        }
        pauseSessionStore(SharedPreferencesAgentSessionStore(appContext), now, reason)
        Log.i(TAG, "Paused ${interrupted.size} interrupted task(s) after process restart")
        return interrupted.size
    }

    private fun pauseSessionStore(
        store: AgentSessionStore,
        nowMillis: Long,
        reason: String,
        force: Boolean = false
    ) {
        val snapshot = store.load() ?: return
        val active = snapshot.phase in setOf(AgentPhase.EXECUTING, AgentPhase.VERIFYING) ||
            snapshot.executionLoopSnapshot?.phase?.isActive == true
        if (!active && !force) return
        store.save(
            AgentColdBootRecoveryPolicy.pauseSession(
                snapshot = snapshot,
                processInstanceId = AgentProcessIdentity.instanceId,
                nowMillis = nowMillis,
                reason = reason
            )
        )
    }

    private const val TAG = "SignalASIColdBoot"
    private const val EVENT_KIND = "task.paused.process_restart"
}
