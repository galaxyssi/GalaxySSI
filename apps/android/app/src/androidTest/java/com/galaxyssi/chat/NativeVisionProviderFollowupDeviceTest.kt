package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.util.UUID
import java.util.concurrent.TimeUnit

/** Exercise the actual phone stream loop; endpoints are local fixtures, not live providers. */
@RunWith(AndroidJUnit4::class)
class NativeVisionProviderFollowupDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun deepSeekAndOtherProvidersKeepHistoryAcrossStreamUnsupportedFallback(): Unit = runBlocking {
        for (style in listOf("openai", "anthropic", "gemini")) {
            MockWebServer().use { server ->
                server.start()
                server.enqueue(MockResponse().setResponseCode(400)
                    .setBody("""{"error":{"message":"stream is not supported"}}"""))
                val response = when (style) {
                    "anthropic" -> """{"content":[{"type":"text","text":"叙事、叙述。"}],"stop_reason":"end_turn"}"""
                    "gemini" -> """{"candidates":[{"content":{"parts":[{"text":"叙事、叙述。"}]},"finishReason":"STOP"}]}"""
                    else -> """{"choices":[{"message":{"role":"assistant","content":"叙事、叙述。"},"finish_reason":"stop"}]}"""
                }
                server.enqueue(MockResponse().setHeader("Content-Type", "application/json").setBody(response))
                val id = "vision-provider-followup-${UUID.randomUUID()}"
                val model = if (style == "openai") "deepseek-v4-flash-vision-exp" else "chosen-$style"
                val endpoint = if (style == "gemini") "/v1beta/models/$model:generateContent" else "/v1/chat/completions"
                val contact = JSONObject().put("id", id)
                    .put("cloud_provider", if (style == "openai") "deepseek" else "custom")
                    .put("cloud_api_style", style).put("cloud_model", model).put("cloud_api_key", "fixture-only")
                    .put("cloud_endpoint", server.url(endpoint).toString())
                val events = mutableListOf<ModelStreamEvent>()
                withTimeout(30_000) {
                    CloudConversationStreamEngine.streamConversation(context, contact,
                        listOf(ChatMessage(0L, "Narrative单词翻译", true, Contact(id, "Fixture", ""))), id,
                        images = listOf(CloudImagePayload("earlier.jpg", "image/jpeg", byteArrayOf(1, 2, 3),
                            historicalSourceTurnId = "earlier-turn")), allowExternalTools = false,
                        systemPromptOverride = "Answer the current question. Execute device operations on the phone only.")
                        .collect { events += it }
                }
                assertTrue(events.filterIsInstance<ModelStreamEvent.Failed>().toString(),
                    events.none { it is ModelStreamEvent.Failed })
                assertTrue(events.any { it is ModelStreamEvent.Completed })
                assertEquals("叙事、叙述。", events.filterIsInstance<ModelStreamEvent.TextDelta>().joinToString("") { it.text })
                assertEquals(2, server.requestCount)
                repeat(2) {
                    val request = requireNotNull(server.takeRequest(1, TimeUnit.SECONDS))
                    val body = JSONObject(request.body.readUtf8())
                    val messages = body.getJSONArray(if (style == "gemini") "contents" else "messages")
                    val current = messages.getJSONObject(messages.length() - 1).toString()
                    val reference = messages.getJSONObject(messages.length() - 2).toString()
                    assertTrue(current.contains("Narrative单词翻译"))
                    assertFalse(current.contains("AQID"))
                    assertTrue(reference.contains("earlier-turn"))
                    assertTrue(reference.contains("image_index=0"))
                    assertTrue(reference.contains("AQID"))
                    assertFalse(body.toString().contains("This turn contains"))
                    assertFalse(body.toString().contains("inspect the image twice"))
                    assertTrue(body.toString().contains("Execute device operations on the phone only."))
                    if (style == "gemini") assertTrue(request.path.orEmpty().contains(model))
                    else assertEquals(model, body.getString("model"))
                }
            }
        }
    }
}
