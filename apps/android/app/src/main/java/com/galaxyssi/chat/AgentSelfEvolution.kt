package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.Base64
import java.util.Locale
import java.util.UUID

const val AGENT_SELF_EVOLUTION_PROTOCOL = "galaxyssi.evolution-task.v1"

enum class AgentSelfEvolutionStatus(val wireValue: String) {
    PROPOSED("proposed"),
    PREPARING("preparing"),
    RUNNING("running"),
    VALIDATING("validating"),
    WAITING_APPROVAL("waiting_approval"),
    PUBLISHING("publishing"),
    PUBLISHED("published"),
    COMPLETED("completed"),
    FAILED("failed"),
    BLOCKED("blocked"),
    CANCELLED("cancelled"),
    ROLLED_BACK("rolled_back")
}

enum class AgentSelfEvolutionRisk(val wireValue: String) {
    LOW("low"),
    MEDIUM("medium"),
    HIGH("high"),
    CRITICAL("critical")
}

enum class AgentSelfEvolutionGateStatus(val wireValue: String) {
    PENDING("pending"),
    RUNNING("running"),
    PASSED("passed"),
    FAILED("failed"),
    SKIPPED("skipped"),
    CANCELLED("cancelled")
}

data class AgentSelfEvolutionGate(
    val id: String,
    val status: AgentSelfEvolutionGateStatus,
    val durationMillis: Long = 0L,
    val exitCode: Int = 0,
    val summary: String = ""
)

data class AgentSelfEvolutionAttempt(
    val number: Int,
    val status: AgentSelfEvolutionStatus,
    val workspaceId: String,
    val branch: String,
    val changedFiles: List<String> = emptyList(),
    val gates: List<AgentSelfEvolutionGate> = emptyList(),
    val failureCode: String = "",
    val failureSummary: String = "",
    val startedAtMillis: Long = 0L,
    val completedAtMillis: Long = 0L
)

data class AgentSelfEvolutionTask(
    val taskId: String,
    val problem: String,
    val reproductionSteps: List<String>,
    val scope: List<String>,
    val acceptance: List<String>,
    val risk: AgentSelfEvolutionRisk,
    val maxAttempts: Int,
    val status: AgentSelfEvolutionStatus = AgentSelfEvolutionStatus.PROPOSED,
    val protocol: String = AGENT_SELF_EVOLUTION_PROTOCOL,
    val executionTarget: String = "android",
    val baseCommit: String = "",
    val candidateCommit: String = "",
    val candidateBranch: String = "",
    val approvalHash: String = "",
    val attempts: List<AgentSelfEvolutionAttempt> = emptyList(),
    val lastErrorCode: String = "",
    val lastError: String = "",
    val createdAtMillis: Long = 0L,
    val updatedAtMillis: Long = 0L
) {
    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "protocol" to protocol,
        "task_id" to taskId,
        "problem" to problem,
        "reproduction_steps" to reproductionSteps,
        "scope" to scope,
        "acceptance" to acceptance,
        "risk_level" to risk.wireValue,
        "max_attempts" to maxAttempts,
        "status" to status.wireValue,
        "execution_target" to executionTarget,
        "base_commit" to baseCommit,
        "candidate_commit" to candidateCommit,
        "candidate_branch" to candidateBranch,
        "approval_hash" to approvalHash,
        "attempts" to attempts.map { attempt ->
            linkedMapOf(
                "number" to attempt.number,
                "status" to attempt.status.wireValue,
                "changed_files" to attempt.changedFiles,
                "gates" to attempt.gates.map { gate ->
                    linkedMapOf(
                        "id" to gate.id,
                        "status" to gate.status.wireValue,
                        "duration_millis" to gate.durationMillis,
                        "exit_code" to gate.exitCode,
                        "summary" to gate.summary
                    )
                },
                "failure_code" to attempt.failureCode,
                "failure_summary" to attempt.failureSummary,
                "started_at_millis" to attempt.startedAtMillis,
                "completed_at_millis" to attempt.completedAtMillis
            )
        },
        "last_error_code" to lastErrorCode,
        "last_error" to lastError,
        "created_at_millis" to createdAtMillis,
        "updated_at_millis" to updatedAtMillis
    )
}

data class AgentSelfEvolutionHealth(
    val totalTasks: Int,
    val queuedTasks: Int,
    val activeTasks: Int,
    val waitingReview: Int,
    val successfulTasks: Int,
    val attentionTasks: Int,
    val staleTasks: Int,
    val totalAttempts: Int,
    val failedAttempts: Int,
    val retries: Int,
    val totalGates: Int,
    val passedGates: Int,
    val failedGates: Int,
    val gatePassPercent: Int,
    val successPercent: Int,
    val averageAttemptDurationMillis: Long,
    val oldestReviewAgeMillis: Long,
    val lastActivityAtMillis: Long,
    val statusCounts: Map<String, Int>,
    val failureCounts: Map<String, Int>,
    val staleTaskIds: List<String>,
    val generatedAtMillis: Long,
    val staleAfterMillis: Long
) {
    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "total_tasks" to totalTasks,
        "queued_tasks" to queuedTasks,
        "active_tasks" to activeTasks,
        "waiting_review" to waitingReview,
        "successful_tasks" to successfulTasks,
        "attention_tasks" to attentionTasks,
        "stale_tasks" to staleTasks,
        "total_attempts" to totalAttempts,
        "failed_attempts" to failedAttempts,
        "retries" to retries,
        "total_gates" to totalGates,
        "passed_gates" to passedGates,
        "failed_gates" to failedGates,
        "gate_pass_percent" to gatePassPercent,
        "success_percent" to successPercent,
        "average_attempt_duration_millis" to averageAttemptDurationMillis,
        "oldest_review_age_millis" to oldestReviewAgeMillis,
        "last_activity_at_millis" to lastActivityAtMillis,
        "status_counts" to statusCounts,
        "failure_counts" to failureCounts,
        "stale_task_ids" to staleTaskIds,
        "generated_at_millis" to generatedAtMillis,
        "stale_after_millis" to staleAfterMillis
    )
}

