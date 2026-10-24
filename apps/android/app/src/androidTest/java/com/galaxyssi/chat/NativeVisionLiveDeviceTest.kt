package com.galaxyssi.chat

import android.net.Uri
import android.os.SystemClock
import android.util.Base64
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
import java.io.File
import java.security.MessageDigest
import java.util.UUID

/** Opt-in transport/response probe, not a semantic oracle. Only authorized input leaves the device. */
@RunWith(AndroidJUnit4::class)
class NativeVisionLiveDeviceTest {
    @Test fun recordsConfiguredProviderResponseForAuthorizedImage(): Unit = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("live_vision") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root = context.filesDir.canonicalFile
        val source = File(requireNotNull(args.getString("vision_image_path"))).canonicalFile
        require(source.path.startsWith(root.path + File.separator) && source.isFile)
        val contacts = AppStore.contacts(context)
        val selected = requireNotNull((0 until contacts.length()).mapNotNull { contacts.optJSONObject(it) }
            .filter { !it.optBoolean("deleted", false) && it.optString("delivery_mode") == "cloud_api" }
            .map { AppStore.selectedCloudModelContact(context, it.optString("id")) ?: it }
            .firstOrNull { it.optString("cloud_model").contains("deepseek", true) && CloudModelCredentialPolicy.isAutoRoutable(it) })
        val contact = CloudModelRequestRoutingPolicy.resolve(selected, requestedModelId = "", hasImageInput = true)
        val attachment = AgentInputAttachment("vision-live", Uri.fromFile(source), source.name, "image/jpeg", source.length())
        val payload = CloudImagePayloadFactory.prepare(context, listOf(attachment)).single()
        assertTrue(payload.bytes.size <= 100_000)
        val directory = File(context.cacheDir, "native-vision-live").apply { mkdirs() }
        File(directory, "input.jpg").writeBytes(payload.bytes)
        val prompt = args.getString("vision_prompt_base64")?.let {
            String(Base64.decode(it, Base64.NO_WRAP), Charsets.UTF_8)
        } ?: context.getString(R.string.agent_attachment_default_goal)
        val report = JSONObject().put("model", contact.optString("cloud_model"))
            .put("image_bytes", payload.bytes.size).put("original_bytes", source.length())
            .put("semantic_acceptance", "requires_human_review")
            .put("sha256", MessageDigest.getInstance("SHA-256").digest(payload.bytes).joinToString("") { "%02x".format(it) })
        val cases = JSONArray()
        try {
            repeat(args.getString("vision_repeats")?.toInt()?.coerceIn(1, 3) ?: 1) {
                val started = SystemClock.elapsedRealtime()
                val answer = StringBuilder()
                var failure = ""
                var completed = false
                var firstOutput = 0L
                val tools = JSONArray()
                try {
                    withTimeout(180_000) {
                        CloudConversationStreamEngine.streamConversation(context, contact,
                            listOf(ChatMessage(0L, prompt, true, Contact("vision-live", "Fixture", ""))),
                            "vision-live-${UUID.randomUUID()}", images = listOf(payload),
                            onToolEvent = { tools.put(JSONObject().put("tool", it.tool).put("stage", it.stage)) }
                        ).collect { event ->
                            when (event) {
                                is ModelStreamEvent.TextDelta -> {
                                    if (firstOutput == 0L) firstOutput = SystemClock.elapsedRealtime() - started
                                    answer.append(event.text)
                                }
                                is ModelStreamEvent.Completed -> completed = true
                                is ModelStreamEvent.Failed -> failure = event.error.code + ": " + event.error.message.take(300)
                                else -> Unit
                            }
                        }
                    }
                    assertEquals("", failure)
                    assertTrue("No completed response", completed)
                    assertTrue(answer.isNotBlank())
                } catch (error: Throwable) {
                    if (failure.isBlank()) failure = error.javaClass.simpleName + ": " + error.message.orEmpty().take(300)
                    throw error
                } finally {
                    cases.put(JSONObject().put("answer", answer.toString()).put("completed", completed)
                        .put("failure", failure).put("ttft_ms", firstOutput).put("tools", tools)
                        .put("elapsed_ms", SystemClock.elapsedRealtime() - started))
                    File(directory, "report.json").writeText(report.put("cases", cases).toString(2))
                }
            }
        } finally {
            payload.bytes.fill(0)
            File(directory, "report.json").writeText(report.put("cases", cases).toString(2))
        }
    }
}
