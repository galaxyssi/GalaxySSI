package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Base64

internal data class CloudImagePayload(
    val displayName: String,
    val mimeType: String,
    val bytes: ByteArray
) {
    init {
        require(bytes.isNotEmpty()) { "Cloud image payload must not be empty" }
        require(bytes.size <= MAX_BYTES) { "Cloud image payload exceeds the 100 KB limit" }
        require(mimeType.startsWith("image/")) { "Cloud image payload must use an image MIME type" }
    }

    fun base64(): String = Base64.getEncoder().encodeToString(bytes)

    companion object {
        const val MAX_BYTES = AgentImagePipeline.TARGET_TRANSPORT_BYTES
    }
}

internal object CloudImagePayloadFactory {
    fun prepare(
        context: Context,
        attachments: List<AgentInputAttachment>
    ): List<CloudImagePayload> = attachments
        .filter(AgentInputAttachment::isImage)
        .map { attachment ->
            val encoded = AgentImagePipeline.encodeForTransport(
                context = context,
                attachment = attachment,
                byteLimit = CloudImagePayload.MAX_BYTES
            ) ?: error(context.getString(R.string.cloud_image_prepare_failed, attachment.displayName))
            CloudImagePayload(
                displayName = encoded.transportName(attachment.displayName),
                mimeType = encoded.mimeType,
                bytes = encoded.bytes
            )
        }
}

/** Adds compressed image content only to the latest user turn. */
internal object CloudVisionPayloadEncoder {
    fun attachOpenAi(conversation: JSONArray, images: List<CloudImagePayload>) {
        if (images.isEmpty()) return
        val message = latestRole(conversation, "user") ?: JSONObject()
            .put("role", "user")
            .also(conversation::put)
        val content = contentArray(message, "text")
        images.forEach { image ->
            content.put(
                JSONObject()
                    .put("type", "image_url")
                    .put(
                        "image_url",
                        JSONObject()
                            .put("url", "data:${image.mimeType};base64,${image.base64()}")
                            .put("detail", "auto")
                    )
            )
        }
        message.put("content", content)
    }

    fun attachAnthropic(conversation: JSONArray, images: List<CloudImagePayload>) {
        if (images.isEmpty()) return
        val message = latestRole(conversation, "user") ?: JSONObject()
            .put("role", "user")
            .also(conversation::put)
        val content = contentArray(message, "text")
        images.forEach { image ->
            content.put(
                JSONObject()
                    .put("type", "image")
                    .put(
                        "source",
                        JSONObject()
                            .put("type", "base64")
                            .put("media_type", image.mimeType)
                            .put("data", image.base64())
                    )
            )
        }
        message.put("content", content)
    }

    fun attachGemini(conversation: JSONArray, images: List<CloudImagePayload>) {
        if (images.isEmpty()) return
        val message = latestRole(conversation, "user") ?: JSONObject()
            .put("role", "user")
            .put("parts", JSONArray())
            .also(conversation::put)
        val parts = message.optJSONArray("parts") ?: JSONArray().also { replacement ->
            message.optString("parts").takeIf(String::isNotBlank)?.let { text ->
                replacement.put(JSONObject().put("text", text))
            }
            message.put("parts", replacement)
        }
        images.forEach { image ->
            parts.put(
                JSONObject().put(
                    "inline_data",
                    JSONObject()
                        .put("mime_type", image.mimeType)
                        .put("data", image.base64())
                )
            )
        }
    }

    private fun latestRole(conversation: JSONArray, role: String): JSONObject? {
        for (index in conversation.length() - 1 downTo 0) {
            val message = conversation.optJSONObject(index) ?: continue
            if (message.optString("role") == role) return message
        }
        return null
    }

    private fun contentArray(message: JSONObject, textType: String): JSONArray {
        val existing = message.opt("content")
        if (existing is JSONArray) return existing
        return JSONArray().apply {
            val text = when (existing) {
                null, JSONObject.NULL -> ""
                else -> existing.toString()
            }
            if (text.isNotBlank()) {
                put(JSONObject().put("type", textType).put("text", text))
            }
        }
    }
}
