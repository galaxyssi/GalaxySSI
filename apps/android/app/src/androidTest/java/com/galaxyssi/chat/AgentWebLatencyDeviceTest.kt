package com.galaxyssi.chat

import android.util.Log
import android.os.SystemClock
import android.graphics.BitmapFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.Collections
import java.util.UUID
import java.io.File

/** Opt-in real network probe. Sends only the public fixture, never existing chat history. */
@RunWith(AndroidJUnit4::class)
class AgentWebLatencyDeviceTest {
    @Test fun realDeepSeekImageLookup(): Unit = runBlocking {
        val arguments = InstrumentationRegistry.getArguments()
        assumeTrue("Enable explicitly with -e live_web true", arguments.getString("live_web") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val contacts = AppStore.contacts(context)
        val contact = requireNotNull((0 until contacts.length()).mapNotNull { contacts.optJSONObject(it) }
            .filter { !it.optBoolean("deleted", false) && it.optString("delivery_mode") == "cloud_api" }
            .map { AppStore.selectedCloudModelContact(context, it.optString("id")) ?: it }
            .firstOrNull { it.optString("cloud_model").contains("deepseek", true) && CloudModelCredentialPolicy.isAutoRoutable(it) }) {
            "No configured DeepSeek provider. Do not modify credentials to pass."
        }
        val query = arguments.getString("live_web_query") ?: "\u8bf7\u641c\u7d22\u5e76\u7ed9\u51fa\u4e00\u5f20\u5c0f\u4e11\u9c7c\u7684\u771f\u5b9e\u56fe\u7247\uff0c\u76f4\u63a5\u663e\u793a\u56fe\u7247\uff0c\u5e76\u9644\u6765\u6e90\u94fe\u63a5\u3002"
        val requestId = "web-latency-${UUID.randomUUID()}"
        val started = SystemClock.elapsedRealtime()
        val events = Collections.synchronizedList(mutableListOf<JSONObject>())
        val answer = StringBuilder()
        var firstTextMillis = -1L
        var failure = ""
        var completed = false
        var finishReason = ""
        var modelConnected = false
        withTimeout(150_000L) {
            CloudConversationStreamEngine.streamConversation(context, contact,
                listOf(ChatMessage(0L, query, true, Contact("public-web-test", "Test", ""))),
                requestId, readTimeoutMillis = 45_000L, onToolEvent = { event ->
                    val elapsed = SystemClock.elapsedRealtime() - started
                    events += JSONObject().put("tool", event.tool).put("stage", event.stage).put("elapsed_ms", elapsed)
                        .put("detail", event.detail)
                    Log.i("GalaxySSIWebLatency", "tool=${event.tool} stage=${event.stage} elapsed_ms=$elapsed")
                }).collect { event ->
                    when (event) {
                        is ModelStreamEvent.Connected -> modelConnected = true
                        is ModelStreamEvent.TextDelta -> {
                            if (firstTextMillis < 0) firstTextMillis = SystemClock.elapsedRealtime() - started
                            answer.append(event.text)
                        }
                        is ModelStreamEvent.Failed -> failure = event.error.code + ":" + event.error.message.take(300)
                        is ModelStreamEvent.Completed -> { completed = true; finishReason = event.finishReason.orEmpty() }
                        else -> Unit
                    }
                }
        }
        val elapsed = SystemClock.elapsedRealtime() - started
        val imageCount = Regex("!\\[[^]]*]\\(https?://").findAll(answer).count()
        val report = JSONObject().put("model", contact.optString("cloud_model")).put("query", query)
            .put("execution_mode", "model_tool_loop").put("model_connected", modelConnected).put("finish_reason", finishReason)
            .put("elapsed_ms", elapsed).put("first_text_ms", firstTextMillis).put("image_count", imageCount)
            .put("completed", completed).put("failure", failure).put("answer", answer.toString())
            .put("events", JSONArray(events.toList()))
        val reportFile = File(context.getExternalFilesDir("reports"), "web-latency-latest.json")
        reportFile.writeText(report.toString(2))
        Log.i("GalaxySSIWebLatency", "completed=$completed elapsed_ms=$elapsed first_text_ms=$firstTextMillis images=$imageCount failure=$failure")
        assertEquals(failure, "", failure)
        assertTrue("Image lookup must retain the real model request", modelConnected)
        assertNotEquals("image_search", finishReason)
        assertTrue("Provider did not complete", completed)
        assertTrue("No visible answer", answer.isNotBlank())
        if (arguments.getString("require_image", "true") == "true") {
            assertTrue("No Markdown image in real response", imageCount > 0)
            assertTrue("No source link in real response", Regex("(?<!!)\\[[^]]*]\\(https?://").containsMatchIn(answer))
            val imageUrl = Regex("!\\[[^]]*]\\((https?://[^\\s)]+)").find(answer)!!.groupValues[1]
            val imageStarted = SystemClock.elapsedRealtime()
            val loaded = runCatching {
                // Exercise the same bounded, decoder-validated loader used by the App image view.
                // The general document downloader separately rejects missing Content-Type headers.
                val bytes = AgentMarkdownImageStore.load(context, imageUrl).readBytes()
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                check(bounds.outWidth > 0 && bounds.outHeight > 0) { "Response is not a decodable image" }
                report.put("image_width", bounds.outWidth).put("image_height", bounds.outHeight).put("image_bytes", bytes.size)
                    .put("image_loader", "app_markdown_image_store")
            }
            report.put("image_download_ms", SystemClock.elapsedRealtime() - imageStarted)
                .put("image_load_error", loaded.exceptionOrNull()?.message.orEmpty())
            reportFile.writeText(report.toString(2))
            assertTrue("Actual image could not be loaded: ${loaded.exceptionOrNull()?.message}", loaded.isSuccess)
        }
    }
}