object AgentSelfEvolutionHealthAnalyzer {
    private val activeStatuses = setOf(
        AgentSelfEvolutionStatus.PREPARING,
        AgentSelfEvolutionStatus.RUNNING,
        AgentSelfEvolutionStatus.VALIDATING,
        AgentSelfEvolutionStatus.PUBLISHING
    )
    private val successfulStatuses = setOf(
        AgentSelfEvolutionStatus.PUBLISHED,
        AgentSelfEvolutionStatus.COMPLETED
    )
    private val attentionStatuses = setOf(
        AgentSelfEvolutionStatus.FAILED,
        AgentSelfEvolutionStatus.BLOCKED
    )

    fun summarize(
        tasks: List<AgentSelfEvolutionTask>,
        nowMillis: Long = System.currentTimeMillis(),
        staleAfterMillis: Long = 30 * 60_000L
    ): AgentSelfEvolutionHealth {
        val now = nowMillis.coerceAtLeast(0L)
        val staleAfter = staleAfterMillis.coerceAtLeast(60_000L)
        val attempts = tasks.flatMap(AgentSelfEvolutionTask::attempts)
        val gates = attempts.flatMap(AgentSelfEvolutionAttempt::gates)
        val statusCounts = tasks.groupingBy { it.status.wireValue }.eachCount().toSortedMap()
        val failureCounts = linkedMapOf<String, Int>()
        attempts.map(AgentSelfEvolutionAttempt::failureCode)
            .filter(String::isNotBlank)
            .forEach { code -> failureCounts[code] = (failureCounts[code] ?: 0) + 1 }
        tasks.filter { task ->
            task.lastErrorCode.isNotBlank() &&
                task.lastErrorCode != task.attempts.lastOrNull()?.failureCode.orEmpty()
        }
            .forEach { task ->
                failureCounts[task.lastErrorCode] = (failureCounts[task.lastErrorCode] ?: 0) + 1
            }
        val staleIds = tasks.asSequence()
            .filter { it.status in activeStatuses }
            .filter { it.updatedAtMillis > 0L && now - it.updatedAtMillis >= staleAfter }
            .map(AgentSelfEvolutionTask::taskId)
            .sorted()
            .toList()
        val overdueReviewIds = tasks.asSequence()
            .filter { it.status == AgentSelfEvolutionStatus.WAITING_APPROVAL }
            .filter { it.updatedAtMillis > 0L && now - it.updatedAtMillis >= staleAfter }
            .map(AgentSelfEvolutionTask::taskId)
            .toSet()
        val attentionIds = tasks.asSequence()
            .filter { it.status in attentionStatuses }
            .map(AgentSelfEvolutionTask::taskId)
            .toMutableSet()
            .apply {
                addAll(staleIds)
                addAll(overdueReviewIds)
            }
        val durations = attempts.mapNotNull { attempt ->
            if (
                attempt.startedAtMillis > 0L &&
                attempt.completedAtMillis >= attempt.startedAtMillis
            ) attempt.completedAtMillis - attempt.startedAtMillis else null
        }
        val passedGates = gates.count { it.status == AgentSelfEvolutionGateStatus.PASSED }
        val failedGates = gates.count {
            it.status in setOf(
                AgentSelfEvolutionGateStatus.FAILED,
                AgentSelfEvolutionGateStatus.CANCELLED
            )
        }
        val decidedGates = passedGates + failedGates
        val successful = tasks.count { it.status in successfulStatuses }
        val unsuccessful = tasks.count { it.status in attentionStatuses }
        val decidedTasks = successful + unsuccessful
        val reviewAges = tasks.mapNotNull { task ->
            if (
                task.status == AgentSelfEvolutionStatus.WAITING_APPROVAL &&
                task.updatedAtMillis > 0L
            ) now - task.updatedAtMillis else null
        }
        return AgentSelfEvolutionHealth(
            totalTasks = tasks.size,
            queuedTasks = tasks.count { it.status == AgentSelfEvolutionStatus.PROPOSED },
            activeTasks = tasks.count { it.status in activeStatuses },
            waitingReview = tasks.count { it.status == AgentSelfEvolutionStatus.WAITING_APPROVAL },
            successfulTasks = successful,
            attentionTasks = attentionIds.size,
            staleTasks = staleIds.size,
            totalAttempts = attempts.size,
            failedAttempts = attempts.count { it.status == AgentSelfEvolutionStatus.FAILED },
            retries = tasks.sumOf { (it.attempts.size - 1).coerceAtLeast(0) },
            totalGates = gates.size,
            passedGates = passedGates,
            failedGates = failedGates,
            gatePassPercent = if (decidedGates == 0) 0 else
                (passedGates * 100 + decidedGates / 2) / decidedGates,
            successPercent = if (decidedTasks == 0) 0 else
                (successful * 100 + decidedTasks / 2) / decidedTasks,
            averageAttemptDurationMillis = if (durations.isEmpty()) 0L else
                durations.sum() / durations.size,
            oldestReviewAgeMillis = reviewAges.maxOrNull() ?: 0L,
            lastActivityAtMillis = tasks.maxOfOrNull(AgentSelfEvolutionTask::updatedAtMillis) ?: 0L,
            statusCounts = statusCounts,
            failureCounts = failureCounts.toSortedMap(),
            staleTaskIds = staleIds,
            generatedAtMillis = now,
            staleAfterMillis = staleAfter
        )
    }
}

data class AgentSelfEvolutionPrepareResult(
    val baseCommit: String,
    val branch: String
)

data class AgentSelfEvolutionPatchResult(
    val changedFiles: List<String>
)

