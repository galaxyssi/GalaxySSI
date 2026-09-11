package com.galaxyssi.chat

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.net.Uri
import android.provider.MediaStore
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CloudImageAnnotationDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private fun image(): CloudImagePayload {
        val bitmap = Bitmap.createBitmap(800, 600, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.WHITE)
        Canvas(bitmap).drawText("1 + 1 = 3", 100f, 170f, Paint().apply { color = Color.BLACK; textSize = 42f })
        val bytes = ByteArrayOutputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
            bitmap.recycle()
            output.toByteArray()
        }
        return CloudImagePayload("homework.png", "image/png", bytes)
    }
    private fun arguments() = JSONObject().put("image_index", 0).put("marks", JSONArray().put(
        JSONObject().put("left", 0.1).put("top", 0.15).put("right", 0.7).put("bottom", 0.35)
            .put("verdict", "incorrect").put("note", "\u8ba1\u7b97\u9519\u8bef\uff0c1 + 1 = 2")))
    private fun block(session: CloudImageAnnotationSession): AgentRichBlock =
        AgentRichContentCodec.decode(session.artifactSuffix().substringAfter("```galaxyssi-rich\n").substringBeforeLast("```"))
            .single()
    private fun clean(block: AgentRichBlock) {
        File(context.filesDir, "agent-rich-output/image-annotations/${block.metadata["annotation_id"]}.png").delete()
    }

    @Test fun rendersVisibleMarksPreservesSourceAndPersistsCard() {
        val input = image()
        val before = input.bytes.clone()
        val session = CloudImageAnnotationSession(context, listOf(input))
        val result = JSONObject(session.execute(CloudImageAnnotationPlan.TOOL, arguments()))
        assertTrue(result.getBoolean("image_saved"))
        val block = block(session)
        try {
            val bytes = context.contentResolver.openInputStream(Uri.parse(block.uri))!!.use { it.readBytes() }
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            try {
                assertEquals(800, bitmap.width)
                assertTrue(bitmap.height > 600)
                val color = bitmap.getPixel(80, 120)
                assertTrue("Red annotation outline must exist", Color.red(color) > Color.green(color) * 2)
                assertEquals(Color.WHITE, bitmap.getPixel(20, 20))
            } finally { bitmap.recycle() }
            assertArrayEquals(before, input.bytes)
            assertEquals(block, AgentRichContentCodec.decode(AgentRichContentCodec.encode(listOf(block))).single())
            assertEquals("image/png", block.mimeType)
        } finally { clean(block) }
    }

    @Test fun saveUsesVerifiedLocalBytesAndRejectsTampering() {
        val session = CloudImageAnnotationSession(context, listOf(image()))
        session.execute(CloudImageAnnotationPlan.TOOL, arguments())
        val block = block(session)
        val name = "\u6279\u6ce8\u56fe\u7247-${block.metadata["annotation_id"]!!.take(8)}.png"
        var saved: Uri? = null
        try {
            assertTrue(CloudImageAnnotationSession.save(context, block).isSuccess)
            context.contentResolver.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Downloads._ID), "${MediaStore.Downloads.DISPLAY_NAME} = ?",
                arrayOf(name), null)!!.use { cursor ->
                assertTrue(cursor.moveToFirst())
                saved = android.content.ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cursor.getLong(0))
            }
            val expected = context.contentResolver.openInputStream(Uri.parse(block.uri))!!.use { it.readBytes() }
            val actual = context.contentResolver.openInputStream(saved!!)!!.use { it.readBytes() }
            assertArrayEquals(expected, actual)
            assertTrue(CloudImageAnnotationSession.save(context,
                block.copy(metadata = block.metadata + ("sha256" to "0".repeat(64)))).isFailure)
        } finally { saved?.let { context.contentResolver.delete(it, null, null) }; clean(block) }
    }

    @Test fun separateRequestsCannotSelectEachOthersInputsAndFailuresProduceNoCards() {
        val first = CloudImageAnnotationSession(context, listOf(image()))
        val second = CloudImageAnnotationSession(context, emptyList())
        val failed = JSONObject(second.execute(CloudImageAnnotationPlan.TOOL, arguments()))
        assertEquals("failed", failed.getString("status"))
        assertEquals("", second.artifactSuffix())
        first.execute(CloudImageAnnotationPlan.TOOL, arguments())
        val original = block(first)
        try {
            first.execute(CloudImageAnnotationPlan.TOOL, arguments())
            assertEquals(original.uri, block(first).uri)
            assertEquals(1, AgentRichContentCodec.decode(first.artifactSuffix()
                .substringAfter("```galaxyssi-rich\n").substringBeforeLast("```")).size)
        } finally { clean(original) }
    }

    @Test fun modelToolRoundAppendsVerifiedImageBeforeCompletion(): Unit = runBlocking {
        MockWebServer().use { server ->
            server.start()
            val tool = JSONObject().put("index", 0).put("id", "annotation-call").put("type", "function")
                .put("function", JSONObject().put("name", CloudImageAnnotationPlan.TOOL)
                    .put("arguments", arguments().toString()))
            server.enqueue(sse(JSONObject().put("tool_calls", JSONArray().put(tool)), "tool_calls"))
            server.enqueue(sse(JSONObject().put("content", "The sum is 2; see the annotated image."), "stop"))
            val id = "annotation-loop-${UUID.randomUUID()}"
            val contact = JSONObject().put("id", id).put("cloud_provider", "custom")
                .put("cloud_model", "fixture-model").put("cloud_api_key", "fixture-only-key")
                .put("cloud_endpoint", server.url("/v1/chat/completions").toString())
            val events = mutableListOf<ModelStreamEvent>()
            var output: AgentRichBlock? = null
            try {
                withTimeout(30_000) {
                    CloudConversationStreamEngine.streamConversation(context, contact,
                        listOf(ChatMessage(0L, "Correct this homework on the uploaded image", true, Contact(id, "Fixture", ""))),
                        id, images = listOf(image())).collect { events += it }
                }
                assertFalse(events.toString(), events.any { it is ModelStreamEvent.Failed })
                assertEquals(2, server.requestCount)
                val first = JSONObject(server.takeRequest(1, TimeUnit.SECONDS)!!.body.readUtf8())
                val second = JSONObject(server.takeRequest(1, TimeUnit.SECONDS)!!.body.readUtf8())
                assertTrue(first.getJSONArray("tools").toString().contains(CloudImageAnnotationPlan.TOOL))
                assertTrue(second.getJSONArray("messages").toString().contains("image_saved"))
                assertFalse("Private output URI must not be sent to model", second.toString().contains("content://"))
                val deltas = events.filterIsInstance<ModelStreamEvent.TextDelta>()
                val reply = deltas.joinToString("") { it.text }
                assertTrue(reply.contains("The sum is 2"))
                output = AgentRichContentCodec.decode(reply.substringAfter("```galaxyssi-rich\n")
                    .substringBeforeLast("```")).single()
                assertTrue(CloudImageAnnotationSession.isLocalImage(output!!))
                assertTrue(events.last() is ModelStreamEvent.Completed)
                assertTrue(deltas.zipWithNext().all { (left, right) -> left.sequence < right.sequence })
                assertNotNull(context.contentResolver.openInputStream(Uri.parse(output!!.uri))?.use { it.read() })
            } finally { output?.let(::clean) }
        }
    }

    @Test fun cachedEarlierRevisionCanBeSelectedAgain() {
        val session = CloudImageAnnotationSession(context, listOf(image()))
        val firstResult = session.execute(CloudImageAnnotationPlan.TOOL, arguments())
        val first = block(session)
        val revised = arguments()
        revised.getJSONArray("marks").getJSONObject(0).put("note", "Revised correction")
        session.execute(CloudImageAnnotationPlan.TOOL, revised)
        val second = block(session)
        try {
            assertNotEquals(first.uri, second.uri)
            session.selectResult(firstResult)
            assertEquals(first.uri, block(session).uri)
        } finally { clean(first); clean(second) }
    }

    private fun sse(delta: JSONObject, finish: String): MockResponse {
        val payload = JSONObject().put("choices", JSONArray().put(JSONObject().put("index", 0)
            .put("delta", delta).put("finish_reason", finish)))
        return MockResponse().setHeader("Content-Type", "text/event-stream")
            .setBody("data: $payload\n\ndata: [DONE]\n\n")
    }
}
