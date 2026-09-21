package com.galaxyssi.watch

import com.galaxyssi.chat.AgentConnectorAvailability
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class WatchAgentStatusTest {
    private val now = 1_800_000_000_000L
    private fun agent(status: String, time: Long = now) = JSONObject()
        .put("setup_status", status).put("setup_updated_at", time)

    @Test fun busyRemainsRoutableLikeAndroid() {
        for (status in listOf("ready", "busy", "READY", "BUSY")) {
            assertTrue(WatchAgentStatus.available(agent(status), now))
        }
        assertEquals(R.string.agent_status_busy, WatchAgentStatus.label(agent("busy"), now))
        for (status in listOf("offline", "needs_setup", "degraded", "unknown", "running", "available")) {
            assertFalse(WatchAgentStatus.available(agent(status), now))
        }
        assertFalse(WatchAgentStatus.available(agent("offline").put("available", true), now))
    }

    @Test fun expiresAtAndroidBoundaryAndHonorsClockSkew() {
        val ttl = AgentConnectorAvailability.DESKTOP_STATUS_TTL_MILLIS
        assertEquals(15_300_000L, ttl)
        assertTrue(WatchAgentStatus.available(agent("busy", now - ttl), now))
        assertFalse(WatchAgentStatus.available(agent("busy", now - ttl - 1), now))
        assertTrue(WatchAgentStatus.available(agent("ready", now + 60_000), now))
        assertFalse(WatchAgentStatus.available(agent("ready", now + 60_001), now))
        assertFalse(WatchAgentStatus.available(agent("ready", 0), now))
        assertEquals(R.string.agent_status_stale, WatchAgentStatus.label(agent("ready", now - ttl - 1), now))
    }

    @Test fun receiveNormalizesSecondsAndPreservesExplicitOldTimestamps() {
        val input = JSONArray().put(JSONObject().put("status", "busy"))
            .put(JSONObject().put("status", "ready").put("updated_at", now / 1000))
            .put(JSONObject().put("status", "ready").put("updated_at", now - 20_000_000))
            .put(JSONObject().put("status", "ready").put("updated_at", 0))
        val saved = WatchAgentStatus.received(input, now)
        assertEquals(now, saved.getJSONObject(0).getLong("setup_updated_at"))
        assertEquals(now, saved.getJSONObject(1).getLong("setup_updated_at"))
        assertTrue(WatchAgentStatus.available(saved.getJSONObject(0), now))
        assertFalse(WatchAgentStatus.available(saved.getJSONObject(2), now))
        assertFalse(WatchAgentStatus.available(saved.getJSONObject(3), now))
        assertFalse(input.getJSONObject(0).has("setup_updated_at"))
    }

    @Test fun distinctStatusLabelsAndLegacyCache() {
        assertEquals(R.string.agent_status_offline, WatchAgentStatus.label(agent("offline"), now))
        assertEquals(R.string.agent_status_setup, WatchAgentStatus.label(agent("needs_setup"), now))
        assertEquals(R.string.agent_status_error, WatchAgentStatus.label(agent("degraded"), now))
        val legacy = JSONObject().put("status", "ready").put("available", true)
        assertEquals(R.string.agent_status_stale, WatchAgentStatus.label(legacy, now))
        assertFalse(WatchAgentStatus.available(legacy, now))
    }
}