data class AgentSelfEvolutionCommitResult(
    val commit: String
)

class AgentSelfEvolutionException(
    val code: String,
    message: String,
    val blocked: Boolean = false
) : IllegalStateException(message)

fun interface AgentSelfEvolutionEventSink {
    fun onEvent(event: AgentNativeJsonObject)

    companion object {
        val NONE = AgentSelfEvolutionEventSink { }
    }
}

interface AgentSelfEvolutionStore {
    fun save(task: AgentSelfEvolutionTask)
    fun get(taskId: String): AgentSelfEvolutionTask?
    fun list(limit: Int = 100): List<AgentSelfEvolutionTask>
}

class InMemoryAgentSelfEvolutionStore : AgentSelfEvolutionStore {
    private val tasks = linkedMapOf<String, AgentSelfEvolutionTask>()

    @Synchronized
    override fun save(task: AgentSelfEvolutionTask) {
        tasks[task.taskId] = task
    }

    @Synchronized
    override fun get(taskId: String): AgentSelfEvolutionTask? = tasks[taskId]

    @Synchronized
    override fun list(limit: Int): List<AgentSelfEvolutionTask> =
        tasks.values.sortedByDescending(AgentSelfEvolutionTask::updatedAtMillis)
            .take(limit.coerceIn(1, 500))
}

class EncryptedAgentSelfEvolutionStore(context: Context) : AgentSelfEvolutionStore {
    private val database = AgentEncryptedDatabase(context.applicationContext, DATABASE)

    @Synchronized
    override fun save(task: AgentSelfEvolutionTask) {
        database.writeString("$TASK_PREFIX${task.taskId}", AgentSelfEvolutionJson.encode(task))
    }

    @Synchronized
    override fun get(taskId: String): AgentSelfEvolutionTask? =
        AgentSelfEvolutionJson.decode(database.readString("$TASK_PREFIX$taskId", ""))

    @Synchronized
    override fun list(limit: Int): List<AgentSelfEvolutionTask> =
        database.entries(TASK_PREFIX)
            .mapNotNull { AgentSelfEvolutionJson.decode(it.second) }
            .sortedByDescending(AgentSelfEvolutionTask::updatedAtMillis)
            .take(limit.coerceIn(1, 500))

    private companion object {
        const val DATABASE = "galaxyssi_self_evolution_v1"
        const val TASK_PREFIX = "task:"
    }
}

data class AgentRemoteSelfEvolutionTask(
    val desktopId: String,
    val task: AgentSelfEvolutionTask
)

class EncryptedAgentRemoteSelfEvolutionStore(context: Context) {
    private val database = AgentEncryptedDatabase(
        context.applicationContext,
        "galaxyssi_remote_self_evolution_v1"
    )

    @Synchronized
    fun save(desktopId: String, taskJson: JSONObject) {
        val cleanDesktopId = desktopId.trim()
        val task = AgentSelfEvolutionJson.decode(taskJson.toString()) ?: return
        if (cleanDesktopId.isBlank() || task.executionTarget != "desktop") return
        database.writeString(key(cleanDesktopId, task.taskId), AgentSelfEvolutionJson.encode(task))
    }

    @Synchronized
    fun replace(desktopId: String, tasks: List<JSONObject>) {
        val cleanDesktopId = desktopId.trim()
        if (cleanDesktopId.isBlank()) return
        database.removeAll(database.entries(prefix(cleanDesktopId)).map(Pair<String, String>::first))
        tasks.forEach { save(cleanDesktopId, it) }
    }

    @Synchronized
    fun get(desktopId: String, taskId: String): AgentSelfEvolutionTask? =
        AgentSelfEvolutionJson.decode(database.readString(key(desktopId.trim(), taskId.trim()), ""))

    @Synchronized
    fun list(limit: Int = 100): List<AgentRemoteSelfEvolutionTask> =
        database.entries(REMOTE_PREFIX)
            .mapNotNull { (key, value) ->
                val desktopId = decodeDesktopId(
                    key.removePrefix(REMOTE_PREFIX).substringBefore(':')
                )
                AgentSelfEvolutionJson.decode(value)?.let {
                    AgentRemoteSelfEvolutionTask(desktopId, it)
                }
            }
            .sortedByDescending { it.task.updatedAtMillis }
            .take(limit.coerceIn(1, 500))

    private fun prefix(desktopId: String): String =
        "$REMOTE_PREFIX${Base64.getUrlEncoder().withoutPadding().encodeToString(desktopId.toByteArray())}:"

    private fun key(desktopId: String, taskId: String): String =
        "${prefix(desktopId)}$taskId"

    private fun decodeDesktopId(value: String): String = runCatching {
        String(Base64.getUrlDecoder().decode(value), Charsets.UTF_8)
    }.getOrDefault("")

    private companion object {
        const val REMOTE_PREFIX = "desktop:"
    }
}

interface AgentSelfEvolutionRuntime {
    fun prepare(
        task: AgentSelfEvolutionTask,
        attempt: AgentSelfEvolutionAttempt,
        cancellationToken: AgentNativeToolCancellationToken
    ): AgentSelfEvolutionPrepareResult

    fun applyPatch(
        task: AgentSelfEvolutionTask,
        attempt: AgentSelfEvolutionAttempt,
        unifiedDiff: String,
        cancellationToken: AgentNativeToolCancellationToken
    ): AgentSelfEvolutionPatchResult

    fun validate(
        task: AgentSelfEvolutionTask,
        attempt: AgentSelfEvolutionAttempt,
        changedFiles: List<String>,
        cancellationToken: AgentNativeToolCancellationToken
    ): List<AgentSelfEvolutionGate>

    fun commit(
        task: AgentSelfEvolutionTask,
        attempt: AgentSelfEvolutionAttempt,
        cancellationToken: AgentNativeToolCancellationToken
    ): AgentSelfEvolutionCommitResult

