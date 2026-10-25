package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativeVisionRequestDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun realPixelsGetBoundedLabeledViewsWithoutReplacingSource() {
        val bitmap = android.graphics.Bitmap.createBitmap(320, 160, android.graphics.Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(android.graphics.Color.WHITE)
        android.graphics.Canvas(bitmap).drawRect(0f, 0f, 160f, 80f,
            android.graphics.Paint().apply { color = android.graphics.Color.RED })
        val bytes = java.io.ByteArrayOutputStream().use { out ->
            bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }
        bitmap.recycle()
        val original = bytes.copyOf()
        val payload = CloudImagePayload("source.png", "image/png", bytes)
        val sheetBytes = requireNotNull(AgentVisionOrientationSheet.create(listOf(payload)))
        assertTrue(sheetBytes.size <= 100_000)
        val sheet = android.graphics.BitmapFactory.decodeByteArray(sheetBytes, 0, sheetBytes.size)
        assertEquals(1280, sheet.width)
        assertEquals(1344, sheet.height)
        for ((x, y) in listOf(160 to 272, 1040 to 192, 480 to 1104, 880 to 1184)) {
            val pixel = sheet.getPixel(x, y)
            assertTrue("Incorrect rotation at $x,$y", android.graphics.Color.red(pixel) > android.graphics.Color.blue(pixel) + 100)
        }
        sheet.recycle()
        for (style in listOf("openai", "anthropic", "gemini")) {
            val request = prepare(style, listOf(payload), "")
            assertTrue(request.conversation.toString().contains(AgentVisionOrientationSheet.CAPTION))
            val user = request.conversation.getJSONObject(request.conversation.length() - 1)
            val blocks = user.getJSONArray(if (style == "gemini") "parts" else "content")
            val imageBlock = (0 until blocks.length()).map { blocks.getJSONObject(it) }.first {
                it.has("image_url") || it.has("source") || it.has("inline_data")
            }
            val encoded = when (style) {
                "anthropic" -> imageBlock.getJSONObject("source").getString("data")
                "gemini" -> imageBlock.getJSONObject("inline_data").getString("data")
                else -> imageBlock.getJSONObject("image_url").getString("url").substringAfter(',')
            }
            assertArrayEquals(original, java.util.Base64.getDecoder().decode(encoded))
        }
        assertArrayEquals(original, bytes)
        assertNull(AgentVisionOrientationSheet.create(listOf(payload, payload)))
        sheetBytes.fill(0)
        bytes.fill(0)
        original.fill(0)
    }

    @Test fun everyCloudStyleIncludesOrientationPolicyWithNativePixels() {
        for (style in listOf("openai", "anthropic", "gemini")) {
            for (override in listOf("", "Preserve the requested response format.")) {
                val image = CloudImagePayload("photo.jpg", "image/jpeg", byteArrayOf(1, 2, 3))
                val request = prepare(style, listOf(image), override)
                val system = when (style) {
                    "anthropic" -> request.body.getString("system")
                    "gemini" -> request.body.getJSONObject("system_instruction").toString()
                    else -> request.conversation.getJSONObject(0).getString("content")
                }
                assertTrue("$style lost orientation policy", system.contains("0, 90, 180 and 270"))
                assertTrue(system.contains("equations, tables and diagrams as connected content"))
                assertTrue(request.conversation.toString().contains("AQID"))
                assertEquals("fixture-model", request.body.optString("model", "fixture-model"))
            }
        }
    }

    @Test fun textOnlyCloudRequestsDoNotReceiveVisionInstructions() {
        for (style in listOf("openai", "anthropic", "gemini")) {
            val request = prepare(style, emptyList(), "Keep this custom instruction.")
            assertFalse(request.body.toString().contains("0, 90, 180 and 270"))
            assertTrue(request.body.toString().contains("Keep this custom instruction."))
        }
    }

    private fun prepare(style: String, images: List<CloudImagePayload>, override: String) =
        CloudModelClient.prepareConversationStream(context,
            JSONObject().put("id", "vision-request-fixture").put("cloud_provider", "custom")
                .put("cloud_api_style", style).put("cloud_model", "fixture-model")
                .put("cloud_endpoint", "https://provider.invalid/v1/chat/completions")
                .put("cloud_api_key", "fixture-only"),
            listOf(ChatMessage(0L, "Inspect this image.", true, Contact("fixture", "Fixture", ""))),
            "vision-request-fixture", images, override)
}
