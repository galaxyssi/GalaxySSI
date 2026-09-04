package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicInteger

class AgentConnectorContactSnapshotTest {
    @Test
    fun `fresh remote capacity report remains authoritative`() {
        val now = 1_000_000L

        val activeRuns = AgentRemoteCapacitySnapshotPolicy.activeRuns(
            reportedActiveRuns = 7,
            fallbackActiveRuns = 1,
            updatedAtMillis = now - AgentRemoteCapacitySnapshotPolicy.MAX_AGE_MILLIS,
            nowMillis = now
        )

        assertEquals(7, activeRuns)
    }

    @Test
    fun `stale remote busy report falls back to current local capacity`() {
        val now = 1_000_000L

        val activeRuns = AgentRemoteCapacitySnapshotPolicy.activeRuns(
            reportedActiveRuns = 10,
            fallbackActiveRuns = 0,
            updatedAtMillis = now - AgentRemoteCapacitySnapshotPolicy.MAX_AGE_MILLIS - 1L,
            nowMillis = now
        )

        assertEquals(0, activeRuns)
    }

    @Test
    fun `future remote capacity report beyond clock skew is ignored`() {
        val now = 1_000_000L

        val activeRuns = AgentRemoteCapacitySnapshotPolicy.activeRuns(
            reportedActiveRuns = 10,
            fallbackActiveRuns = 2,
            updatedAtMillis = now + AgentRemoteCapacitySnapshotPolicy.MAX_CLOCK_SKEW_MILLIS + 1L,
            nowMillis = now
        )

        assertEquals(2, activeRuns)
    }

    @Test
    fun `indexes contacts and resolves desktop agent aliases from one source`() {
        val snapshot = AgentConnectorContactSnapshot.from(
            JSONArray()
                .put(contact("desktop-1:codex", agentId = "codex"))
                .put(contact("desktop-1:claude", agentId = "claude"))
                .put(contact("deleted", agentId = "hermes").put("deleted", true))
        )

        assertEquals("desktop-1:codex", snapshot.contactForAgent("codex")?.getString("id"))
        assertEquals("desktop-1:claude", snapshot.contactForAgent("claude-code")?.getString("id"))
        assertNull(snapshot.contactForAgent("hermes"))
    }

    @Test
    fun `projects selected cloud model without mutating contact snapshot`() {
        val original = contact("cloud:deepseek")
            .put("delivery_mode", "cloud_api")
            .put("selected_cloud_model", "deepseek-v4")
            .put(
                "cloud_models",
                JSONArray()
                    .put(model("deepseek-v4-flash", "flash-key"))
                    .put(model("deepseek-v4", "v4-key"))
            )
        val snapshot = AgentConnectorContactSnapshot.from(JSONArray().put(original))

        val selected = snapshot.selectedCloudModel(original)

        assertEquals("deepseek-v4", selected.getString("cloud_model"))
        assertEquals("v4-key", selected.getString("cloud_api_key"))
        assertEquals("", original.optString("cloud_model"))
    }

    @Test
    fun `falls back to first cloud model when selection is absent`() {
        val contact = contact("cloud:openai")
            .put("cloud_models", JSONArray().put(model("gpt-5", "openai-key")))

        val selected = AgentConnectorContactSnapshot.from(JSONArray().put(contact)).selectedCloudModel(contact)

        assertEquals("gpt-5", selected.getString("selected_cloud_model"))
        assertEquals("https://api.example.test/gpt-5", selected.getString("cloud_endpoint"))
    }

    @Test
    fun `prefers newest sendable desktop contact over stale matching contact`() {
        val snapshot = AgentConnectorContactSnapshot.from(
            JSONArray()
                .put(contact("desktop-old:codex", agentId = "codex").put("setup_updated_at", 10L))
                .put(contact("desktop-current:codex", agentId = "codex").put("setup_updated_at", 30L))
                .put(contact("desktop-backup:codex", agentId = "codex").put("setup_updated_at", 20L))
        )

        val selected = snapshot.preferredMatchingContactId("codex") { contactId ->
            contactId != "desktop-old:codex"
        }

        assertEquals("desktop-current:codex", selected)
    }

    @Test
    fun `keeps an exact dynamic contact when its route is sendable`() {
        val snapshot = AgentConnectorContactSnapshot.from(
            JSONArray()
                .put(contact("desktop-first:codex", agentId = "codex").put("setup_updated_at", 30L))
                .put(contact("desktop-selected:codex", agentId = "codex").put("setup_updated_at", 10L))
        )

        val selected = snapshot.preferredMatchingContactId("desktop-selected:codex") { true }

        assertEquals("desktop-selected:codex", selected)
    }

    @Test
    fun `does not select a contact without a sendable secure route`() {
        val snapshot = AgentConnectorContactSnapshot.from(
            JSONArray()
                .put(contact("desktop-old:codex", agentId = "codex").put("paired_at", 10L))
                .put(contact("desktop-current:codex", agentId = "codex").put("paired_at", 20L))
        )

        val selected = snapshot.preferredMatchingContactId("codex") { false }

        assertNull(selected)
    }

    @Test
    fun `same contact revision reuses one parsed snapshot`() {
        val cache = AgentConnectorContactSnapshotCache()
        val loads = AtomicInteger()

        val first = cache.get(7L) {
            loads.incrementAndGet()
            snapshot("codex")
        }
        val second = cache.get(7L) {
            loads.incrementAndGet()
            snapshot("hermes")
        }

        assertSame(first, second)
        assertEquals(1, loads.get())
    }

    @Test
    fun `new contact revision refreshes parsed snapshot`() {
        val cache = AgentConnectorContactSnapshotCache()

        cache.get(7L) { snapshot("codex") }
        val refreshed = cache.get(8L) { snapshot("hermes") }

        assertEquals("hermes", refreshed.matchingContactIds("hermes").single())
    }

    @Test
    fun `concurrent readers build one snapshot per revision`() {
        val cache = AgentConnectorContactSnapshotCache()
        val loads = AtomicInteger()
        val start = CountDownLatch(1)
        val executor = Executors.newFixedThreadPool(8)
        val futures = (1..8).map {
            executor.submit<AgentConnectorContactSnapshot> {
                start.await()
                cache.get(9L) {
                    loads.incrementAndGet()
                    snapshot("codex")
                }
            }
        }

        start.countDown()
        val snapshots = futures.map { it.get() }
        executor.shutdownNow()

        assertTrue(snapshots.drop(1).all { it === snapshots.first() })
        assertEquals(1, loads.get())
    }

    private fun contact(id: String, agentId: String = "") = JSONObject()
        .put("id", id)
        .put("signalasi_id", id)
        .put("agent_id", agentId)

    private fun snapshot(id: String): AgentConnectorContactSnapshot =
        AgentConnectorContactSnapshot.from(JSONArray().put(contact(id)))

    private fun model(id: String, apiKey: String) = JSONObject()
        .put("model_id", id)
        .put("endpoint", "https://api.example.test/$id")
        .put("api_key", apiKey)
        .put("api_style", "openai")
}