    fun discard(task: AgentSelfEvolutionTask, attempt: AgentSelfEvolutionAttempt)
}

class AgentSelfEvolutionManager(
    private val store: AgentSelfEvolutionStore,
    private val runtime: AgentSelfEvolutionRuntime,
    private val eventSink: AgentSelfEvolutionEventSink = AgentSelfEvolutionEventSink.NONE,
    private val clock: () -> Long = System::currentTimeMillis
) {
    @Synchronized
    fun create(
        problem: String,
        scope: List<String>,
        acceptance: List<String>,
        reproductionSteps: List<String> = emptyList(),
        risk: AgentSelfEvolutionRisk = AgentSelfEvolutionRisk.MEDIUM,
        maxAttempts: Int = 3,
        taskId: String = "evolve-${UUID.randomUUID().toString().replace("-", "").take(20)}"
    ): AgentSelfEvolutionTask {
        val cleanProblem = problem.trim().take(4_000)
        require(cleanProblem.length >= 4) { "Evolution task problem is too short" }
        val cleanScope = AgentSelfEvolutionPolicy.normalizedScope(scope)
        val cleanAcceptance = acceptance.map(String::trim).filter(String::isNotBlank)
            .map { it.take(1_000) }.distinct().take(40)
        require(cleanAcceptance.isNotEmpty()) { "Evolution acceptance criteria are required" }
        require(TASK_ID_PATTERN.matches(taskId)) { "Evolution task id is invalid" }
        val now = clock()
        val task = AgentSelfEvolutionTask(
            taskId = taskId,
            problem = cleanProblem,
            reproductionSteps = reproductionSteps.map(String::trim).filter(String::isNotBlank)
                .map { it.take(1_000) }.take(20),
            scope = cleanScope,
            acceptance = cleanAcceptance,
            risk = risk,
            maxAttempts = maxAttempts.coerceIn(1, 5),
            createdAtMillis = now,
            updatedAtMillis = now
        )
        store.save(task)
        emit(task, "created")
        return task
    }

    @Synchronized
    fun prepare(
        taskId: String,
        cancellationToken: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE
    ): AgentSelfEvolutionTask {
        val task = requireTask(taskId)
        require(task.status in setOf(AgentSelfEvolutionStatus.PROPOSED, AgentSelfEvolutionStatus.BLOCKED)) {
            "Evolution task is not ready to prepare"
        }
        require(consumedAttemptCount(task) < task.maxAttempts) { "Evolution attempt budget is exhausted" }
        cancellationToken.throwIfCancelled()
        val number = (task.attempts.maxOfOrNull(AgentSelfEvolutionAttempt::number) ?: 0) + 1
        val workspaceId = workspaceId(task.taskId, number)
        val branch = "evolution/${task.taskId}-a$number"
        var attempt = AgentSelfEvolutionAttempt(
            number = number,
            status = AgentSelfEvolutionStatus.PREPARING,
            workspaceId = workspaceId,
            branch = branch,
            startedAtMillis = clock()
        )
        var current = task.copy(
            status = AgentSelfEvolutionStatus.PREPARING,
            attempts = task.attempts + attempt,
            updatedAtMillis = clock()
        )
        store.save(current)
        emit(current, "worktree_preparing", mapOf("attempt" to number))
        return try {
            val prepared = runtime.prepare(current, attempt, cancellationToken)
            attempt = attempt.copy(
                status = AgentSelfEvolutionStatus.RUNNING,
                branch = prepared.branch
            )
            current = current.copy(
                status = AgentSelfEvolutionStatus.RUNNING,
                baseCommit = prepared.baseCommit,
                attempts = current.attempts.dropLast(1) + attempt,
                lastErrorCode = "",
                lastError = "",
                updatedAtMillis = clock()
            )
            store.save(current)
            emit(current, "worktree_ready", mapOf("attempt" to number))
            current
        } catch (error: Throwable) {
            failAttempt(current, attempt, error)
        }
    }

    @Synchronized
    fun applyPatchAndValidate(
        taskId: String,
        unifiedDiff: String,
        cancellationToken: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE
    ): AgentSelfEvolutionTask {
        var task = requireTask(taskId)
        var attempt = task.attempts.lastOrNull()
            ?: throw IllegalStateException("Evolution task has no prepared candidate")
        require(task.status == AgentSelfEvolutionStatus.RUNNING) { "Evolution task is not accepting a patch" }
        require(unifiedDiff.toByteArray(Charsets.UTF_8).size in 1..MAX_PATCH_BYTES) {
            "Evolution patch size is invalid"
        }
        cancellationToken.throwIfCancelled()
        return try {
            val patch = runtime.applyPatch(task, attempt, unifiedDiff, cancellationToken)
            AgentSelfEvolutionPolicy.requireChangedFilesInScope(task.scope, patch.changedFiles)
            require(patch.changedFiles.isNotEmpty()) { "Evolution patch did not change the candidate" }
            attempt = attempt.copy(
                status = AgentSelfEvolutionStatus.VALIDATING,
                changedFiles = patch.changedFiles
            )
            task = task.copy(
                status = AgentSelfEvolutionStatus.VALIDATING,
                attempts = task.attempts.dropLast(1) + attempt,
                updatedAtMillis = clock()
            )
            store.save(task)
            emit(task, "validation_started", mapOf("attempt" to attempt.number))
            val gates = runtime.validate(task, attempt, patch.changedFiles, cancellationToken)
            attempt = attempt.copy(gates = gates)
            task = task.copy(
                attempts = task.attempts.dropLast(1) + attempt,
                updatedAtMillis = clock()
            )
            store.save(task)
            val failed = gates.firstOrNull { it.status != AgentSelfEvolutionGateStatus.PASSED }
            if (failed != null) {
                throw AgentSelfEvolutionException(
                    "quality_gate_failed",
                    "Quality gate ${failed.id} failed: ${failed.summary}"
                )
            }
            val committed = runtime.commit(task, attempt, cancellationToken)
            attempt = attempt.copy(
                status = AgentSelfEvolutionStatus.WAITING_APPROVAL,
                gates = gates,
                completedAtMillis = clock()
            )
            task = task.copy(
                status = AgentSelfEvolutionStatus.WAITING_APPROVAL,
                candidateCommit = committed.commit,
                candidateBranch = attempt.branch,
                attempts = task.attempts.dropLast(1) + attempt,
                updatedAtMillis = clock()
            )
            task = task.copy(approvalHash = AgentSelfEvolutionPolicy.approvalHash(task))
            store.save(task)
            emit(task, "candidate_ready", mapOf("attempt" to attempt.number))
            task
        } catch (error: Throwable) {
            failAttempt(task, attempt, error)
        }
    }

    @Synchronized
    fun rollback(taskId: String): AgentSelfEvolutionTask {
        val task = requireTask(taskId)
        task.attempts.forEach { attempt -> runCatching { runtime.discard(task, attempt) } }
        val rolledBack = task.copy(
            status = AgentSelfEvolutionStatus.ROLLED_BACK,
            candidateCommit = "",
            candidateBranch = "",
            approvalHash = "",
            updatedAtMillis = clock()
        )
        store.save(rolledBack)
        emit(rolledBack, "rolled_back")
        return rolledBack
    }

    @Synchronized
    fun cancel(taskId: String): AgentSelfEvolutionTask {
        val task = requireTask(taskId)
        val cancelled = task.copy(
            status = AgentSelfEvolutionStatus.CANCELLED,
            lastErrorCode = "cancelled",
            lastError = "Evolution task was cancelled",
            updatedAtMillis = clock()
        )
        store.save(cancelled)
        emit(cancelled, "cancelled")
        return cancelled
    }

    fun get(taskId: String): AgentSelfEvolutionTask? = store.get(taskId)

    fun list(limit: Int = 100): List<AgentSelfEvolutionTask> = store.list(limit)

    fun health(
        limit: Int = 500,
        nowMillis: Long = clock(),
        staleAfterMillis: Long = 30 * 60_000L
    ): AgentSelfEvolutionHealth = AgentSelfEvolutionHealthAnalyzer.summarize(
        store.list(limit),
        nowMillis,
        staleAfterMillis
    )

    private fun requireTask(taskId: String): AgentSelfEvolutionTask =
        store.get(taskId) ?: throw IllegalArgumentException("Evolution task was not found")

    private fun failAttempt(
        task: AgentSelfEvolutionTask,
        attempt: AgentSelfEvolutionAttempt,
        error: Throwable
    ): AgentSelfEvolutionTask {
        runCatching { runtime.discard(task, attempt) }
        val code = (error as? AgentSelfEvolutionException)?.code
            ?: if (error is AgentNativeToolCancelledException) "cancelled" else "evolution_failed"
        val blocked = (error as? AgentSelfEvolutionException)?.blocked == true
        val terminal = when {
            code == "cancelled" -> AgentSelfEvolutionStatus.CANCELLED
            blocked -> AgentSelfEvolutionStatus.BLOCKED
            consumedAttemptCount(task, code) >= task.maxAttempts -> AgentSelfEvolutionStatus.FAILED
            else -> AgentSelfEvolutionStatus.PROPOSED
        }
        val failedAttempt = attempt.copy(
            status = when {
                code == "cancelled" -> AgentSelfEvolutionStatus.CANCELLED
                blocked -> AgentSelfEvolutionStatus.BLOCKED
                else -> AgentSelfEvolutionStatus.FAILED
            },
            failureCode = code,
            failureSummary = error.message.orEmpty().take(4_000),
            completedAtMillis = clock()
        )
        val failed = task.copy(
            status = terminal,
            attempts = task.attempts.dropLast(1) + failedAttempt,
            lastErrorCode = code,
            lastError = error.message.orEmpty().take(4_000),
            updatedAtMillis = clock()
        )
        store.save(failed)
        emit(failed, if (blocked) "blocked" else "attempt_failed", mapOf("attempt" to attempt.number))
        return failed
    }

    private fun consumedAttemptCount(
        task: AgentSelfEvolutionTask,
        pendingFailureCode: String? = null
    ): Int {
        if (pendingFailureCode == null) {
            return task.attempts.count { attempt ->
                attempt.failureCode !in NON_CONSUMING_FAILURE_CODES
            }
        }
        val previous = task.attempts.dropLast(1).count { attempt ->
            attempt.failureCode !in NON_CONSUMING_FAILURE_CODES
        }
        return previous + if (pendingFailureCode in NON_CONSUMING_FAILURE_CODES) 0 else 1
    }

    private fun emit(
        task: AgentSelfEvolutionTask,
        event: String,
        metadata: AgentNativeJsonObject = emptyMap()
    ) {
        eventSink.onEvent(linkedMapOf(
            "type" to "evolution_task_event",
            "event" to event,
            "task" to task.publicValue(),
            "metadata" to metadata,
            "timestamp_millis" to clock()
        ))
    }

    private fun AgentNativeToolCancellationToken.throwIfCancelled() {
        if (isCancellationRequested) throw AgentNativeToolCancelledException()
    }

    private companion object {
        const val MAX_PATCH_BYTES = 160 * 1024
        val TASK_ID_PATTERN = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,95}")
        val NON_CONSUMING_FAILURE_CODES = setOf(
            "runtime_unavailable",
            "git_unavailable",
            "android_sdk_unavailable"
        )

        fun workspaceId(taskId: String, attempt: Int): String =
            "evo-${taskId.takeLast(40)}-$attempt".take(64)
    }
}

