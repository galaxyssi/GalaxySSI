package com.galaxyssi.chat

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Base64

internal data class CloudImagePayload(
    val displayName: String,
    val mimeType: String,
    val bytes: ByteArray,
    val sourceUri: String = "",
    val original: Boolean = false,
    val historicalSourceTurnId: String = ""
) {
    init {
        require(bytes.isNotEmpty()) { "Cloud image payload must not be empty" }
        require(bytes.size <= if (original) AgentImagePipeline.MAX_ORIGINAL_BYTES else MAX_BYTES) {
            "Cloud image payload exceeds the selected quality limit"
        }
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
        attachments: List<AgentInputAttachment>,
        taskId: String = ""
    ): List<CloudImagePayload> = attachments
        .filter(AgentInputAttachment::isImage)
        .map { attachment ->
            val encoded = AgentImagePipeline.encodeForTransport(
                context = context,
                attachment = attachment,
                byteLimit = CloudImagePayload.MAX_BYTES,
                taskId = taskId
            ) ?: error(context.getString(R.string.cloud_image_prepare_failed, attachment.displayName))
            CloudImagePayload(
                displayName = encoded.transportName(attachment.displayName),
                mimeType = encoded.mimeType,
                bytes = encoded.bytes,
                sourceUri = attachment.uri.toString(),
                original = attachment.sendOriginal,
                historicalSourceTurnId = attachment.historicalSourceTurnId
            )
        }
}

/** New uploads belong to the current turn; replayed images are explicitly historical context. */
internal object CloudVisionPayloadEncoder {
    fun attachOpenAi(conversation: JSONArray, images: List<CloudImagePayload>) {
        imageTurns(conversation, images, gemini = false).forEach { (message, turnImages) ->
            attachOpenAiTurn(message, turnImages)
        }
    }

    private fun attachOpenAiTurn(message: JSONObject, turnImages: List<IndexedValue<CloudImagePayload>>) {
        val content = contentArray(message, "text")
        turnImages.forEach { (index, image) ->
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
            content.put(JSONObject().put("type", "text").put("text", sourceLabel(index)))
        }
        withOrientationSheet(turnImages.map { it.value }) { base64 ->
            content.put(JSONObject().put("type", "text").put("text", AgentVisionOrientationSheet.CAPTION))
            content.put(JSONObject().put("type", "image_url").put("image_url", JSONObject()
                .put("url", "data:image/jpeg;base64,$base64").put("detail", "auto")))
        }
        message.put("content", content)
    }

    fun attachAnthropic(conversation: JSONArray, images: List<CloudImagePayload>) {
        imageTurns(conversation, images, gemini = false).forEach { (message, turnImages) ->
            attachAnthropicTurn(message, turnImages)
        }
    }

    private fun attachAnthropicTurn(message: JSONObject, turnImages: List<IndexedValue<CloudImagePayload>>) {
        val content = contentArray(message, "text")
        turnImages.forEach { (index, image) ->
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
            content.put(JSONObject().put("type", "text").put("text", sourceLabel(index)))
        }
        withOrientationSheet(turnImages.map { it.value }) { base64 ->
            content.put(JSONObject().put("type", "text").put("text", AgentVisionOrientationSheet.CAPTION))
            content.put(JSONObject().put("type", "image").put("source", JSONObject()
                .put("type", "base64").put("media_type", "image/jpeg").put("data", base64)))
        }
        message.put("content", content)
    }

    fun attachGemini(conversation: JSONArray, images: List<CloudImagePayload>) {
        imageTurns(conversation, images, gemini = true).forEach { (message, turnImages) ->
            attachGeminiTurn(message, turnImages)
        }
    }

    private fun attachGeminiTurn(message: JSONObject, turnImages: List<IndexedValue<CloudImagePayload>>) {
        val parts = message.optJSONArray("parts") ?: JSONArray().also { replacement ->
            message.optString("parts").takeIf(String::isNotBlank)?.let { text ->
                replacement.put(JSONObject().put("text", text))
            }
            message.put("parts", replacement)
        }
        turnImages.forEach { (index, image) ->
            parts.put(
                JSONObject().put(
                    "inline_data",
                    JSONObject()
                        .put("mime_type", image.mimeType)
                        .put("data", image.base64())
                )
            )
            parts.put(JSONObject().put("text", sourceLabel(index)))
        }
        withOrientationSheet(turnImages.map { it.value }) { base64 ->
            parts.put(JSONObject().put("text", AgentVisionOrientationSheet.CAPTION))
            parts.put(JSONObject().put("inline_data", JSONObject()
                .put("mime_type", "image/jpeg").put("data", base64)))
        }
    }

    private fun sourceLabel(index: Int) = "The preceding source image has image_index=$index for image tools."

    private inline fun withOrientationSheet(images: List<CloudImagePayload>, append: (String) -> Unit) {
        if (images.any { it.historicalSourceTurnId.isNotBlank() }) return
        val bytes = runCatching { AgentVisionOrientationSheet.create(images) }.getOrNull() ?: return
        try {
            append(Base64.getEncoder().encodeToString(bytes))
        } finally {
            bytes.wipeSensitive()
        }
    }

    private fun imageTurns(
        conversation: JSONArray,
        images: List<CloudImagePayload>,
        gemini: Boolean
    ): List<Pair<JSONObject, List<IndexedValue<CloudImagePayload>>>> {
        if (images.isEmpty()) return emptyList()
        val current = latestRole(conversation, "user") ?: JSONObject().put("role", "user")
            .also(conversation::put)
        val groups = images.withIndex().groupBy { it.value.historicalSourceTurnId }
        val historical = groups.filterKeys(String::isNotBlank).map { (sourceTurn, references) ->
            val label = AgentVisualTurnPolicy.historyLabel(sourceTurn)
            val message = JSONObject().put("role", "user")
            if (gemini) message.put("parts", JSONArray().put(JSONObject().put("text", label)))
            else message.put("content", label)
            message to references
        }
        if (historical.isNotEmpty()) {
            // Compacted cloud history may lack the source turn. Restore a labeled reference,
            // never move its pixels into the user's new text-only message or invent a reply.
            val items = (0 until conversation.length()).map(conversation::get)
            val insertion = items.indexOfFirst { it === current }
            val restored = items.toMutableList().apply { addAll(insertion, historical.map { it.first }) }
            restored.forEachIndexed { index, item -> conversation.put(index, item) }
        }
        return historical + listOfNotNull(groups[""]?.let { current to it })
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
