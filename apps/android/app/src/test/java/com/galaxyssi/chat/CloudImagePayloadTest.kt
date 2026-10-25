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

    @Test fun explicitOriginalAcceptsImageWithoutTheCompressedLimit() {
        val original = CloudImagePayload("original.jpg", "image/jpeg", ByteArray(512_001), original = true)
        assertEquals(512_001, original.bytes.size)
        assertTrue(original.original)
    }

    @Test fun originalDoesNotBypassExistingAttachmentMemoryBound() {
        assertTrue(runCatching {
            CloudImagePayload("oversize.jpg", "image/jpeg",
                ByteArray(AgentImagePipeline.MAX_ORIGINAL_BYTES + 1), original = true)
        }.isFailure)
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

    @Test fun historicalImagesRemainSeparateFromCurrentTextForEveryApiStyle() {
        for (style in listOf("openai", "anthropic", "gemini")) {
            val prior = message(style, "assistant", "Earlier explanation")
            val current = message(style, "user", "Narrative translate")
            val conversation = JSONArray().put(prior).put(current)
            attach(style, conversation, listOf(image.copy(historicalSourceTurnId = "source-turn")))
            assertEquals(3, conversation.length())
            assertTrue(conversation.getJSONObject(0) === prior)
            assertTrue(conversation.getJSONObject(2) === current)
            assertEquals(message(style, "user", "Narrative translate").toString(), current.toString())
            val historical = conversation.getJSONObject(1).toString()
            assertTrue(historical.contains("source-turn"))
            assertTrue(historical.contains("not newly uploaded"))
            assertFalse(historical.contains(AgentVisionOrientationSheet.CAPTION))
            assertTrue(historical.contains(image.base64()))
        }
    }

    @Test fun mixedInputsKeepTheirSourceTurnsAndOnlyNewUploadsInCurrentMessage() {
        for (style in listOf("openai", "anthropic", "gemini")) {
            val current = message(style, "user", "Compare these")
            val conversation = JSONArray().put(current)
            val oldA = CloudImagePayload("old-a.jpg", "image/jpeg", byteArrayOf(1), historicalSourceTurnId = "turn-a")
            val oldB = CloudImagePayload("old-b.jpg", "image/jpeg", byteArrayOf(2), historicalSourceTurnId = "turn-b")
            val fresh = CloudImagePayload("new.jpg", "image/jpeg", byteArrayOf(3))
            attach(style, conversation, listOf(oldA, oldB, fresh))
            assertEquals(3, conversation.length())
            assertTrue(conversation.getJSONObject(0).toString().contains("turn-a"))
            assertTrue(conversation.getJSONObject(1).toString().contains("turn-b"))
            assertTrue(conversation.getJSONObject(2) === current)
            assertTrue(current.toString().contains(fresh.base64()))
            assertFalse(current.toString().contains("turn-a"))
            assertFalse(current.toString().contains("turn-b"))
        }
    }

    private fun message(style: String, role: String, text: String): JSONObject = JSONObject()
        .put("role", role).apply {
            if (style == "gemini") put("parts", JSONArray().put(JSONObject().put("text", text)))
            else put("content", text)
        }

    @Test fun sourceIndicesStayStableWhenHistoryIsReorderedBeforeTheCurrentTurn() {
        for (style in listOf("openai", "anthropic", "gemini")) {
            val fresh = CloudImagePayload("new.jpg", "image/jpeg", byteArrayOf(9))
            val old = CloudImagePayload("old.jpg", "image/jpeg", byteArrayOf(8), historicalSourceTurnId = "earlier")
            val conversation = JSONArray().put(message(style, "user", "Compare and mark the earlier image"))
            attach(style, conversation, listOf(fresh, old))
            assertTrue(conversation.getJSONObject(0).toString().contains("image_index=1"))
            assertFalse(conversation.getJSONObject(0).toString().contains("image_index=0"))
            assertTrue(conversation.getJSONObject(1).toString().contains("image_index=0"))
        }
    }

    @Test fun annotationContractNeverMisrepresentsAvailableHistoryAsANewUpload() {
        val contract = CloudImageAnnotationPlan.instruction(2)
        assertTrue(contract.contains("Historical references are not"))
        assertTrue(contract.contains("Only annotate when the current user request"))
        assertFalse(contract.contains("This turn contains"))
        assertEquals("", CloudImageAnnotationPlan.instruction(0))
    }

    private fun attach(style: String, conversation: JSONArray, images: List<CloudImagePayload>) {
        when (style) {
            "anthropic" -> CloudVisionPayloadEncoder.attachAnthropic(conversation, images)
            "gemini" -> CloudVisionPayloadEncoder.attachGemini(conversation, images)
            else -> CloudVisionPayloadEncoder.attachOpenAi(conversation, images)
        }
    }
}
