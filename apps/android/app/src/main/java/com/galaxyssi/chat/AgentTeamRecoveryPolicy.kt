package com.galaxyssi.chat

import android.content.Context
import java.security.MessageDigest
import org.json.JSONObject

internal class CollaborationGroupUnavailableException : IllegalArgumentException("Collaboration group is no longer available")

internal data class AgentTeamRecoveryState(
    val failures: Int = 0,
    val retryAtMillis: Long = 0,
    val progress: String = "",
    val failureType: String = "",
    val scopeMissing: Boolean = false
) {
    val stalled: Boolean get() = scopeMissing || failures >= AgentTeamRecoveryPolicy.MAX_FAILURES
}

/** Per-run recovery failures, not an action budget. Starting a supervisor is not progress. */
internal class AgentTeamRecoveryPolicy(
    private val read: (String) -> String?,
    private val write: (String, String?) -> Unit,
    private val now: () -> Long = System::currentTimeMillis
) {
    private val cache = LinkedHashMap<String, AgentTeamRecoveryState>(16, 0.75f, true)

    private constructor(database: AgentEncryptedDatabase) : this(
        { database.readString(it, "").takeIf(String::isNotBlank) },
        { id, value -> if (value == null) database.remove(id) else database.writeString(id, value) })

    constructor(context: Context) : this(AgentEncryptedDatabase(context.applicationContext, "agent_team_recovery_retry_v1"))

    @Synchronized fun state(run: String): AgentTeamRecoveryState = cache[run] ?: run {
        val saved = read(run)?.let(::JSONObject)
        val state = if (saved == null) AgentTeamRecoveryState() else AgentTeamRecoveryState(
            saved.getInt("failures").also { require(it in 0..MAX_FAILURES) },
            saved.getLong("retry_at").also { require(it >= 0) }, saved.getString("progress"),
            saved.getString("failure_type"), saved.optBoolean("scope_missing"))
        remember(run, state)
        state
    }

    @Synchronized fun mayAttempt(run: String): Boolean = state(run).let { saved ->
        !saved.stalled && now() >= saved.retryAtMillis
    }

    fun project(snapshot: AgentTeamExecutionSnapshot): AgentTeamExecutionSnapshot {
        val saved = state(snapshot.supervisorRunId)
        return if (saved.stalled && CollaborationCurrentStatePolicy.unresolved(snapshot))
            snapshot.copy(paused = true, recoveryFailureCount = saved.failures,
                recoveryScopeMissing = saved.scopeMissing) else snapshot
    }

    @Synchronized fun missingScope(run: String): AgentTeamRecoveryState =
        save(run, state(run).copy(scopeMissing = true))

    @Synchronized fun failed(snapshot: AgentTeamExecutionSnapshot, failure: Throwable): AgentTeamRecoveryState {
        val run = snapshot.supervisorRunId
        val previous = state(run)
        if (previous.stalled) return previous
        val progress = progress(snapshot)
        val failures = (if (previous.progress == progress) previous.failures + 1 else 1).coerceAtMost(MAX_FAILURES)
        val delay = (5_000L shl (failures - 1).coerceIn(0, 3)).coerceAtMost(30_000L)
        return save(run, AgentTeamRecoveryState(failures, now() + delay, progress,
            failure.javaClass.simpleName.take(120)))
    }

    /** Waiting for an outstanding result is not a failed attempt. */
    @Synchronized fun awaitingResult(run: String) {
        val previous = state(run)
        if (!previous.stalled) save(run, previous.copy(retryAtMillis = now() + 30_000L))
    }

    @Synchronized fun observed(snapshot: AgentTeamExecutionSnapshot) {
        val previous = state(snapshot.supervisorRunId)
        if (previous == AgentTeamRecoveryState()) return
        val completed = snapshot.state.isTerminal && snapshot.state != AgentTeamExecutionState.INTERRUPTED &&
            snapshot.goalDisposition !in setOf("continue", "blocked")
        if (completed || !previous.stalled && previous.progress.isNotEmpty() && previous.progress != progress(snapshot))
            reset(snapshot.supervisorRunId)
    }

    @Synchronized fun reset(run: String) {
        write(run, null)
        remember(run, AgentTeamRecoveryState())
    }

    private fun save(run: String, state: AgentTeamRecoveryState): AgentTeamRecoveryState {
        // A failed disk write must not re-enable a hot retry loop in this process.
        remember(run, state)
        write(run, JSONObject().put("failures", state.failures).put("retry_at", state.retryAtMillis)
            .put("progress", state.progress).put("failure_type", state.failureType)
            .put("scope_missing", state.scopeMissing).toString())
        return state
    }

    private fun remember(run: String, state: AgentTeamRecoveryState) {
        cache[run] = state
        while (cache.size > 256) cache.remove(cache.keys.first())
    }

    companion object {
        const val MAX_FAILURES = 10

        internal fun missingScopeFailure(failure: Throwable): Boolean =
            generateSequence(failure) { it.cause }.take(8).any { it is CollaborationGroupUnavailableException }

        internal fun progress(snapshot: AgentTeamExecutionSnapshot): String {
            val evidence = snapshot.members.filter { it.status.isTerminal && it.deliveryMode != AgentDeliveryMode.IGNORE }
                .sortedBy { it.memberId }.joinToString("\n") { "${it.memberId.length}:${it.memberId}:${it.status}" }
            return MessageDigest.getInstance("SHA-256").digest(evidence.toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it.toInt() and 255) }
        }

        internal fun requireScope(snapshot: AgentTeamExecutionSnapshot, exists: (String) -> Boolean) {
            snapshot.members.map { it.collaborationGroupId }.filter(String::isNotBlank).distinct().forEach {
                if (!exists(it)) throw CollaborationGroupUnavailableException()
            }
        }
    }
}
