package com.galaxyssi.watch

import com.galaxyssi.chat.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import okio.Buffer

class WatchModelSelectionTest {
    @Test fun refreshedGpt6CatalogPreservesSelectedModelThroughWatchRequest() {
        val previous = org.json.JSONArray("""[{"agent_id":"codex","invocation_profile":{"models":["gpt-5.6-sol"]}}]""")
        val refresh = org.json.JSONArray("""[{"agent_id":"codex","status":"ready","invocation_profile":{
            "default_model":"gpt-5.6-sol","models":["gpt-5.6-sol","gpt-6-astra","gpt-6-sol","gpt-6-luna"],
            "reasoning_efforts":["low","high"]}}]""")
        val received = WatchAgentStatus.received(refresh, 100, previous).getJSONObject(0)
        val updatedProfile = AgentInvocationProfileJsonCodec.decode(received.getJSONObject("invocation_profile"))
        val updatedTarget = target("pc").copy(profile = updatedProfile)
        assertEquals("gpt-5.6-sol", updatedProfile.defaultModelId)
        for (model in listOf("gpt-6-astra", "gpt-6-sol", "gpt-6-luna")) {
            val selected = updatedTarget.normalize(WatchModelSelection(model = model, effort = "high"))
            assertEquals(model, selected.model)
            val task = WatchConversationRouting.create("scope", updatedTarget, selected, "Test", emptyList())
            val restored = WatchTask.fromJson(JSONObject(task.json().toString()))
            assertEquals(model, restored.request("zh").getJSONObject("agent_invocation").getString("model_id"))
        }
    }

    private val profile = AgentInvocationProfileJsonCodec.decode(JSONObject("""{
        "default_model":"model-b", "models":[{"id":"model-a","display_name":"A"},"model-b"],
        "reasoning_efforts":["low","medium","high"] }"""))
    private fun target(desktop: String) = WatchModelTarget("remote:$desktop:codex", desktop, "route-$desktop", "codex",
        "Codex", desktop, true, profile)

    @Test fun switchingModelPreservesLocalAndRemoteConversationAndPersistsInvocation() {
        val old = WatchTask.create("pc", "route-pc", "codex", "First").copy(state = TaskState.COMPLETED, reply = "Answer")
        val next = WatchConversationRouting.create(old.sessionId, target("pc"), WatchModelSelection(model = "model-b", effort = "high"), "Next", listOf(old))
        assertEquals(old.conversationId, next.conversationId)
        assertEquals(old.conversationKey(), next.conversationKey())
        assertNotEquals(old.id, next.id)
        val restored = WatchTask.fromJson(JSONObject(next.json().toString()))
        assertEquals(next, restored)
        val request = restored.request("zh").getJSONObject("agent_invocation")
        assertEquals("model-b", request.getString("model_id"))
        assertEquals("high", request.getString("reasoning_effort"))
        assertFalse(old.request("zh").has("agent_invocation"))
    }
    @Test fun changingComputersKeepsOneTranscriptButNeverReusesForeignRemoteSession() {
        val old = WatchTask.create("pc", "route-pc", "codex", "First").copy(state = TaskState.COMPLETED, reply = "Answer")
        val next = WatchConversationRouting.create(old.sessionId, target("other"), WatchModelSelection(), "Next", listOf(old))
        assertEquals(old.conversationKey(), next.conversationKey())
        assertNotEquals(old.conversationId, next.conversationId)
        assertTrue(WatchConversationRouting.remoteContent(next, listOf(old)).contains("Answer"))
        val returned = WatchConversationRouting.create(old.sessionId, target("pc"), WatchModelSelection(), "Back", listOf(old, next))
        assertEquals(old.conversationId, returned.conversationId)
        assertEquals(1, listOf(old, next, returned).groupBy { it.conversationKey() }.size)
        val visibility = WatchConversationVisibility(); visibility.show(Any(), old)
        assertTrue(visibility.isViewing(next))
    }
    @Test fun sameRouteInAnotherLocalConversationDoesNotLeakHistoryOrSession() {
        val old = WatchTask.create("pc", "route-pc", "codex", "Private").copy(state = TaskState.COMPLETED, reply = "Secret")
        val next = WatchConversationRouting.create("separate", target("pc"), WatchModelSelection(), "New", listOf(old))
        assertNotEquals(old.conversationKey(), next.conversationKey())
        assertNotEquals(old.conversationId, next.conversationId)
        assertEquals("New", WatchConversationRouting.remoteContent(next, listOf(old)))
    }
    @Test fun capabilityChangesNormalizeModelsAndEffortsWithAndroidRules() {
        val selected = target("pc").normalize(WatchModelSelection(model = "missing", effort = "xhigh"))
        assertEquals("model-b", selected.model)
        assertEquals("low", selected.effort)
        val unavailable = target("pc").copy(profile = AgentInvocationProfile()).normalize(selected)
        assertEquals("", unavailable.model)
        assertEquals("auto", unavailable.effort)
    }
    @Test fun cloudSwitchSendsSelectedModelAndOnlyCurrentLocalConversationHistory() {
        val old = WatchTask.create("pc", "route-pc", "codex", "First").copy(state = TaskState.COMPLETED, reply = "Answer")
        val api = ApiProfile("https://example.com/v1/chat/completions", "model-b", "test-only", "cloud")
        val cloud = WatchModelTarget("cloud:cloud", "api", "cloud", "model-b", "Cloud", "example.com", true, profile, api)
        val next = WatchConversationRouting.create(old.sessionId, cloud, WatchModelSelection(model = "model-b"), "Next", listOf(old))
        val unrelated = old.copy(conversationId = "private", reply = "SECRET")
        val call = WatchApi().request(api, next, listOf(old, unrelated))
        val buffer = Buffer(); call.request().body!!.writeTo(buffer)
        val body = JSONObject(buffer.readUtf8())
        assertEquals("model-b", body.getString("model"))
        assertEquals(3, body.getJSONArray("messages").length())
        assertTrue(body.toString().contains("Answer")); assertFalse(body.toString().contains("SECRET"))
    }
    @Test fun sameEndpointDifferentLocalSessionStillRequiresItsOwnRemoteConversation() {
        val first = WatchTask.create("pc", "route-pc", "codex", "Hello").copy(localConversationId = "one")
        val second = WatchConversationRouting.create("two", target("pc"), WatchModelSelection(), "Hi", listOf(first))
        assertNotEquals(first.conversationId, second.conversationId)
    }
    @Test fun statusOnlyRefreshPreservesModelsButExplicitEmptyProfileClearsThem() {
        val old = org.json.JSONArray("""[{"agent_id":"codex","invocation_profile":{"models":["model-a"]}}]""")
        val refresh = org.json.JSONArray("""[{"agent_id":"codex","status":"busy"}]""")
        val updated = WatchAgentStatus.received(refresh, 100, old).getJSONObject(0)
        assertEquals("model-a", updated.getJSONObject("invocation_profile").getJSONArray("models").getString(0))
        assertEquals("busy", updated.getString("setup_status"))
        refresh.getJSONObject(0).put("invocation_profile", JSONObject())
        assertEquals(0, WatchAgentStatus.received(refresh, 101, old).getJSONObject(0).getJSONObject("invocation_profile").length())
    }
}
