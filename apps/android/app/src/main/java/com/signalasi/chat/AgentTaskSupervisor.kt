package com.signalasi.chat

import java.io.Closeable
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableJob
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex

enum class AgentTaskLane {
    READ_REASONING,
    SIDE_EFFECT
}

enum class AgentTaskPriority {
    FOREGROUND,
    NORMAL,
    BACKGROUND
}

object AgentTaskEventKinds {
    const val QUEUED = "task.queued"
    const val RESUMED = "task.resumed"
    const val RUNNING = "task.running"
    const val COMPLETED = "task.completed"
    const val FAILED = "task.failed"
    const val CANCELLED = "task.cancelled"
    const val INTERRUPTED = "task.interrupted"
    const val CHECKPOINT = "task.checkpoint"
    const val WAITING_CONFIRMATION = "task.waiting_confirmation"
    const val WAITING_RESPONSE = "task.waiting_response"
    const val RECOVERY_WAITING_RESPONSE = "task.recovery_waiting_response"
    const val PAUSED = "task.paused"
    const val BLOCKED = "task.blocked"
    const val SNAPSHOT = "task.execution_snapshot"
    const val PERMISSION_REVOKED = "task.permission_revoked"
    const val HEARTBEAT = "task.heartbeat"
    const val PROGRESS = "task.progress"
    const val STALLED = "task.stalled"
    const val TIMED_OUT = "task.timed_out"
    const val LIVENESS_ASSESSMENT_REQUESTED = "task.liveness_assessment_requested"
    const val LATE_RESPONSE = "task.late_response"
    const val RECOVERED_INTERRUPTED = "task.recovered_interrupted"
}

fun interface AgentTaskResumeHook {
    suspend fun resume(context: AgentTaskContext, workspace: AgentWorkspace)
}

class AgentTaskCancellationSource internal constructor(
    private val cancellationJob: CompletableJob,
    private val requestCancellation: (String) -> Boolean
) {
    private val requested = AtomicBoolean(false)
    private val interrupted = AtomicBoolean(false)
    private val cancellationListeners = CopyOnWriteArrayList<() -> Unit>()

    val isCancellationRequested: Boolean
        get() = requested.get()

    val isActive: Boolean
        get() = cancellationJob.isActive

    fun cancel(reason: String = "Task cancellation requested"): Boolean =
        requestCancellation(reason.ifBlank { "Task cancellation requested" })

    fun throwIfCancellationRequested() {
        if (requested.get()) throw CancellationException("Task cancellation requested")
    }

    internal fun asNativeToolCancellationToken(): AgentNativeToolCancellationToken {
        val source = this
        return object : AgentNativeToolCancellationToken {
            override val isCancellationRequested: Boolean
                get() = source.isCancellationRequested || source.interrupted.get()

            override fun invokeOnCancellation(
                listener: () -> Unit
            ): AgentNativeToolCancellationRegistration = source.registerCancellationListener(listener)
        }
    }

    internal fun cancelExecution(reason: String) {
        if (requested.compareAndSet(false, true)) {
            val listeners = cancellationListeners.toList()
            cancellationListeners.clear()
            listeners.forEach { listener -> runCatching(listener) }
        }
        cancellationJob.cancel(CancellationException(reason))
    }

    internal fun interruptExecution(reason: String) {
        interrupted.set(true)
        val listeners = cancellationListeners.toList()
        cancellationListeners.clear()
        listeners.forEach { listener -> runCatching(listener) }
        cancellationJob.cancel(CancellationException(reason))
    }

    internal fun complete() {
        cancellationJob.complete()
    }

    private fun registerCancellationListener(
        listener: () -> Unit
    ): AgentNativeToolCancellationRegistration {
        val active = AtomicBoolean(true)
        val guarded = {
            if (active.getAndSet(false)) listener()
        }
        cancellationListeners += guarded
        if ((requested.get() || interrupted.get()) && cancellationListeners.remove(guarded)) guarded()
        return AgentNativeToolCancellationRegistration {
            active.set(false)
            cancellationListeners.remove(guarded)
        }
    }
}

class AgentTaskHandle internal constructor(
    val workspaceId: String,
    val taskId: String,
    val lane: AgentTaskLane,
    val priority: AgentTaskPriority,
    val cancellationSource: AgentTaskCancellationSource,
    val job: Job
) {
    val isActive: Boolean
        get() = job.isActive

    suspend fun join() {
        job.join()
    }

    fun cancel(reason: String = "Task cancellation requested"): Boolean =
        cancellationSource.cancel(reason)
}

