package com.galaxyssi.chat

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

    fun belongsToPreviousProcess(snapshot: AgentSessionSnapshot, processInstanceId: String): Boolean =
        snapshot.processInstanceId != processInstanceId &&
            snapshot.phase !in setOf(AgentPhase.COMPLETED, AgentPhase.CANCELLED, AgentPhase.FAILED) &&
            snapshot.lastActionResult?.actionId != "agent-paused"

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
            currentPlan = if (snapshot.pendingPlanning?.isReplanning == true) snapshot.currentPlan
                else snapshot.currentPlan?.recoverInterruptedExecution(),
            lastActionResult = snapshot.lastActionResult?.takeIf {
                it.metadata["plan_node_recovery_error"] == "true" ||
                    it.metadata["active_plan_recovery_error"] == "true"
            } ?: AgentActionResult(
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
        "galaxyssi.project.",
        "galaxyssi.runtime.",
        PHONE_SUPERVISED_PROJECT_CONNECTOR_MODE,
        PHONE_SUPERVISED_PROJECT_PLANNER_PROFILE
    )
}

internal object AgentColdBootRecoveryCoordinator {
    @Synchronized
    fun pauseInterruptedTasks(context: Context, reason: String): Int {
        val appContext = context.applicationContext
        val paused = pauseInterruptedTasks(
            store = EncryptedAgentWorkspaceStore(appContext),
            sessionStore = { SharedPreferencesAgentSessionStore(appContext, "task:$it") },
            rootSessionStore = SharedPreferencesAgentSessionStore(appContext),
            journal = EncryptedAgentPlanNodeJournal(appContext),
            activeWorkspaceIds = AgentTaskRuntime::activeWorkspaceIds,
            processInstanceId = AgentProcessIdentity.instanceId,
            now = System.currentTimeMillis(), reason = reason
        )
        Log.i(TAG, "Paused $paused interrupted task(s) after process restart")
        return paused
    }

    @Synchronized
    internal fun pauseInterruptedTasks(
        store: AgentWorkspaceStore,
        sessionStore: (String) -> AgentSessionStore,
        rootSessionStore: AgentSessionStore,
        journal: AgentPlanNodeJournal,
        activeWorkspaceIds: () -> Set<String>,
        processInstanceId: String,
        now: Long,
        reason: String
    ): Int {
        val interrupted = store.list().filter { workspace ->
            workspace.workspaceId !in activeWorkspaceIds() &&
                !workspace.cancellationRequested && AgentColdBootRecoveryPolicy.shouldPause(workspace)
        }
        var paused = 0
        interrupted.forEach { workspace ->
            if (!pauseSessionStore(
                sessionStore(workspace.workspaceId),
                now,
                reason,
                journal = journal,
                processInstanceId = processInstanceId,
                force = true
            )) return@forEach
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
            paused++
        }
        pauseSessionStore(rootSessionStore, now, reason, journal, processInstanceId)
        return paused
    }

    private fun pauseSessionStore(
        store: AgentSessionStore,
        nowMillis: Long,
        reason: String,
        journal: AgentPlanNodeJournal,
        processInstanceId: String,
        force: Boolean = false
    ): Boolean {
        val snapshot = store.load() ?: return false
        if (!AgentColdBootRecoveryPolicy.belongsToPreviousProcess(snapshot, processInstanceId)) {
            return false
        }
        val active = snapshot.phase in setOf(AgentPhase.EXECUTING, AgentPhase.VERIFYING) ||
            (snapshot.phase == AgentPhase.PLANNING && snapshot.pendingPlanning != null) ||
            snapshot.executionLoopSnapshot?.phase?.isActive == true
        if (!active && !force) return false
        store.save(
            AgentColdBootRecoveryPolicy.pauseSession(
                snapshot = if (snapshot.pendingPlanning?.isReplanning == true) snapshot
                    else AgentPlanNodeRecovery.restoreOrReport(snapshot, journal),
                processInstanceId = processInstanceId,
                nowMillis = nowMillis,
                reason = reason
            )
        )
        return true
    }

    private const val TAG = "GalaxySSIColdBoot"
    private const val EVENT_KIND = "task.paused.process_restart"
}
