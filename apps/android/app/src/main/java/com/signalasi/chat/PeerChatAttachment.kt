package com.signalasi.chat

import org.json.JSONArray
import org.json.JSONObject

data class PeerChatAttachment(
    val name: String,
    val mimeType: String,
    val sizeBytes: Long,
    val uri: String = "",
    val artifactUri: String = ""
) {
    fun json(): JSONObject = JSONObject()
        .put("name", name)
        .put("mime_type", mimeType)
        .put("size_bytes", sizeBytes)
        .put("uri", uri)
        .put("artifact_uri", artifactUri)

    companion object {
        fun fromJson(value: JSONObject): PeerChatAttachment = PeerChatAttachment(
            name = value.optString("name").ifBlank { "attachment" },
            mimeType = value.optString("mime_type").ifBlank { "application/octet-stream" },
            sizeBytes = value.optLong("size_bytes", value.optLong("size", 0L)),
            uri = value.optString("uri"),
            artifactUri = value.optString("artifact_uri")
        )

        fun decode(values: JSONArray?): List<PeerChatAttachment> = buildList {
            if (values == null) return@buildList
            for (index in 0 until values.length()) {
                values.optJSONObject(index)?.let { add(fromJson(it)) }
            }
        }

        fun encode(values: List<PeerChatAttachment>): JSONArray = JSONArray().apply {
            values.forEach { put(it.json()) }
        }
    }
}
