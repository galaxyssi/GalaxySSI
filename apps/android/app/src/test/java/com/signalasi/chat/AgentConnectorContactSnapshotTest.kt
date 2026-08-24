package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AgentConnectorContactSnapshotTest {
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

    private fun contact(id: String, agentId: String = "") = JSONObject()
        .put("id", id)
        .put("signalasi_id", id)
        .put("agent_id", agentId)

    private fun model(id: String, apiKey: String) = JSONObject()
        .put("model_id", id)
        .put("endpoint", "https://api.example.test/$id")
        .put("api_key", apiKey)
        .put("api_style", "openai")
}