object AgentSelfEvolutionPolicy {
    private val safeComponent = Regex("[A-Za-z0-9._+@() -]+")
    private val protectedComponents = setOf(".git", "node_modules", "dist", "build", "runtime-data")

    fun normalizedScope(values: List<String>): List<String> {
        val normalized = values.map { it.replace('\\', '/').trim().trim('/') }
            .filter(String::isNotBlank)
            .distinct()
        require(normalized.size in 1..64) { "Evolution tasks require 1 to 64 scoped paths" }
        normalized.forEach { value ->
            val parts = value.split('/')
            require(value.length <= 512 && parts.all { part ->
                part !in setOf("", ".", "..") && safeComponent.matches(part)
            }) { "Evolution scope is unsafe: $value" }
            require(parts.none { it.lowercase(Locale.ROOT) in protectedComponents }) {
                "Evolution scope is protected: $value"
            }
        }
        return normalized
    }

    fun requireChangedFilesInScope(scope: List<String>, changedFiles: List<String>) {
        val violations = changedFiles.filter { changed ->
            scope.none { root -> changed == root || changed.startsWith("${root.trimEnd('/')}/") }
        }
        if (violations.isNotEmpty()) {
            throw AgentSelfEvolutionException(
                "scope_violation",
                "Candidate changed files outside the declared scope: ${violations.take(20).joinToString()}"
            )
        }
    }

