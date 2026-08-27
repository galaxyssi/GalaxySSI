package com.signalasi.chat

import android.content.Context
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject

data class PeerChatAttachment(
    val name: String,
    val mimeType: String,
    val sizeBytes: Long,
    val uri: String = "",
    val artifactUri: String = "",
    val transferId: String = "",
    val sha256: String = "",
    val durationMillis: Long = 0L
) {
    fun resolvedUri(context: Context): Uri? {
        val source = if (artifactUri.isNotBlank()) {
            AgentDesktopArtifactStore.resolveBlock(
                context,
                AgentRichBlock(
                    id = artifactUri,
                    type = if (mimeType.startsWith("image/")) {
                        AgentRichBlockType.IMAGE
                    } else {
                        AgentRichBlockType.FILE
                    },
                    title = name,
                    uri = artifactUri,
                    mimeType = mimeType,
                    metadata = mapOf("artifact_source_uri" to artifactUri)
                )
            ).uri
        } else {
            uri
        }
        if (source.startsWith("signalasi-artifact://")) return null
        val parsed = source.takeIf(String::isNotBlank)?.let(Uri::parse)
        if (mimeType.startsWith("audio/", ignoreCase = true)) {
            return PeerMessageAttachmentStore.resolveAudio(context, name, parsed)
        }
        return parsed
    }

    fun json(): JSONObject = JSONObject()
        .put("name", name)
        .put("mime_type", mimeType)
        .put("size_bytes", sizeBytes)
        .put("uri", uri)
        .put("artifact_uri", artifactUri)
        .put("transfer_id", transferId)
        .put("sha256", sha256)
        .put("duration_ms", durationMillis)

    companion object {
        fun fromJson(value: JSONObject): PeerChatAttachment = PeerChatAttachment(
            name = value.optString("name").ifBlank { "attachment" },
            mimeType = value.optString("mime_type").ifBlank { "application/octet-stream" },
            sizeBytes = value.optLong("size_bytes", value.optLong("size", 0L)),
            uri = value.optString("uri"),
            artifactUri = value.optString("artifact_uri"),
            transferId = value.optString("transfer_id"),
            sha256 = value.optString("sha256"),
            durationMillis = value.optLong("duration_ms", 0L)
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

internal object PeerChatPresentation {
    fun incomingContent(payload: String, json: JSONObject?): String {
        if (json?.optString("type") == "peer_message") {
            return json.optString("content")
        }
        return json?.optString("content", payload)?.takeIf(String::isNotBlank) ?: payload
    }

    fun storedContent(content: String): String {
        val envelope = runCatching { JSONObject(content) }.getOrNull() ?: return content
        if (envelope.optString("type") != "peer_message") return content
        return envelope.optString("content")
    }
}
