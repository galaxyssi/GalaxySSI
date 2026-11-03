package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import com.galaxyssi.chat.voice.modelstream.ModelStreamProvider
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class CloudSupervisedResearchDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun providerNativeResearchRetainsObservationAndReturnsTheFinalPlan() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            val arguments = JSONObject().put("content", "<html><title>Example</title><p>PUBLIC_EVIDENCE_42</p></html>")
            server.enqueue(toolResponse("web_extract", arguments))
            val final = """{"execution_location":"phone","completion_requirements":{"publication":"none","phone_linux":false},"actions":[{"kind":"DRAFT_PLAN","target":"task-complete","description":"PUBLIC_EVIDENCE_42","parameters":{}}]}"""
            server.enqueue(textResponse(final))
            val toolEvents = mutableListOf<CloudToolEvent>()
            val events = collect(server, toolEvents)
            assertTrue(events.none { it is ModelStreamEvent.Failed })
            assertEquals(final, events.filterIsInstance<ModelStreamEvent.TextDelta>().joinToString("") { it.text })
            assertEquals(1, events.filterIsInstance<ModelStreamEvent.Completed>().size)
            assertTrue(toolEvents.any { it.tool == "web_extract" && it.stage == "completed" })
            assertEquals(2, server.requestCount)
            val first = JSONObject(server.takeRequest().body.readUtf8())
            val names = first.getJSONArray("tools").let { array ->
                (0 until array.length()).map { array.getJSONObject(it).getJSONObject("function").getString("name") }
            }
            assertEquals(setOf("web_search", "web_image_search", "web_fetch", "web_extract", "web_weather"), names.toSet())
            val second = JSONObject(server.takeRequest().body.readUtf8()).getJSONArray("messages")
            assertTrue((0 until second.length()).map { second.getJSONObject(it) }
                .any { it.optString("role") == "tool" && it.toString().contains("PUBLIC_EVIDENCE_42") })
        }
    }

    @Test fun deviceMutationCannotExecuteInTheResearchTransport() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(toolResponse("galaxyssi.agent_action.set.alarm", JSONObject().put("timer_seconds", 60)))
            val tools = mutableListOf<CloudToolEvent>()
            val events = collect(server, tools)
            assertTrue(events.filterIsInstance<ModelStreamEvent.Failed>().any { it.error.code == "UNEXPECTED_TOOL_CALL" })
            assertFalse(tools.any { it.stage == "running" || it.stage == "completed" })
            assertEquals(1, server.requestCount)
        }
    }

    @Test fun readOnlySchemasMatchEachProviderWireFormat() {
        for (provider in ModelStreamProvider.entries) {
            val prepared = PreparedCloudConversationStream("fixture", provider, "", emptyMap(), JSONObject(), JSONArray(), "messages")
            CloudSupervisedResearch.install(prepared)
            val tools = prepared.body.getJSONArray("tools")
            when (provider) {
                ModelStreamProvider.ANTHROPIC -> assertTrue(tools.getJSONObject(0).has("input_schema"))
                ModelStreamProvider.GEMINI -> assertEquals(5, tools.getJSONObject(0).getJSONArray("functionDeclarations").length())
                else -> assertTrue(tools.getJSONObject(0).getJSONObject("function").has("parameters"))
            }
        }
    }

    private suspend fun collect(server: MockWebServer, toolEvents: MutableList<CloudToolEvent>): List<ModelStreamEvent> {
        val id = "native-research-${UUID.randomUUID()}"
        val contact = JSONObject().put("id", id).put("cloud_provider", "custom").put("cloud_model", "fixture")
            .put("cloud_api_key", "fixture-only").put("cloud_endpoint", server.url("/v1/chat/completions").toString())
        val events = mutableListOf<ModelStreamEvent>()
        withTimeout(30_000) {
            CloudConversationStreamEngine.streamConversation(context, contact,
                listOf(ChatMessage(0L, "Extract the supplied public content, then summarize", true, Contact(id, "Test", ""))),
                id, allowExternalTools = true, supervisedControl = true, onToolEvent = { toolEvents += it })
                .collect { events += it }
        }
        return events
    }

    private fun toolResponse(name: String, arguments: JSONObject) = event(JSONObject().put("tool_calls", JSONArray().put(
        JSONObject().put("index", 0).put("id", "call-1").put("type", "function").put("function",
            JSONObject().put("name", name).put("arguments", arguments.toString())))), "tool_calls")
    private fun textResponse(text: String) = event(JSONObject().put("content", text), "stop")
    private fun event(delta: JSONObject, finish: String): MockResponse {
        val payload = JSONObject().put("choices", JSONArray().put(JSONObject().put("index", 0).put("delta", delta).put("finish_reason", finish)))
        return MockResponse().setHeader("Content-Type", "text/event-stream").setBody("data: $payload\n\ndata: [DONE]\n\n")
    }
}