    fun approvalHash(task: AgentSelfEvolutionTask): String {
        val attempt = task.attempts.last()
        val payload = buildString {
            append(task.protocol).append('\n')
            append(task.taskId).append('\n')
            append(task.baseCommit).append('\n')
            append(task.candidateCommit).append('\n')
            append(task.risk.wireValue).append('\n')
            task.scope.sorted().forEach { append(it).append('\n') }
            attempt.gates.forEach {
                append(it.id).append(':').append(it.status.wireValue).append(':').append(it.exitCode).append('\n')
            }
        }
        return MessageDigest.getInstance("SHA-256")
            .digest(payload.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
    }
}

class AndroidAgentSelfEvolutionRuntime(
    context: Context,
    private val runtimeManager: AgentOnDeviceRuntimeManager = AgentOnDeviceRuntimeManager(context.applicationContext)
) : AgentSelfEvolutionRuntime {
    private val appContext = context.applicationContext

    override fun prepare(
        task: AgentSelfEvolutionTask,
        attempt: AgentSelfEvolutionAttempt,
        cancellationToken: AgentNativeToolCancellationToken
    ): AgentSelfEvolutionPrepareResult {
        val status = runtimeManager.status()
        if (!status.backendReady || !status.languageReady(AgentRuntimeLanguage.SHELL)) {
            throw AgentSelfEvolutionException(
                "runtime_unavailable",
                status.reason.ifBlank { "Install and start the Android-local Linux runtime" },
                blocked = true
            )
        }
        val response = execute(
            attempt,
            """
                set -eu
                if ! command -v git >/dev/null 2>&1; then
                  echo "GALAXYSSI_ERROR=git_unavailable" >&2
                  exit 71
                fi
                rm -rf source
                git clone --depth 1 --branch main --single-branch "$OFFICIAL_REPOSITORY" source
                cd source
                base="${'$'}(git rev-parse HEAD)"
                git checkout -b "${attempt.branch}"
                printf 'GALAXYSSI_BASE=%s\n' "${'$'}base"
            """.trimIndent(),
            networkEnabled = true,
            timeoutMillis = 15 * 60_000L,
            cancellationToken = cancellationToken
        )
        if (response.exitCode != 0) {
            val missingGit = "GALAXYSSI_ERROR=git_unavailable" in response.stderr
            throw AgentSelfEvolutionException(
                if (missingGit) "git_unavailable" else "source_checkout_failed",
                if (missingGit) {
                    "Install the Git runtime package before preparing Android-local evolution tasks"
                } else {
                    response.failureSummary("Android-local source checkout failed")
                },
                blocked = missingGit
            )
        }
        val base = response.marker("GALAXYSSI_BASE")
        if (!SHA256_PATTERN.matches(base)) {
            throw AgentSelfEvolutionException("base_commit_missing", "Source checkout did not report a valid base commit")
        }
        return AgentSelfEvolutionPrepareResult(base, attempt.branch)
    }

    override fun applyPatch(
        task: AgentSelfEvolutionTask,
        attempt: AgentSelfEvolutionAttempt,
        unifiedDiff: String,
        cancellationToken: AgentNativeToolCancellationToken
    ): AgentSelfEvolutionPatchResult {
        val encoded = Base64.getEncoder().encodeToString(unifiedDiff.toByteArray(Charsets.UTF_8))
        val response = execute(
            attempt,
            """
                set -eu
                cd source
                printf '%s' '$encoded' | base64 -d > ../candidate.patch
                git apply --check ../candidate.patch
                git apply ../candidate.patch
                {
                  git diff --name-only
                  git ls-files --others --exclude-standard
                } | sed '/^$/d' | sort -u | sed 's/^/GALAXYSSI_CHANGED=/'
            """.trimIndent(),
            timeoutMillis = 5 * 60_000L,
            cancellationToken = cancellationToken
        )
        if (response.exitCode != 0) {
            throw AgentSelfEvolutionException(
                "patch_apply_failed",
                response.failureSummary("Android-local candidate patch could not be applied")
            )
        }
        return AgentSelfEvolutionPatchResult(
            response.stdout.lineSequence()
                .filter { it.startsWith("GALAXYSSI_CHANGED=") }
                .map { it.substringAfter('=').replace('\\', '/') }
                .filter(String::isNotBlank)
                .distinct()
                .sorted()
                .toList()
        )
    }

    override fun validate(
        task: AgentSelfEvolutionTask,
        attempt: AgentSelfEvolutionAttempt,
        changedFiles: List<String>,
        cancellationToken: AgentNativeToolCancellationToken
    ): List<AgentSelfEvolutionGate> {
        val gates = mutableListOf<AgentSelfEvolutionGate>()
        gates += runGate(
            attempt,
            "git-diff-check",
            "cd source && git diff --check",
            60_000L,
            cancellationToken
        )
        if (gates.last().status != AgentSelfEvolutionGateStatus.PASSED) return gates
        if (changedFiles.any { it.startsWith("apps/android/") || it.startsWith("core/") }) {
            gates += runGate(
                attempt,
                "android-unit-build",
                """
                    set -eu
                    cd source/apps/android
                    if [ -z "${'$'}{ANDROID_HOME:-}" ] && [ -z "${'$'}{ANDROID_SDK_ROOT:-}" ]; then
                      echo "Android SDK is not installed in the local runtime" >&2
                      exit 72
                    fi
                    ./gradlew :app:testDebugUnitTest :app:assembleDebug --no-daemon
                """.trimIndent(),
                30 * 60_000L,
                cancellationToken,
                networkEnabled = true
            )
            if (gates.last().exitCode == ANDROID_SDK_MISSING_EXIT_CODE) {
                throw AgentSelfEvolutionException(
                    "android_sdk_unavailable",
                    gates.last().summary.ifBlank { "Install the Android SDK build runtime" },
                    blocked = true
                )
            }
            if (gates.last().status != AgentSelfEvolutionGateStatus.PASSED) return gates
        }
        if (changedFiles.any { it.startsWith("apps/desktop/") || it.startsWith("core/") }) {
            gates += runGate(
                attempt,
                "desktop-source-check",
                """
                    set -eu
                    cd source/apps/desktop
                    python3 -m unittest discover -s core/galaxyssi-link/backend -p 'test_*.py'
                    node scripts/check.js
                """.trimIndent(),
                30 * 60_000L,
                cancellationToken
            )
        }
        return gates
    }

    override fun commit(
        task: AgentSelfEvolutionTask,
        attempt: AgentSelfEvolutionAttempt,
        cancellationToken: AgentNativeToolCancellationToken
    ): AgentSelfEvolutionCommitResult {
        val response = execute(
            attempt,
            """
                set -eu
                cd source
                git add --all
                git -c user.name='GalaxySSI Evolution' -c user.email='galaxyssi@hotmail.com' \
                  commit -m 'Prepare evolution candidate ${task.taskId}'
                printf 'GALAXYSSI_COMMIT=%s\n' "${'$'}(git rev-parse HEAD)"
            """.trimIndent(),
            timeoutMillis = 2 * 60_000L,
            cancellationToken = cancellationToken
        )
        if (response.exitCode != 0) {
            throw AgentSelfEvolutionException(
                "candidate_commit_failed",
                response.failureSummary("Android-local candidate could not be committed")
            )
        }
        val commit = response.marker("GALAXYSSI_COMMIT")
        if (!SHA256_PATTERN.matches(commit)) {
            throw AgentSelfEvolutionException("candidate_commit_missing", "Candidate commit id is invalid")
        }
        return AgentSelfEvolutionCommitResult(commit)
    }

    override fun discard(task: AgentSelfEvolutionTask, attempt: AgentSelfEvolutionAttempt) {
        val project = File(appContext.filesDir, "agent-native-workspaces/${attempt.workspaceId}")
        val canonicalRoot = File(appContext.filesDir, "agent-native-workspaces").canonicalFile
        val canonicalProject = project.canonicalFile
        if (canonicalProject.path.startsWith(canonicalRoot.path + File.separator)) {
            canonicalProject.deleteRecursively()
        }
    }

    private fun runGate(
        attempt: AgentSelfEvolutionAttempt,
        id: String,
        source: String,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken,
        networkEnabled: Boolean = false
    ): AgentSelfEvolutionGate {
        val started = System.currentTimeMillis()
        val response = execute(
            attempt,
            source,
            networkEnabled = networkEnabled,
            timeoutMillis = timeoutMillis,
            cancellationToken = cancellationToken
        )
        return AgentSelfEvolutionGate(
            id = id,
            status = if (response.exitCode == 0) {
                AgentSelfEvolutionGateStatus.PASSED
            } else AgentSelfEvolutionGateStatus.FAILED,
            durationMillis = System.currentTimeMillis() - started,
            exitCode = response.exitCode,
            summary = if (response.exitCode == 0) {
                response.stdout.lineSequence().filter(String::isNotBlank).toList().takeLast(8).joinToString("\n")
                    .ifBlank { "Passed" }
            } else response.failureSummary("Quality gate failed")
        )
    }

    private fun execute(
        attempt: AgentSelfEvolutionAttempt,
        source: String,
        networkEnabled: Boolean = false,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken
    ): AgentRuntimeExecutionResponse = runtimeManager.execute(
        AgentRuntimeExecutionRequest(
            language = AgentRuntimeLanguage.SHELL,
            source = source,
            arguments = emptyList(),
            timeoutMillis = timeoutMillis,
            networkEnabled = networkEnabled,
            allowedNetworkDomains = if (networkEnabled) NETWORK_DOMAINS else emptyList(),
            artifactPaths = emptyList(),
            workspaceId = attempt.workspaceId,
            requestId = "evo-${UUID.randomUUID()}",
            cancellationToken = cancellationToken,
            resourceLimits = AgentRuntimeResourceLimits(
                wallClockMillis = timeoutMillis,
                cpuMillis = (timeoutMillis * 9L / 10L).coerceAtLeast(100L),
                memoryBytes = 2L * 1024L * 1024L * 1024L,
                diskBytes = 4L * 1024L * 1024L * 1024L,
                maxProcesses = 256,
                maxOutputBytes = 4L * 1024L * 1024L,
                maxArtifactBytes = 2L * 1024L * 1024L * 1024L
            )
        )
    )

    private fun AgentRuntimeExecutionResponse.marker(name: String): String =
        stdout.lineSequence().firstOrNull { it.startsWith("$name=") }?.substringAfter('=').orEmpty().trim()

    private fun AgentRuntimeExecutionResponse.failureSummary(fallback: String): String =
        stderr.trim().ifBlank { stdout.trim() }.ifBlank { fallback }.takeLast(4_000)

    private companion object {
        const val OFFICIAL_REPOSITORY = "https://github.com/galaxyssi/GalaxySSI.git"
        const val ANDROID_SDK_MISSING_EXIT_CODE = 72
        val NETWORK_DOMAINS = listOf(
            "github.com",
            "objects.githubusercontent.com",
            "raw.githubusercontent.com",
            "services.gradle.org",
            "plugins.gradle.org",
            "dl.google.com",
            "maven.google.com",
            "repo.maven.apache.org"
        )
        val SHA256_PATTERN = Regex("[0-9a-f]{40,64}")
    }
}

internal object AgentSelfEvolutionJson {
    fun encode(task: AgentSelfEvolutionTask): String = JSONObject()
        .put("protocol", task.protocol)
        .put("task_id", task.taskId)
        .put("problem", task.problem)
        .put("reproduction_steps", JSONArray(task.reproductionSteps))
        .put("scope", JSONArray(task.scope))
        .put("acceptance", JSONArray(task.acceptance))
        .put("risk_level", task.risk.wireValue)
        .put("max_attempts", task.maxAttempts)
        .put("status", task.status.wireValue)
        .put("execution_target", task.executionTarget)
        .put("base_commit", task.baseCommit)
        .put("candidate_commit", task.candidateCommit)
        .put("candidate_branch", task.candidateBranch)
        .put("approval_hash", task.approvalHash)
        .put("attempts", JSONArray().apply { task.attempts.forEach { put(encodeAttempt(it)) } })
        .put("last_error_code", task.lastErrorCode)
        .put("last_error", task.lastError)
        .put("created_at_millis", task.createdAtMillis)
        .put("updated_at_millis", task.updatedAtMillis)
        .toString()

