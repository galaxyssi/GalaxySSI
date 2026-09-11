package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Collections
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in: only this synthetic worksheet is sent; credentials and existing chats are never exported. */
@RunWith(AndroidJUnit4::class)
class CloudImageAnnotationLiveTest {
    @Test fun configuredDeepSeekProducesAnnotatedImage(): Unit = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("live_annotation") == "true")
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val contacts = AppStore.contacts(context)
        val selected = requireNotNull((0 until contacts.length()).mapNotNull { contacts.optJSONObject(it) }
            .filter { !it.optBoolean("deleted", false) && it.optString("delivery_mode") == "cloud_api" }
            .map { AppStore.selectedCloudModelContact(context, it.optString("id")) ?: it }
            .firstOrNull { it.optString("cloud_model").contains("deepseek", true) && CloudModelCredentialPolicy.isAutoRoutable(it) }) {
            "No configured DeepSeek provider; credentials must not be modified by this test"
        }
        val contact = CloudModelRequestRoutingPolicy.resolve(selected, requestedModelId = "", hasImageInput = true)
        val bitmap = Bitmap.createBitmap(1000, 700, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.WHITE) }
        Canvas(bitmap).apply {
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; textSize = 52f }
            drawText("Math homework", 70f, 90f, paint)
            drawText("1) 2 + 3 = 5", 70f, 230f, paint)
            drawText("2) 6 - 2 = 5", 70f, 380f, paint)
            drawText("3) 3 x 4 = 12", 70f, 530f, paint)
        }
        val bytes = ByteArrayOutputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
            bitmap.recycle()
            it.toByteArray()
        }
        val prompt = "\u8bf7\u6279\u6539\u8fd9\u5f20\u4f5c\u4e1a\uff0c\u5728\u539f\u56fe\u4e0a\u6807\u6ce8\u5bf9\u9519\u548c\u4fee\u6b63\u7b54\u6848\uff0c\u8fd4\u56de\u6279\u6ce8\u540e\u7684\u56fe\u7247\uff0c\u4e0d\u8981\u53ea\u7528\u6587\u5b57\u89e3\u91ca\u3002"
        val requestId = "live-annotation-${UUID.randomUUID()}"
        val started = SystemClock.elapsedRealtime()
        val answer = StringBuilder()
        val toolEvents = Collections.synchronizedList(mutableListOf<JSONObject>())
        var failure = ""
        var complete = false
        val directory = File(context.getExternalFilesDir("reports"), requestId).apply { mkdirs() }
        val report = JSONObject().put("model", contact.optString("cloud_model"))
        try {
            withTimeout(180_000) {
                CloudConversationStreamEngine.streamConversation(context, contact,
                    listOf(ChatMessage(0L, prompt, true, Contact(requestId, "Fixture", ""))), requestId,
                    images = listOf(CloudImagePayload("math.png", "image/png", bytes)),
                    onToolEvent = {
                        toolEvents += JSONObject().put("tool", it.tool).put("stage", it.stage).put("detail", it.detail)
                            .put("elapsed_ms", SystemClock.elapsedRealtime() - started)
                    }).collect {
                    when (it) {
                        is ModelStreamEvent.TextDelta -> answer.append(it.text)
                        is ModelStreamEvent.Completed -> complete = true
                        is ModelStreamEvent.Failed -> failure = it.error.code + ": " + it.error.message.take(300)
                        else -> Unit
                    }
                }
            }
            assertEquals(failure, "", failure)
            assertTrue("Model request did not complete", complete)
            val images = AgentRichContentCodec.fromText(answer.toString()).filter(CloudImageAnnotationSession::isLocalImage)
            assertEquals("Model must return exactly one locally annotated image", 1, images.size)
            val block = images.single()
            context.contentResolver.openInputStream(Uri.parse(block.uri))!!.use { input ->
                File(directory, "annotated.png").outputStream().use { input.copyTo(it) }
            }
            report.put("image_count", images.size).put("image_sha256", block.metadata["sha256"])
            File(context.filesDir, "agent-rich-output/image-annotations/${block.metadata["annotation_id"]}.png").delete()
        } finally {
            report.put("completed", complete).put("failure", failure).put("answer", answer.toString())
                .put("events", JSONArray(toolEvents.toList())).put("elapsed_ms", SystemClock.elapsedRealtime() - started)
            File(directory, "report.json").writeText(report.toString(2))
            File(context.getExternalFilesDir("reports"), "annotation-latest-path.txt").writeText(directory.absolutePath)
        }
    }
}
