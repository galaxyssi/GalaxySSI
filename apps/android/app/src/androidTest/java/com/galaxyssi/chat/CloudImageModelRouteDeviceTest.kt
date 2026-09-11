package com.galaxyssi.chat

import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
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
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class CloudImageModelRouteDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun literalImageRequestRetainsModelToolAndModelSynthesis(): Unit = runBlocking {
        assertEquals("SM-S9480", Build.MODEL)
        MockWebServer().use { server ->
            server.start()
            val tool = JSONObject().put("index", 0).put("id", "cache-call").put("type", "function")
                .put("function", JSONObject().put("name", "web_cache").put("arguments", "{\"action\":\"status\"}"))
            server.enqueue(sse(JSONObject().put("tool_calls", JSONArray().put(tool)), "tool_calls"))
            server.enqueue(sse(JSONObject().put("content", "MODEL_AUTHORED_RESULT"), "stop"))
            val id = "image-model-route-${UUID.randomUUID()}"
            val contact = JSONObject().put("id", id).put("cloud_provider", "custom")
                .put("cloud_model", "fixture-model").put("cloud_api_key", "fixture-only-key")
                .put("cloud_endpoint", server.url("/v1/chat/completions").toString())
            val events = mutableListOf<ModelStreamEvent>()
            val tools = mutableListOf<CloudToolEvent>()
            withTimeout(30_000) {
                CloudConversationStreamEngine.streamConversation(context, contact,
                    listOf(ChatMessage(0L, "Give images of clownfish", true, Contact(id, "Fixture", ""))), id,
                    onToolEvent = { tools += it }).collect { events += it }
            }
            assertEquals(2, server.requestCount)
            val first = JSONObject(server.takeRequest(1, TimeUnit.SECONDS)!!.body.readUtf8())
            val second = JSONObject(server.takeRequest(1, TimeUnit.SECONDS)!!.body.readUtf8())
            assertTrue(first.getJSONArray("messages").toString().contains("Give images of clownfish"))
            assertTrue(second.getJSONArray("messages").toString().contains("cache-call"))
            assertTrue(second.getJSONArray("messages").toString().contains("\"role\":\"tool\""))
            assertTrue(events.any { it is ModelStreamEvent.Connected })
            assertEquals("MODEL_AUTHORED_RESULT", events.filterIsInstance<ModelStreamEvent.TextDelta>().joinToString("") { it.text })
            assertTrue(events.any { it is ModelStreamEvent.Completed && it.finishReason != "image_search" })
            assertEquals(listOf("running", "completed"), tools.map { it.stage })
        }
    }

    @Test fun blockedModelCannotBeBypassedByAnImageRequest(): Unit = runBlocking {
        assertEquals("SM-S9480", Build.MODEL)
        val store = EncryptedAgentDataDisclosureStore(context)
        val id = "blocked-image-probe-${UUID.randomUUID()}"
        val contact = JSONObject().put("id", id).put("cloud_endpoint", "https://not-a-provider.invalid")
        store.setDestinationBlocked(id, true)
        try {
            val events = mutableListOf<ModelStreamEvent>()
            CloudConversationStreamEngine.streamConversation(context, contact,
                listOf(ChatMessage(0L, "Give images of clownfish", true, Contact(id, "Test", ""))), id,
                onToolEvent = { error("Blocked request called a tool") }).collect { events += it }
            assertEquals("DISCLOSURE_BLOCKED", (events.single() as ModelStreamEvent.Failed).error.code)
        } finally { store.setDestinationBlocked(id, false) }
    }

    private fun sse(delta: JSONObject, finish: String): MockResponse {
        val payload = JSONObject().put("choices", JSONArray().put(JSONObject().put("index", 0)
            .put("delta", delta).put("finish_reason", finish)))
        return MockResponse().setHeader("Content-Type", "text/event-stream")
            .setBody("data: $payload\n\ndata: [DONE]\n\n")
    }
}