    fun decode(raw: String): AgentSelfEvolutionTask? = runCatching {
        if (raw.isBlank()) return@runCatching null
        val json = JSONObject(raw)
        if (json.optString("protocol") != AGENT_SELF_EVOLUTION_PROTOCOL) return@runCatching null
        AgentSelfEvolutionTask(
            taskId = json.getString("task_id"),
            problem = json.getString("problem"),
            reproductionSteps = json.optJSONArray("reproduction_steps").strings(),
            scope = json.getJSONArray("scope").strings(),
            acceptance = json.getJSONArray("acceptance").strings(),
            risk = AgentSelfEvolutionRisk.entries.first { it.wireValue == json.getString("risk_level") },
            maxAttempts = json.getInt("max_attempts"),
            status = AgentSelfEvolutionStatus.entries.first { it.wireValue == json.getString("status") },
            executionTarget = json.optString("execution_target", "android"),
            baseCommit = json.optString("base_commit"),
            candidateCommit = json.optString("candidate_commit"),
            candidateBranch = json.optString("candidate_branch"),
            approvalHash = json.optString("approval_hash"),
            attempts = json.optJSONArray("attempts").objects().map(::decodeAttempt),
            lastErrorCode = json.optString("last_error_code"),
            lastError = json.optString("last_error"),
            createdAtMillis = json.optLong("created_at_millis"),
            updatedAtMillis = json.optLong("updated_at_millis")
        )
    }.getOrNull()

