package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** URI-only state survives recreation without placing image bytes in Binder or saved state. */
internal data class ComposerAttachmentItem(
    val id: String,
    val uri: String,
    val name: String,
    val mime: String,
    val size: Long,
    val originalUri: String = ""
) {
    val isImage: Boolean get() = mime.startsWith("image/", ignoreCase = true)
    val source: String get() = originalUri.ifBlank { uri }
    val isCropped: Boolean get() = originalUri.isNotBlank() && originalUri != uri

    fun descriptor(): JSONObject = JSONObject().put("id", id).put("uri", uri)
        .put("name", name).put("mime_type", mime).put("size", size).put("original_uri", originalUri)

    fun cropped(uri: String, name: String, size: Long, mime: String): ComposerAttachmentItem {
        require(isImage) { "Only image attachments can be cropped" }
        require(uri.isNotBlank() && size > 0) { "Cropped image is unavailable" }
        return copy(uri = uri, name = name, size = size, mime = mime, originalUri = source)
    }

    companion object {
        fun from(json: JSONObject) = ComposerAttachmentItem(json.getString("id"), json.getString("uri"),
            json.getString("name"), json.getString("mime_type"), json.optLong("size"), json.optString("original_uri"))
        fun decode(value: String): List<ComposerAttachmentItem> {
            val array = JSONArray(value)
            return (0 until array.length()).map { from(array.getJSONObject(it)) }
        }
        fun encode(items: List<ComposerAttachmentItem>): String = JSONArray(items.map { it.descriptor() }).toString()
    }
}