class AgentTaskContext internal constructor(
    val workspaceKey: AgentWorkspaceKey,
    val lane: AgentTaskLane,
    val priority: AgentTaskPriority,
    val cancellationSource: AgentTaskCancellationSource,
    private val supervisor: AgentTaskSupervisor
) {
    fun workspace(): AgentWorkspace = supervisor.requireWorkspace(workspaceKey.workspaceId)

    fun appendEvent(
        kind: String,
        message: String = "",
        payloadJson: String = ""
    ): AgentWorkspace = supervisor.appendEvent(
        workspaceId = workspaceKey.workspaceId,
        kind = kind,
        message = message,
        payloadJson = payloadJson
    )

    fun checkpoint(
        checkpointId: String,
        planSnapshot: String = "",
        stateJson: String = ""
    ): AgentWorkspace = supervisor.checkpoint(
        workspaceId = workspaceKey.workspaceId,
        checkpointId = checkpointId,
        planSnapshot = planSnapshot,
        stateJson = stateJson
    )

    internal fun appendEventAndCheckpoint(
        kind: String,
        message: String,
        payloadJson: String,
        checkpointId: String,
        stateJson: String
    ): AgentWorkspace = supervisor.appendEventAndCheckpoint(
        workspaceId = workspaceKey.workspaceId,
        kind = kind,
        message = message,
        payloadJson = payloadJson,
        checkpointId = checkpointId,
        stateJson = stateJson
    )

    fun heartbeat(
        stage: String = "running",
        message: String = ""
    ): AgentWorkspace = supervisor.heartbeat(
        workspaceId = workspaceKey.workspaceId,
        stage = stage,
        message = message
    )

    fun progress(
        stage: String,
        message: String = ""
    ): AgentWorkspace = supervisor.progress(
        workspaceId = workspaceKey.workspaceId,
        stage = stage,
        message = message
    )

    fun transition(
        status: AgentWorkspaceStatus,
        eventKind: String = "task.status.${status.name.lowercase()}",
        message: String = "",
        payloadJson: String = ""
    ): AgentWorkspace = supervisor.transition(
        workspaceId = workspaceKey.workspaceId,
        status = status,
        eventKind = eventKind,
        message = message,
        payloadJson = payloadJson
    )

    suspend fun ensureActive() {
        cancellationSource.throwIfCancellationRequested()
        currentCoroutineContext().ensureActive()
    }

    fun recordExecutionSnapshot(snapshot: AgentWorkspaceExecutionSnapshot): AgentWorkspace =
        supervisor.recordExecutionSnapshot(workspaceKey.workspaceId, snapshot)

    fun waitForConfirmation(message: String = ""): Nothing = supervisor.deferTask(
        workspaceId = workspaceKey.workspaceId,
        status = AgentWorkspaceStatus.WAITING_CONFIRMATION,
        eventKind = AgentTaskEventKinds.WAITING_CONFIRMATION,
        message = message
    )

    fun waitForResponse(message: String = ""): Nothing = supervisor.deferTask(
        workspaceId = workspaceKey.workspaceId,
        status = AgentWorkspaceStatus.WAITING_RESPONSE,
        eventKind = AgentTaskEventKinds.WAITING_RESPONSE,
        message = message
    )

    fun pause(message: String = ""): Nothing = supervisor.deferTask(
        workspaceId = workspaceKey.workspaceId,
        status = AgentWorkspaceStatus.PAUSED,
        eventKind = AgentTaskEventKinds.PAUSED,
        message = message
    )

    fun blockTask(message: String = ""): Nothing = supervisor.deferTask(
        workspaceId = workspaceKey.workspaceId,
        status = AgentWorkspaceStatus.BLOCKED,
        eventKind = AgentTaskEventKinds.BLOCKED,
        message = message
    )
}

/**
 * Process-lifetime coordinator for agent work. It owns no Activity or other UI lifecycle object.
 */