    private fun encodeAttempt(attempt: AgentSelfEvolutionAttempt): JSONObject = JSONObject()
        .put("number", attempt.number)
        .put("status", attempt.status.wireValue)
        .put("workspace_id", attempt.workspaceId)
        .put("branch", attempt.branch)
        .put("changed_files", JSONArray(attempt.changedFiles))
        .put("gates", JSONArray().apply {
            attempt.gates.forEach { gate ->
                put(JSONObject()
                    .put("id", gate.id)
                    .put("status", gate.status.wireValue)
                    .put("duration_millis", gate.durationMillis)
                    .put("exit_code", gate.exitCode)
                    .put("summary", gate.summary))
            }
        })
        .put("failure_code", attempt.failureCode)
        .put("failure_summary", attempt.failureSummary)
        .put("started_at_millis", attempt.startedAtMillis)
        .put("completed_at_millis", attempt.completedAtMillis)

    private fun decodeAttempt(json: JSONObject): AgentSelfEvolutionAttempt = AgentSelfEvolutionAttempt(
        number = json.getInt("number"),
        status = AgentSelfEvolutionStatus.entries.first { it.wireValue == json.getString("status") },
        workspaceId = json.getString("workspace_id"),
        branch = json.getString("branch"),
        changedFiles = json.optJSONArray("changed_files").strings(),
        gates = json.optJSONArray("gates").objects().map { gate ->
            AgentSelfEvolutionGate(
                id = gate.getString("id"),
                status = AgentSelfEvolutionGateStatus.entries.first { it.wireValue == gate.getString("status") },
                durationMillis = gate.optLong("duration_millis"),
                exitCode = gate.optInt("exit_code"),
                summary = gate.optString("summary")
            )
        },
        failureCode = json.optString("failure_code"),
        failureSummary = json.optString("failure_summary"),
        startedAtMillis = json.optLong("started_at_millis"),
        completedAtMillis = json.optLong("completed_at_millis")
    )

    private fun JSONArray?.strings(): List<String> = buildList {
        val values = this@strings ?: return@buildList
        for (index in 0 until values.length()) values.optString(index).takeIf(String::isNotBlank)?.let(::add)
    }

    private fun JSONArray?.objects(): List<JSONObject> = buildList {
        val values = this@objects ?: return@buildList
        for (index in 0 until values.length()) values.optJSONObject(index)?.let(::add)
    }
}
