package com.galaxyssi.watch

import com.galaxyssi.chat.AgentConnectorAvailability
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/** The same received timestamp normalization as Android AppStore.applyConnectorAgentStatus. */
internal object WatchAgentStatus {
    fun received(agents: JSONArray, now: Long): JSONArray = JSONArray().apply {
        for (i in 0 until agents.length()) {
            val raw = agents.optJSONObject(i) ?: continue
            val item = JSONObject(raw.toString())
            val updated = item.optLong("updated_at", now)
            item.put("setup_updated_at", if (updated in 1L..9_999_999_999L) updated * 1000L else updated)
            item.put("setup_status", item.optString("status", "needs_setup"))
            put(item)
        }
    }

    fun available(agent: JSONObject, now: Long): Boolean = AgentConnectorAvailability.desktopAgentReady(agent, now)

    fun label(agent: JSONObject, now: Long): Int {
        val timestamp = agent.optLong("setup_updated_at", 0L)
        val age = now - timestamp
        if (timestamp <= 0L || age !in -AgentConnectorAvailability.MAX_CLOCK_SKEW_MILLIS..AgentConnectorAvailability.DESKTOP_STATUS_TTL_MILLIS)
            return R.string.agent_status_stale
        return when (agent.optString("setup_status").lowercase(Locale.US)) {
            "ready" -> R.string.agent_status_ready
            "busy" -> R.string.agent_status_busy
            "offline", "disconnected", "unreachable", "timed_out" -> R.string.agent_status_offline
            "needs_setup", "not_configured", "permission_required", "needs_permission" -> R.string.agent_status_setup
            "degraded", "error", "unavailable" -> R.string.agent_status_error
            "updating" -> R.string.agent_status_updating
            else -> R.string.agent_status_stale
        }
    }
}
