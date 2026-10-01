package com.galaxyssi.chat

import android.content.Context
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay

internal enum class AgentTeamUserControl { RUN, PAUSE, STOP }

internal object AgentTeamControlIntent {
    fun parse(text: String): AgentTeamUserControl? = when (text.trim().lowercase(java.util.Locale.ROOT)) {
        "暂停", "暫停", "暂停任务", "暫停任務", "pause" -> AgentTeamUserControl.PAUSE
        "停止", "停止任务", "停止任務", "取消任务", "取消任務", "stop", "cancel" -> AgentTeamUserControl.STOP
        "继续", "繼續", "继续任务", "繼續任務", "恢复", "恢復", "resume" -> AgentTeamUserControl.RUN
        else -> null
    }
}

/** Separate from transport failure: neither a reboot nor a retry clears explicit user intent. */
internal class AgentTeamDurableControl(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, "agent_team_user_control_v1")

    fun get(runId: String): AgentTeamUserControl = runCatching {
        AgentTeamUserControl.valueOf(database.readString(runId, AgentTeamUserControl.RUN.name))
    }.getOrDefault(AgentTeamUserControl.STOP)

    fun set(runId: String, value: AgentTeamUserControl) = database.writeString(runId, value.name)

    fun remove(runId: String) = database.remove(runId)

    suspend fun awaitDispatch(runId: String) {
        while (true) when (get(runId)) {
            AgentTeamUserControl.RUN -> return
            AgentTeamUserControl.STOP -> throw CancellationException("Agent team stopped by user")
            AgentTeamUserControl.PAUSE -> delay(1_000L)
        }
    }
}

internal object AgentTeamReconnectPolicy {
    // A bounded rate, not a bounded number of attempts. No polling floods during prolonged outages.
    fun delayMillis(attempt: Int): Long = (1_000L shl attempt.coerceIn(0, 6)).coerceAtMost(60_000L)
}

internal class AgentTeamDispatchCheckpoint(context: Context) {
    private val database = AgentEncryptedDatabase(context.applicationContext, "agent_team_dispatch_checkpoint_v1")

    fun begin(runId: String) = synchronized(LOCK) {
        check(database.readString(runId, "") != "dispatching") { "Original member dispatch must be reconciled first" }
        database.writeString(runId, "waiting")
    }

    fun dispatching(runId: String) = synchronized(LOCK) { database.writeString(runId, "dispatching") }

    fun wasNotDispatched(runId: String): Boolean = synchronized(LOCK) {
        database.readString(runId, "") in setOf("", "waiting")
    }

    fun remove(runId: String) = database.remove(runId)

    private companion object { val LOCK = Any() }
}
