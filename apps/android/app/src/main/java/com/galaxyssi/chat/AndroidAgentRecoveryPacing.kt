package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** Timing is durable across route renewals and process restarts, scoped to one task. */
internal object AndroidAgentRecoveryPacing {
    private fun store(context: Context) = context.getSharedPreferences("agent_recovery_pacing_v1", Context.MODE_PRIVATE)
    private fun read(context: Context, key: String): AgentRecoveryPacing.State {
        val prefs = store(context)
        return AgentRecoveryPacing.State(prefs.getInt("$key:attempts", 0), prefs.getLong("$key:next", 0),
            prefs.getString("$key:progress", "").orEmpty())
    }
    private fun write(context: Context, key: String, state: AgentRecoveryPacing.State) {
        store(context).edit().putInt("$key:attempts", state.attempts).putLong("$key:next", state.nextAt)
            .putString("$key:progress", state.progress).apply()
    }
    @Synchronized fun reserve(context: Context, source: Long, now: Long = System.currentTimeMillis()): Boolean {
        if (source <= 0) return false
        val key = source.toString()
        val next = AgentRecoveryPacing.reserve(read(context, key), now) ?: return false
        write(context, key, next)
        return true
    }
    @Synchronized fun observed(context: Context, source: Long, result: JSONObject) {
        val progress = listOf(result.optString("execution_generation"), result.optString("status_sequence"),
            result.optString("status"), result.optJSONObject("result_page")?.optString("sha256").orEmpty()).joinToString(":")
        val key = source.toString()
        val now = System.currentTimeMillis()
        val state = if (result.optString("status") !in AgentRemoteOutcomeCodec.TERMINAL)
            AgentRecoveryPacing.State(nextAt = now + AgentRemoteSilencePolicy.PROBE_INTERVAL, progress = progress)
        else AgentRecoveryPacing.observed(read(context, key), progress, now)
        write(context, key, state)
    }
    @Synchronized fun retire(context: Context, source: Long) {
        val key = source.toString()
        store(context).edit().remove("$key:attempts").remove("$key:next").remove("$key:progress").apply()
    }
}
