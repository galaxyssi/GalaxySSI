package com.galaxyssi.chat

import android.content.Context
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.CancellationException
import org.json.JSONObject

internal data class CognitionRecoveryState(
    val failures: Int = 0,
    val retryAtMillis: Long = 0,
    val firstFailureAtMillis: Long = 0,
    val reason: String = "",
    val failureType: String = ""
) {
    val stopped: Boolean get() = failures >= AndroidCognitionRecovery.MAX_FAILURES
}

/** Failure budgets survive WorkManager replacement and are independent of normal agent actions. */
internal class AndroidCognitionRecovery(
    private val read: (String) -> String?,
    private val write: (String, String) -> Unit,
    private val now: () -> Long = System::currentTimeMillis
) {
    private constructor(database: AgentEncryptedDatabase) : this(
        { database.readString(it, "").takeIf(String::isNotBlank) }, database::writeString)

    constructor(context: Context) : this(AgentEncryptedDatabase(context.applicationContext, "cognition_recovery_v1"))

    fun state(mode: AndroidCognitionWorkMode): CognitionRecoveryState {
        val json = read(mode.name)?.let(::JSONObject) ?: return CognitionRecoveryState()
        return CognitionRecoveryState(json.getInt("failures").also { require(it in 0..MAX_FAILURES) },
            json.getLong("retry_at"), json.getLong("first_failure_at"), json.getString("reason"),
            json.optString("failure_type"))
    }

    fun mayAttempt(mode: AndroidCognitionWorkMode): Boolean = state(mode).let {
        !it.stopped && now() >= it.retryAtMillis
    }

    fun failed(mode: AndroidCognitionWorkMode, error: Throwable): CognitionRecoveryState {
        if (error is CancellationException) throw error
        val previous = state(mode)
        if (previous.stopped) return previous
        val count = previous.failures + 1
        return CognitionRecoveryState(count, now() + delayMillis(count),
            previous.firstFailureAtMillis.takeIf { previous.failures > 0 } ?: now(),
            if (error is GlobalMemorySupersessionException) "memory_integrity" else "processing_failed",
            error.javaClass.simpleName.take(120))
            .also { save(mode, it) }
    }

    fun succeeded(mode: AndroidCognitionWorkMode) {
        if (state(mode).failures != 0) save(mode, CognitionRecoveryState())
    }

    /** A retry of the same explicit work must not reset the budget again. */
    fun resumeOnce(token: String) {
        if (token.isBlank() || read("resume_token") == token) return
        AndroidCognitionWorkMode.entries.forEach { save(it, CognitionRecoveryState()) }
        write("resume_token", token)
    }

    private fun save(mode: AndroidCognitionWorkMode, state: CognitionRecoveryState) {
        write(mode.name, JSONObject().put("failures", state.failures).put("retry_at", state.retryAtMillis)
            .put("first_failure_at", state.firstFailureAtMillis).put("reason", state.reason)
            .put("failure_type", state.failureType).toString())
    }

    companion object {
        const val MAX_FAILURES = 10
        // Serialize all cognition modes, including explicit requests and projection, across worker instances.
        val execution = Mutex()
        fun delayMillis(failures: Int): Long =
            (30_000L shl (failures - 1).coerceIn(0, 6)).coerceAtMost(30 * 60_000L)

        fun reportStopped(context: Context, mode: AndroidCognitionWorkMode, state: CognitionRecoveryState) {
            val localized = AppLanguage.wrap(context)
            val reason = if (state.reason == "memory_integrity")
                localized.getString(R.string.cognition_recovery_memory_integrity)
            else localized.getString(R.string.cognition_recovery_processing_failed, state.failureType)
            ChatHistoryStore.appendSystemNotification(context,
                localized.getString(R.string.cognition_recovery_stopped, state.failures, reason),
                "cognition-stopped:${mode.name}:${state.firstFailureAtMillis}")
        }
    }
}
