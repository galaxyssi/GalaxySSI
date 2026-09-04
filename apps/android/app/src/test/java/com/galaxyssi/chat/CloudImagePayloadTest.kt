package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Base64

class CloudImagePayloadTest {
    private val bytes = ByteArray(CloudImagePayload.MAX_BYTES) { index -> (index % 251).toByte() }
    private val image = CloudImagePayload("photo.jpg", "image/jpeg", bytes)

    @Test
    fun payloadEnforcesOneHundredKilobyteBinaryLimit() {
        assertEquals(100_000, CloudImagePayload.MAX_BYTES)
        assertEquals(100_000, image.bytes.size)
        assertTrue(
            runCatching {
                CloudImagePayload("too-large.jpg", "image/jpeg", ByteArray(100_001))
            }.isFailure
        )
    }

    @Test
    fun openAiCompatiblePayloadAddsCompressedImageToLatestUserTurn() {
        val conversation = JSONArray()
            .put(JSONObject().put("role", "user").put("content", "Earlier"))
            .put(JSONObject().put("role", "assistant").put("content", "Reply"))
            .put(JSONObject().put("role", "user").put("content", "Inspect this image"))

        CloudVisionPayloadEncoder.attachOpenAi(conversation, listOf(image))

        assertEquals("Earlier", conversation.getJSONObject(0).getString("content"))
        val content = conversation.getJSONObject(2).getJSONArray("content")
        assertEquals("Inspect this image", content.getJSONObject(0).getString("text"))
        val url = content.getJSONObject(1).getJSONObject("image_url").getString("url")
        assertTrue(url.startsWith("data:image/jpeg;base64,"))
        assertArrayEquals(bytes, Base64.getDecoder().decode(url.substringAfter(',')))
        assertFalse(conversation.toString().contains("content://"))
    }

    @Test
    fun anthropicPayloadUsesBase64ImageSource() {
        val conversation = JSONArray().put(
            JSONObject().put("role", "user").put("content", "Read the image")
        )

        CloudVisionPayloadEncoder.attachAnthropic(conversation, listOf(image))

        val content = conversation.getJSONObject(0).getJSONArray("content")
        val source = content.getJSONObject(1).getJSONObject("source")
        assertEquals("base64", source.getString("type"))
        assertEquals("image/jpeg", source.getString("media_type"))
        assertArrayEquals(bytes, Base64.getDecoder().decode(source.getString("data")))
    }

    @Test
    fun geminiPayloadUsesInlineImageData() {
        val conversation = JSONArray().put(
            JSONObject()
                .put("role", "user")
                .put("parts", JSONArray().put(JSONObject().put("text", "Read the image")))
        )

        CloudVisionPayloadEncoder.attachGemini(conversation, listOf(image))

        val parts = conversation.getJSONObject(0).getJSONArray("parts")
        val inline = parts.getJSONObject(1).getJSONObject("inline_data")
        assertEquals("image/jpeg", inline.getString("mime_type"))
        assertArrayEquals(bytes, Base64.getDecoder().decode(inline.getString("data")))
    }
}
