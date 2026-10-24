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