class AgentTaskSupervisor(
    private val workspaceStore: AgentWorkspaceStore,
    maxConcurrentReadReasoningTasks: Int = DEFAULT_MAX_READ_REASONING_TASKS,
    readReasoningLimitProvider: () -> Int = { maxConcurrentReadReasoningTasks },
    dispatcher: CoroutineDispatcher = Dispatchers.Default,
    private val clock: () -> Long = { System.currentTimeMillis() },
    private val livenessPolicy: AgentTaskLivenessPolicy = AgentTaskLivenessPolicy(),
    private val livenessListener: AgentTaskLivenessListener = AgentTaskLivenessListener {},
    private val memoryObserver: (AgentWorkspace) -> Unit = {}
) : Closeable {
    private val supervisorJob = SupervisorJob()
    private val applicationScope = CoroutineScope(
        supervisorJob + dispatcher + CoroutineName("AgentTaskSupervisor")
    )
    private val readReasoningPermits = AgentAdaptiveCoroutinePermitGate(
        limitProvider = {
            readReasoningLimitProvider().coerceIn(1, maxConcurrentReadReasoningTasks)
        },
        maximum = maxConcurrentReadReasoningTasks
    )
    private val backgroundReadReasoningPermits = AgentAdaptiveCoroutinePermitGate(
        limitProvider = {
            (readReasoningLimitProvider().coerceIn(1, maxConcurrentReadReasoningTasks) - 1)
                .coerceAtLeast(1)
        },
        maximum = maxConcurrentReadReasoningTasks
    )
    private val sideEffectMutex = Mutex()
    private val storeMutationLock = Any()
    private val closed = AtomicBoolean(false)
    private val activeByWorkspace = ConcurrentHashMap<String, TaskControl>()
    private val activeByTask = ConcurrentHashMap<String, TaskControl>()

    init {
        require(maxConcurrentReadReasoningTasks > 0) {
            "maxConcurrentReadReasoningTasks must be positive"
        }
        applicationScope.launch(CoroutineName("AgentTaskWatchdog")) {
            while (currentCoroutineContext().isActive) {
                delay(livenessPolicy.watchdogIntervalMillis)
                runCatching { sweepLiveness() }
            }
        }
    }

    val isActive: Boolean
        get() = supervisorJob.isActive && !closed.get()

    fun activeTaskIds(): Set<String> = activeByTask.keys.toSet()

    fun activeWorkspaces(): List<AgentWorkspace> = activeByWorkspace.keys
        .mapNotNull(workspaceStore::find)
        .sortedWith(compareBy<AgentWorkspace> { it.createdAtMillis }.thenBy { it.workspaceId })

    fun heartbeat(
        workspaceId: String,
        stage: String = "running",
        message: String = ""
    ): AgentWorkspace = recordActivity(
        workspaceId = workspaceId,
        eventKind = AgentTaskEventKinds.HEARTBEAT,
        stage = stage,
        message = message
    )

    fun progress(
        workspaceId: String,
        stage: String,
        message: String = ""
    ): AgentWorkspace = recordActivity(
        workspaceId = workspaceId,
        eventKind = AgentTaskEventKinds.PROGRESS,
        stage = stage,
        message = message
    )

    fun sweepLiveness(): List<AgentTaskLivenessSignal> {
        val observedAt = now()
        return workspaceStore.recoverable().mapNotNull { workspace ->
            val volatileActivity = activeByWorkspace[workspace.workspaceId]?.lastActivityAtMillis ?: 0L
            val decision = livenessPolicy.evaluate(workspace, observedAt, volatileActivity)
            when (decision.state) {
                AgentTaskLivenessState.HEALTHY -> null
                AgentTaskLivenessState.STALLED -> markStalled(workspace, decision, observedAt)
                AgentTaskLivenessState.ASSESSMENT_REQUIRED -> requestLivenessAssessment(
                    workspace,
                    decision,
                    observedAt
                )
            }
        }
    }

    fun cancellationSource(taskId: String): AgentTaskCancellationSource? =
        activeByTask[taskId.trim()]?.cancellationSource

    fun submit(
        workspace: AgentWorkspace,
        lane: AgentTaskLane = AgentTaskLane.READ_REASONING,
        priority: AgentTaskPriority = AgentTaskPriority.NORMAL,
        block: suspend AgentTaskContext.() -> Unit
    ): AgentTaskHandle = startTask(
        workspace = workspace,
        lane = lane,
        priority = priority,
        resumed = false,
        block = block
    )

    fun launch(
        workspace: AgentWorkspace,
        lane: AgentTaskLane = AgentTaskLane.READ_REASONING,
        priority: AgentTaskPriority = AgentTaskPriority.NORMAL,
        block: suspend AgentTaskContext.() -> Unit
    ): AgentTaskHandle = submit(workspace, lane, priority, block)

    fun recoverableTasks(): List<AgentWorkspace> = workspaceStore.recoverable()

    fun reopenInterruptedWorkspace(
        workspaceId: String,
        reason: String = "Interrupted execution is ready to resume"
    ): AgentWorkspace = synchronized(storeMutationLock) {
        mutateWorkspaceLocked(workspaceId) { current ->
            require(current.status == AgentWorkspaceStatus.FAILED) {
                "Only an interrupted failed workspace can be reopened"
            }
            appendEventCandidate(
                current = current,
                kind = AgentTaskEventKinds.RECOVERED_INTERRUPTED,
                message = reason.ifBlank { "Interrupted execution is ready to resume" },
                payloadJson = ""
            ).copy(
                status = AgentWorkspaceStatus.PAUSED,
                errorMessage = "",
                cancellationRequested = false
            )
        }
    }

    fun resume(
        workspaceId: String,
        lane: AgentTaskLane = AgentTaskLane.READ_REASONING,
        priority: AgentTaskPriority = AgentTaskPriority.NORMAL,
        hook: AgentTaskResumeHook
    ): AgentTaskHandle {
        val recovered = requireWorkspace(workspaceId)
        require(!recovered.status.isTerminal && !recovered.cancellationRequested) {
            "Workspace $workspaceId is not recoverable"
        }
        return startTask(recovered, lane, priority, resumed = true) {
            hook.resume(this, recovered)
        }
    }

    fun resumeRecoverable(
        laneSelector: (AgentWorkspace) -> AgentTaskLane = { AgentTaskLane.READ_REASONING },
        prioritySelector: (AgentWorkspace) -> AgentTaskPriority = { AgentTaskPriority.NORMAL },
        hook: AgentTaskResumeHook
    ): List<AgentTaskHandle> = recoverableTasks()
        .filterNot { activeByWorkspace.containsKey(it.workspaceId) }
        .map { workspace ->
            startTask(
                workspace = workspace,
                lane = laneSelector(workspace),
                priority = prioritySelector(workspace),
                resumed = true
            ) {
                hook.resume(this, workspace)
            }
        }

    fun cancelTask(taskId: String, reason: String = "Task cancellation requested"): Boolean {
        val cleanTaskId = taskId.trim()
        if (cleanTaskId.isBlank()) return false
        val active = activeByTask[cleanTaskId]
        return if (active != null) {
            cancelWorkspace(active.workspaceId, reason)
        } else {
            val workspace = workspaceStore.list().firstOrNull { it.taskId == cleanTaskId } ?: return false
            cancelWorkspace(workspace.workspaceId, reason)
        }
    }

    fun cancelWorkspace(
        workspaceId: String,
        reason: String = "Task cancellation requested"
    ): Boolean {
        val cleanWorkspaceId = workspaceId.trim()
        if (cleanWorkspaceId.isBlank()) return false
        val cleanReason = reason.ifBlank { "Task cancellation requested" }
        var changed = false
        var shouldCancelExecution = false
        synchronized(storeMutationLock) {
            val current = workspaceStore.find(cleanWorkspaceId) ?: return@synchronized
            if (!current.status.isTerminal || current.status == AgentWorkspaceStatus.CANCELLED) {
                shouldCancelExecution = true
            }
            if (!current.status.isTerminal ||
                (current.status == AgentWorkspaceStatus.CANCELLED && !current.cancellationRequested)
            ) {
                mutateWorkspaceLocked(cleanWorkspaceId) { latest ->
                    if (latest.status.isTerminal && latest.cancellationRequested) {
                        latest
                    } else {
                        changed = true
                        transitionCandidate(
                            current = latest,
                            status = AgentWorkspaceStatus.CANCELLED,
                            eventKind = AgentTaskEventKinds.CANCELLED,
                            message = cleanReason,
                            cancellationRequested = true
                        )
                    }
                }
            }
        }
        if (shouldCancelExecution) {
            activeByWorkspace[cleanWorkspaceId]?.cancellationSource?.cancelExecution(cleanReason)
        }
        return changed
    }

    fun pauseForPermissionRevocation(
        workspaceId: String,
        reason: String = "A required permission grant was revoked"
    ): Boolean {
        val cleanWorkspaceId = workspaceId.trim()
        if (cleanWorkspaceId.isBlank()) return false
        val current = workspaceStore.find(cleanWorkspaceId) ?: return false
        if (current.status.isTerminal || current.cancellationRequested) return false
        val cleanReason = reason.ifBlank { "A required permission grant was revoked" }
        transition(
            workspaceId = cleanWorkspaceId,
            status = AgentWorkspaceStatus.PAUSED,
            eventKind = AgentTaskEventKinds.PERMISSION_REVOKED,
            message = cleanReason
        )
        activeByWorkspace[cleanWorkspaceId]?.cancellationSource?.cancelExecution(cleanReason)
        return true
    }

    fun appendEvent(
        workspaceId: String,
        kind: String,
        message: String = "",
        payloadJson: String = ""
    ): AgentWorkspace = synchronized(storeMutationLock) {
        mutateWorkspaceLocked(workspaceId) { current ->
            appendEventCandidate(current, kind, message, payloadJson)
        }
    }

    /**
     * Reopens a connector task only when an authenticated response is bound to
     * the original handoff. This is the narrow exception to terminal workspace
     * transitions used when a valid remote result arrives after local timeout.
     */
    fun reconcileLateConnectorResponse(
        workspaceId: String,
        sourceMessageId: Long,
        durableTurnId: String = ""
    ): AgentWorkspace? = synchronized(storeMutationLock) {
        if (sourceMessageId <= 0L) return@synchronized null
        val current = workspaceStore.find(workspaceId.trim()) ?: return@synchronized null
        if (current.status != AgentWorkspaceStatus.FAILED || current.cancellationRequested) {
            return@synchronized current.takeUnless { it.cancellationRequested }
        }
        val sourceSuffix = ":$sourceMessageId"
        val handoffMatches = current.handoffIds.any { it.endsWith(sourceSuffix) } ||
            current.remoteRunId == sourceMessageId.toString()
        val durableBindingMatches = durableTurnId.trim().let { turnId ->
            turnId.isNotBlank() && turnId == current.workspaceId
        }
        if (!handoffMatches && !durableBindingMatches) return@synchronized null
        mutateWorkspaceLocked(current.workspaceId) { latest ->
            if (latest.status != AgentWorkspaceStatus.FAILED || latest.cancellationRequested) {
                latest
            } else {
                appendEventCandidate(
                    current = latest,
                    kind = AgentTaskEventKinds.LATE_RESPONSE,
                    message = "Authenticated connector response received after local timeout",
                    payloadJson = AgentNativeJsonCodec.stringify(
                        mapOf("source_message_id" to sourceMessageId)
                    )
                ).copy(
                    status = AgentWorkspaceStatus.WAITING_RESPONSE,
                    errorMessage = ""
                )
            }
        }
    }

    private fun recordActivity(
        workspaceId: String,
        eventKind: String,
        stage: String,
        message: String
    ): AgentWorkspace {
        val cleanStage = stage.trim().ifBlank { "running" }
        val cleanMessage = message.trim().ifBlank { cleanStage }
        val observedAt = now()
        val activityPayload = AgentNativeJsonCodec.stringify(mapOf("stage" to cleanStage))
        activeByWorkspace[workspaceId.trim()]?.lastActivityAtMillis = observedAt
        var recovered = false
        val updated = synchronized(storeMutationLock) {
            mutateWorkspaceLocked(workspaceId) { current ->
                if (current.status.isTerminal || current.cancellationRequested) return@mutateWorkspaceLocked current
                recovered = livenessPolicy.hasUnresolvedStall(current) ||
                    livenessPolicy.hasPendingAssessment(current)
                val previous = current.eventJournal.lastOrNull()
                val sameRecentStage = !recovered && previous?.kind == eventKind &&
                    previous.payloadJson == activityPayload &&
                    observedAt - previous.timestampMillis < livenessPolicy.heartbeatWriteThrottleMillis
                if (sameRecentStage) current else appendEventCandidate(
                    current = current,
                    kind = eventKind,
                    message = cleanMessage,
                    payloadJson = activityPayload
                )
            }
        }
        if (recovered) {
            notifyLiveness(
                AgentTaskLivenessSignalKind.RECOVERED,
                updated,
                "progress_resumed",
                observedAt
            )
        }
        return updated
    }

    private fun markStalled(
        workspace: AgentWorkspace,
        decision: AgentTaskLivenessDecision,
        observedAt: Long
    ): AgentTaskLivenessSignal? {
        if (livenessPolicy.hasUnresolvedStall(workspace)) return null
        val updated = synchronized(storeMutationLock) {
            mutateWorkspaceLocked(workspace.workspaceId) { current ->
                if (current.status.isTerminal || livenessPolicy.hasUnresolvedStall(current)) current
                else appendEventCandidate(
                    current = current,
                    kind = AgentTaskEventKinds.STALLED,
                    message = decision.reason,
                    payloadJson = AgentNativeJsonCodec.stringify(mapOf(
                        "idle_ms" to decision.idleMillis,
                        "lifetime_ms" to decision.lifetimeMillis
                    ))
                )
            }
        }
        val signal = AgentTaskLivenessSignal(
            AgentTaskLivenessSignalKind.STALLED,
            updated,
            decision.reason,
            observedAt
        )
        runCatching { livenessListener.onSignal(signal) }
        return signal
    }

    private fun requestLivenessAssessment(
        workspace: AgentWorkspace,
        decision: AgentTaskLivenessDecision,
        observedAt: Long
    ): AgentTaskLivenessSignal? {
        var changed = false
        val updated = synchronized(storeMutationLock) {
            mutateWorkspaceLocked(workspace.workspaceId) { current ->
                if (current.status.isTerminal || current.cancellationRequested ||
                    livenessPolicy.hasPendingAssessment(current)
                ) current else {
                    changed = true
                    appendEventCandidate(
                        current = current,
                        kind = AgentTaskEventKinds.LIVENESS_ASSESSMENT_REQUESTED,
                        message = decision.reason,
                        payloadJson = AgentNativeJsonCodec.stringify(mapOf(
                            "idle_ms" to decision.idleMillis,
                            "lifetime_ms" to decision.lifetimeMillis,
                            "decision_owner" to "model"
                        ))
                    )
                }
            }
        }
        if (!changed) return null
        val signal = AgentTaskLivenessSignal(
            AgentTaskLivenessSignalKind.ASSESSMENT_REQUIRED,
            updated,
            decision.reason,
            observedAt
        )
        activeByWorkspace[workspace.workspaceId]?.cancellationSource?.interruptExecution(
            "Yielding the current execution lease for model liveness assessment"
        )
        runCatching { livenessListener.onSignal(signal) }
        return signal
    }

    private fun notifyLiveness(
        kind: AgentTaskLivenessSignalKind,
        workspace: AgentWorkspace,
        reason: String,
        observedAt: Long
    ) {
        runCatching {
            livenessListener.onSignal(AgentTaskLivenessSignal(kind, workspace, reason, observedAt))
        }
    }

    fun checkpoint(
        workspaceId: String,
        checkpointId: String,
        planSnapshot: String = "",
        stateJson: String = ""
    ): AgentWorkspace = synchronized(storeMutationLock) {
        mutateWorkspaceLocked(workspaceId) { current ->
            checkpointCandidate(current, checkpointId, planSnapshot, stateJson)
        }
    }

    internal fun appendEventAndCheckpoint(
        workspaceId: String,
        kind: String,
        message: String,
        payloadJson: String,
        checkpointId: String,
        stateJson: String
    ): AgentWorkspace = synchronized(storeMutationLock) {
        mutateWorkspaceLocked(workspaceId) { current ->
            val withEvent = appendEventCandidate(current, kind, message, payloadJson)
            checkpointCandidate(
                current = withEvent,
                checkpointId = checkpointId,
                planSnapshot = "",
                stateJson = stateJson,
                appendJournalEvent = false
            )
        }
    }

    fun recordExecutionSnapshot(
        workspaceId: String,
        snapshot: AgentWorkspaceExecutionSnapshot
    ): AgentWorkspace = synchronized(storeMutationLock) {
        mutateWorkspaceLocked(workspaceId) { current ->
            applyExecutionSnapshotCandidate(current, snapshot)
        }
    }.also(::notifyMemoryObserver)

    /**
     * Atomically reopens an interrupted workspace and records the recovered runtime state.
     * This is intentionally separate from normal snapshot persistence so terminal-state
     * protection remains strict for every non-recovery caller.
     */
    fun recordRecoveredExecutionSnapshot(
        workspaceId: String,
        snapshot: AgentWorkspaceExecutionSnapshot,
        reason: String = "Interrupted execution resumed from durable state"
    ): AgentWorkspace = synchronized(storeMutationLock) {
        mutateWorkspaceLocked(workspaceId) { current ->
            require(!current.cancellationRequested) {
                "Cancelled workspace $workspaceId cannot be recovered"
            }
            require(current.status != AgentWorkspaceStatus.COMPLETED &&
                current.status != AgentWorkspaceStatus.CANCELLED
            ) {
                "Terminal workspace $workspaceId cannot be recovered from ${current.status}"
            }
            val nextStatus = snapshot.status ?: current.status
            require(!nextStatus.isTerminal) {
                "Recovery snapshot for $workspaceId must be non-terminal"
            }
            val reopened = if (current.status == AgentWorkspaceStatus.FAILED) {
                appendEventCandidate(
                    current = current,
                    kind = AgentTaskEventKinds.RECOVERED_INTERRUPTED,
                    message = reason.ifBlank { "Interrupted execution resumed from durable state" },
                    payloadJson = ""
                ).copy(
                    status = AgentWorkspaceStatus.PAUSED,
                    errorMessage = "",
                    cancellationRequested = false
                )
            } else {
                current
            }
            applyExecutionSnapshotCandidate(reopened, snapshot)
        }
    }.also(::notifyMemoryObserver)

    fun transition(
        workspaceId: String,
        status: AgentWorkspaceStatus,
        eventKind: String = "task.status.${status.name.lowercase()}",
        message: String = "",
        payloadJson: String = ""
    ): AgentWorkspace = synchronized(storeMutationLock) {
        mutateWorkspaceLocked(workspaceId) { current ->
            transitionCandidate(
                current = current,
                status = status,
                eventKind = eventKind,
                message = message,
                payloadJson = payloadJson,
                cancellationRequested = current.cancellationRequested || status == AgentWorkspaceStatus.CANCELLED
            )
        }
    }.also(::notifyMemoryObserver)

    internal fun requireWorkspace(workspaceId: String): AgentWorkspace =
        requireNotNull(workspaceStore.find(workspaceId.trim())) {
            "Agent workspace $workspaceId does not exist"
        }

    internal fun deferTask(
        workspaceId: String,
        status: AgentWorkspaceStatus,
        eventKind: String,
        message: String
    ): Nothing {
        transition(workspaceId, status, eventKind, message)
        throw AgentTaskDeferredException(status)
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) {
            supervisorJob.cancel(CancellationException("Agent task supervisor closed"))
        }
    }

    suspend fun shutdown() {
        val jobs = activeByWorkspace.values.mapNotNull { it.executionJob }
        close()
        jobs.joinAll()
    }

    private fun startTask(
        workspace: AgentWorkspace,
        lane: AgentTaskLane,
        priority: AgentTaskPriority,
        resumed: Boolean,
        block: suspend AgentTaskContext.() -> Unit
    ): AgentTaskHandle {
        check(isActive) { "Agent task supervisor is closed" }
        val normalizedWorkspace = workspace.copy(
            workspaceId = workspace.workspaceId.trim(),
            sessionId = workspace.sessionId.trim(),
            conversationId = workspace.conversationId.trim(),
            taskId = workspace.taskId.trim()
        )
        require(normalizedWorkspace.workspaceId.isNotBlank()) { "workspaceId must not be blank" }
        require(normalizedWorkspace.sessionId.isNotBlank()) { "sessionId must not be blank" }
        require(normalizedWorkspace.conversationId.isNotBlank()) { "conversationId must not be blank" }
        require(normalizedWorkspace.taskId.isNotBlank()) { "taskId must not be blank" }

        val taskJob = Job(supervisorJob)
        lateinit var control: TaskControl
        val cancellationSource = AgentTaskCancellationSource(taskJob) { reason ->
            cancelWorkspace(normalizedWorkspace.workspaceId, reason)
        }
        control = TaskControl(
            workspaceId = normalizedWorkspace.workspaceId,
            taskId = normalizedWorkspace.taskId,
            lane = lane,
            priority = priority,
            cancellationSource = cancellationSource
        )
        try {
            reserve(control)
        } catch (failure: Throwable) {
            taskJob.complete()
            throw failure
        }

        val recoveringFromStall = workspaceStore.find(normalizedWorkspace.workspaceId)
            ?.let(livenessPolicy::hasUnresolvedStall)
            ?: false
        val queued = try {
            queueWorkspace(normalizedWorkspace, resumed)
        } catch (failure: Throwable) {
            release(control)
            taskJob.complete()
            throw failure
        }
        notifyMemoryObserver(queued)
        control.lastActivityAtMillis = now()
        if (recoveringFromStall) {
            notifyLiveness(
                AgentTaskLivenessSignalKind.RECOVERED,
                queued,
                "task_resumed",
                now()
            )
        }
        val context = AgentTaskContext(
            workspaceKey = queued.key,
            lane = lane,
            priority = priority,
            cancellationSource = cancellationSource,
            supervisor = this
        )
        val execution = applicationScope.launch(
            taskJob + CoroutineName("AgentTask-${queued.taskId}")
        ) {
            runTask(control, context, block)
        }
        control.executionJob = execution
        execution.invokeOnCompletion { cause ->
            if (cause is CancellationException) finishInterrupted(control)
            workspaceStore.find(control.workspaceId)?.let(::notifyMemoryObserver)
            release(control)
            cancellationSource.complete()
        }
        return AgentTaskHandle(
            workspaceId = queued.workspaceId,
            taskId = queued.taskId,
            lane = lane,
            priority = priority,
            cancellationSource = cancellationSource,
            job = execution
        )
    }

    private fun notifyMemoryObserver(workspace: AgentWorkspace) {
        runCatching { memoryObserver(workspace) }
    }

    private suspend fun runTask(
        control: TaskControl,
        context: AgentTaskContext,
        block: suspend AgentTaskContext.() -> Unit
    ) {
        try {
            runInLane(control.lane, control.priority) {
                context.ensureActive()
                transition(
                    workspaceId = control.workspaceId,
                    status = AgentWorkspaceStatus.RUNNING,
                    eventKind = AgentTaskEventKinds.RUNNING
                )
                control.lastActivityAtMillis = now()
                context.block()
            }
            finishCompleted(control)
        } catch (_: AgentTaskDeferredException) {
            // The context already persisted the waiting, paused, or blocked state.
        } catch (_: CancellationException) {
            finishInterrupted(control)
        } catch (failure: Throwable) {
            finishFailed(control, failure)
        }
    }

    private suspend fun <T> runInLane(
        lane: AgentTaskLane,
        priority: AgentTaskPriority,
        block: suspend () -> T
    ): T = when (lane) {
        AgentTaskLane.READ_REASONING -> {
            if (priority == AgentTaskPriority.BACKGROUND) {
                backgroundReadReasoningPermits.acquire()
            }
            try {
                readReasoningPermits.acquire()
                try {
                    block()
                } finally {
                    readReasoningPermits.release()
                }
            } finally {
                if (priority == AgentTaskPriority.BACKGROUND) {
                    backgroundReadReasoningPermits.release()
                }
            }
        }

        AgentTaskLane.SIDE_EFFECT -> {
            sideEffectMutex.lock()
            try {
                block()
            } finally {
                sideEffectMutex.unlock()
            }
        }
    }

    private fun queueWorkspace(workspace: AgentWorkspace, resumed: Boolean): AgentWorkspace =
        synchronized(storeMutationLock) {
            val existing = workspaceStore.find(workspace.workspaceId)
            if (existing == null) {
                require(!workspace.status.isTerminal && !workspace.cancellationRequested) {
                    "A new task workspace must be recoverable"
                }
                val queued = transitionCandidate(
                    current = workspace.copy(revision = 0L),
                    status = AgentWorkspaceStatus.QUEUED,
                    eventKind = if (resumed) AgentTaskEventKinds.RESUMED else AgentTaskEventKinds.QUEUED
                )
                workspaceStore.upsert(queued, expectedRevision = 0L)
            } else {
                require(existing.key == workspace.key) {
                    "Agent workspace identity fields cannot change"
                }
                require(!existing.status.isTerminal && !existing.cancellationRequested) {
                    "Workspace ${workspace.workspaceId} is not recoverable"
                }
                mutateWorkspaceLocked(workspace.workspaceId) { current ->
                    transitionCandidate(
                        current = current,
                        status = AgentWorkspaceStatus.QUEUED,
                        eventKind = if (resumed) AgentTaskEventKinds.RESUMED else AgentTaskEventKinds.QUEUED
                    )
                }
            }
        }

    private fun finishCompleted(control: TaskControl) {
        runCatching {
            synchronized(storeMutationLock) {
                mutateWorkspaceLocked(control.workspaceId) { current ->
                    when {
                        current.status.isTerminal -> current
                        current.cancellationRequested -> transitionCandidate(
                            current,
                            AgentWorkspaceStatus.CANCELLED,
                            AgentTaskEventKinds.CANCELLED,
                            "Task cancellation requested",
                            cancellationRequested = true
                        )

                        current.status in DEFERRED_STATUSES -> current
                        else -> transitionCandidate(
                            current,
                            AgentWorkspaceStatus.COMPLETED,
                            AgentTaskEventKinds.COMPLETED
                        )
                    }
                }
            }
        }
    }

    private fun finishFailed(control: TaskControl, failure: Throwable) {
        runCatching {
            synchronized(storeMutationLock) {
                mutateWorkspaceLocked(control.workspaceId) { current ->
                    when {
                        current.status.isTerminal -> current
                        current.cancellationRequested -> transitionCandidate(
                            current,
                            AgentWorkspaceStatus.CANCELLED,
                            AgentTaskEventKinds.CANCELLED,
                            "Task cancellation requested",
                            cancellationRequested = true
                        )

                        else -> transitionCandidate(
                            current,
                            AgentWorkspaceStatus.FAILED,
                            AgentTaskEventKinds.FAILED,
                            failure.message?.takeIf { it.isNotBlank() }
                                ?: failure::class.java.simpleName.ifBlank { "Task failed" }
                        )
                    }
                }
            }
        }
    }

    private fun finishInterrupted(control: TaskControl) {
        runCatching {
            synchronized(storeMutationLock) {
                mutateWorkspaceLocked(control.workspaceId) { current ->
                    when {
                        current.status.isTerminal -> current
                        current.cancellationRequested || control.cancellationSource.isCancellationRequested ->
                            transitionCandidate(
                                current,
                                AgentWorkspaceStatus.CANCELLED,
                                AgentTaskEventKinds.CANCELLED,
                                "Task cancellation requested",
                                cancellationRequested = true
                            )

                        current.status in DEFERRED_STATUSES -> current
                        else -> transitionCandidate(
                            current,
                            AgentWorkspaceStatus.PAUSED,
                            AgentTaskEventKinds.INTERRUPTED,
                            "Task execution was interrupted"
                        )
                    }
                }
            }
        }
    }

    private fun transitionCandidate(
        current: AgentWorkspace,
        status: AgentWorkspaceStatus,
        eventKind: String,
        message: String = "",
        payloadJson: String = "",
        cancellationRequested: Boolean = current.cancellationRequested
    ): AgentWorkspace {
        require(!current.status.isTerminal || current.status == status) {
            "Terminal workspace ${current.workspaceId} cannot transition from ${current.status} to $status"
        }
        return appendEventCandidate(current, eventKind, message, payloadJson).copy(
            status = status,
            cancellationRequested = cancellationRequested
        )
    }

    private fun applyExecutionSnapshotCandidate(
        current: AgentWorkspace,
        snapshot: AgentWorkspaceExecutionSnapshot
    ): AgentWorkspace {
        val nextStatus = snapshot.status ?: current.status
        val withEvent = if (nextStatus != current.status) {
            transitionCandidate(
                current = current,
                status = nextStatus,
                eventKind = AgentTaskEventKinds.SNAPSHOT,
                message = nextStatus.name.lowercase()
            )
        } else {
            appendEventCandidate(
                current = current,
                kind = AgentTaskEventKinds.SNAPSHOT,
                message = nextStatus.name.lowercase(),
                payloadJson = ""
            )
        }
        return withEvent.copy(
            currentPlanSnapshot = snapshot.planSnapshot.ifBlank { current.currentPlanSnapshot },
            resultJson = snapshot.resultJson.ifBlank { current.resultJson },
            errorMessage = snapshot.errorMessage.ifBlank { current.errorMessage },
            toolCalls = (current.toolCalls + snapshot.toolCalls)
                .distinctBy(AgentToolCallRecord::id)
                .takeLast(AgentWorkspaceLimits.MAX_TOOL_CALLS),
            artifacts = (current.artifacts + snapshot.artifacts)
                .distinctBy(AgentArtifactReference::id)
                .takeLast(AgentWorkspaceLimits.MAX_ARTIFACTS),
            permissionGrantIds = (current.permissionGrantIds + snapshot.permissionGrantIds)
                .distinct()
                .takeLast(AgentWorkspaceLimits.MAX_PERMISSION_BINDINGS),
            permissionScopes = (current.permissionScopes + snapshot.permissionScopes)
                .distinct()
                .takeLast(AgentWorkspaceLimits.MAX_PERMISSION_BINDINGS),
            handoffIds = (current.handoffIds + snapshot.handoffIds)
                .distinct()
                .takeLast(AgentWorkspaceLimits.MAX_HANDOFF_IDS),
            agentId = snapshot.agentId.ifBlank { current.agentId },
            deviceId = snapshot.deviceId.ifBlank { current.deviceId },
            remoteRunId = snapshot.remoteRunId.ifBlank { current.remoteRunId },
            lastRemoteEventSequence = maxOf(
                current.lastRemoteEventSequence,
                snapshot.lastRemoteEventSequence
            )
        )
    }

    private fun appendEventCandidate(
        current: AgentWorkspace,
        kind: String,
        message: String,
        payloadJson: String
    ): AgentWorkspace {
        val cleanKind = kind.trim()
        require(cleanKind.isNotBlank()) { "event kind must not be blank" }
        require(current.eventSequence < Long.MAX_VALUE) { "Agent workspace event sequence exhausted" }
        val timestamp = now()
        val nextSequence = current.eventSequence + 1L
        val event = AgentWorkspaceEvent(
            sequence = nextSequence,
            kind = cleanKind,
            message = message,
            payloadJson = payloadJson,
            timestampMillis = timestamp
        )
        return current.copy(
            eventSequence = nextSequence,
            eventJournal = (current.eventJournal + event).takeLast(AgentWorkspaceLimits.MAX_EVENTS),
            updatedAtMillis = maxOf(current.updatedAtMillis, timestamp)
        )
    }

    private fun checkpointCandidate(
        current: AgentWorkspace,
        checkpointId: String,
        planSnapshot: String,
        stateJson: String,
        appendJournalEvent: Boolean = true
    ): AgentWorkspace {
        val cleanCheckpointId = checkpointId.trim()
        require(cleanCheckpointId.isNotBlank()) { "checkpointId must not be blank" }
        val timestamp = now()
        val withEvent = if (appendJournalEvent) {
            appendEventCandidate(
                current = current,
                kind = AgentTaskEventKinds.CHECKPOINT,
                message = cleanCheckpointId,
                payloadJson = ""
            )
        } else {
            current
        }
        val checkpoint = AgentWorkspaceCheckpoint(
            id = cleanCheckpointId,
            eventSequence = withEvent.eventSequence,
            planSnapshot = planSnapshot.ifBlank { current.currentPlanSnapshot },
            stateJson = stateJson,
            createdAtMillis = timestamp
        )
        val checkpoints = current.checkpoints
            .filterNot { it.id == cleanCheckpointId }
            .plus(checkpoint)
            .sortedWith(compareBy<AgentWorkspaceCheckpoint> { it.eventSequence }
                .thenBy { it.createdAtMillis }
                .thenBy { it.id })
            .takeLast(AgentWorkspaceLimits.MAX_CHECKPOINTS)
        return withEvent.copy(
            currentPlanSnapshot = checkpoint.planSnapshot,
            checkpoints = checkpoints,
            updatedAtMillis = maxOf(withEvent.updatedAtMillis, timestamp)
        )
    }

    private fun mutateWorkspaceLocked(
        workspaceId: String,
        mutation: (AgentWorkspace) -> AgentWorkspace
    ): AgentWorkspace {
        val cleanWorkspaceId = workspaceId.trim()
        require(cleanWorkspaceId.isNotBlank()) { "workspaceId must not be blank" }
        var lastConflict: AgentWorkspaceRevisionConflictException? = null
        repeat(MAX_STORE_WRITE_ATTEMPTS) {
            val current = requireNotNull(workspaceStore.find(cleanWorkspaceId)) {
                "Agent workspace $cleanWorkspaceId does not exist"
            }
            val candidate = mutation(current)
            if (candidate == current) return current
            try {
                return workspaceStore.upsert(
                    candidate.copy(revision = current.revision),
                    expectedRevision = current.revision
                )
            } catch (conflict: AgentWorkspaceRevisionConflictException) {
                lastConflict = conflict
            }
        }
        throw checkNotNull(lastConflict)
    }

    private fun reserve(control: TaskControl) {
        check(activeByWorkspace.putIfAbsent(control.workspaceId, control) == null) {
            "Workspace ${control.workspaceId} already has an active task"
        }
        if (activeByTask.putIfAbsent(control.taskId, control) != null) {
            activeByWorkspace.remove(control.workspaceId, control)
            error("Task ${control.taskId} is already active")
        }
        if (control.priority == AgentTaskPriority.FOREGROUND) {
            try {
                control.foregroundLease = AgentForegroundWorkCoordinator.begin(control.taskId)
            } catch (failure: Throwable) {
                activeByWorkspace.remove(control.workspaceId, control)
                activeByTask.remove(control.taskId, control)
                throw failure
            }
        }
    }

    private fun release(control: TaskControl) {
        control.foregroundLease?.close()
        control.foregroundLease = null
        activeByWorkspace.remove(control.workspaceId, control)
        activeByTask.remove(control.taskId, control)
    }

    private fun now(): Long = clock().coerceAtLeast(0L)

    private class TaskControl(
        val workspaceId: String,
        val taskId: String,
        val lane: AgentTaskLane,
        val priority: AgentTaskPriority,
        val cancellationSource: AgentTaskCancellationSource,
        @Volatile var foregroundLease: AgentForegroundWorkCoordinator.Lease? = null,
        @Volatile var executionJob: Job? = null,
        @Volatile var lastActivityAtMillis: Long = 0L
    )

    private class AgentTaskDeferredException(
        val status: AgentWorkspaceStatus
    ) : RuntimeException(null, null, false, false)

    companion object {
        const val DEFAULT_MAX_READ_REASONING_TASKS = AgentAdaptiveConcurrencyPolicy.DEFAULT_CONCURRENCY
        private const val MAX_STORE_WRITE_ATTEMPTS = 5
        private val DEFERRED_STATUSES = setOf(
            AgentWorkspaceStatus.WAITING_CONFIRMATION,
            AgentWorkspaceStatus.WAITING_RESPONSE,
            AgentWorkspaceStatus.PAUSED,
            AgentWorkspaceStatus.BLOCKED
        )
    }
}
