package com.signalasi.chat

import org.json.JSONObject

internal object PeerAttachmentTransferProgress {
    const val TYPE = "peer_attachment_progress"
    const val STATE_AVAILABLE = "available"
    const val STATE_UPLOADING = "uploading"
    const val STATE_DOWNLOADING = "downloading"
    const val STATE_COMPLETE = "complete"
    const val STATE_FAILED = "failed"
    const val DEFAULT_REQUEST_WINDOW_CHUNKS = 16
    const val MAX_REQUEST_WINDOW_CHUNKS = 64
    const val LARGE_ATTACHMENT_THRESHOLD_BYTES = 5L * 1024L * 1024L
    const val LARGE_REQUEST_WINDOW_BYTES = 1024 * 1024

    fun percent(receivedBytes: Long, sizeBytes: Long): Int = when {
        sizeBytes <= 0L -> 0
        receivedBytes >= sizeBytes -> 100
        else -> ((receivedBytes.coerceAtLeast(0L) * 100L) / sizeBytes).toInt().coerceIn(0, 99)
    }

    fun requestWindow(
        missingIndices: List<Int>,
        sizeBytes: Long,
        chunkSizeBytes: Int
    ): List<Int> {
        val chunkCount = if (sizeBytes > LARGE_ATTACHMENT_THRESHOLD_BYTES) {
            ((LARGE_REQUEST_WINDOW_BYTES + chunkSizeBytes - 1) / chunkSizeBytes)
                .coerceIn(1, MAX_REQUEST_WINDOW_CHUNKS)
        } else {
            DEFAULT_REQUEST_WINDOW_CHUNKS
        }
        return missingIndices.take(chunkCount)
    }

    fun event(
        transfer: AgentPreparedOutboundAttachment,
        contactId: String,
        direction: String,
        progress: Int,
        state: String,
        receivedBytes: Long = 0L
    ): JSONObject = JSONObject()
        .put("type", TYPE)
        .put("contact_id", contactId)
        .put("direction", direction)
        .put("source_message_id", transfer.scope.clientMessageId?.toString().orEmpty())
        .put("transfer_id", transfer.transferId)
        .put("attachment_ordinal", transfer.ordinal)
        .put("name", transfer.name)
        .put("original_name", transfer.originalName)
        .put("mime_type", transfer.mimeType)
        .put("size_bytes", transfer.sizeBytes)
        .put("original_size_bytes", transfer.originalSizeBytes)
        .put("sha256", transfer.sha256)
        .put("duration_ms", transfer.scope.durationMillis)
        .put("received_bytes", receivedBytes.coerceAtLeast(0L))
        .put("progress", progress.coerceIn(0, 100))
        .put("state", state)

    fun event(
        manifest: JSONObject,
        contactId: String,
        direction: String,
        progress: Int,
        state: String,
        receivedBytes: Long = 0L,
        uri: String = ""
    ): JSONObject = JSONObject()
        .put("type", TYPE)
        .put("contact_id", contactId)
        .put("direction", direction)
        .put("source_message_id", manifest.optString("client_message_id"))
        .put("transfer_id", manifest.optString("transfer_id"))
        .put("attachment_ordinal", manifest.optInt("attachment_ordinal"))
        .put("name", manifest.optString("name", "attachment"))
        .put("original_name", manifest.optString("original_name"))
        .put("mime_type", manifest.optString("mime_type", "application/octet-stream"))
        .put("size_bytes", manifest.optLong("size_bytes"))
        .put("original_size_bytes", manifest.optLong("original_size_bytes", manifest.optLong("size_bytes")))
        .put("sha256", manifest.optString("sha256"))
        .put("duration_ms", manifest.optLong("duration_ms"))
        .put("received_bytes", receivedBytes.coerceAtLeast(0L))
        .put("progress", progress.coerceIn(0, 100))
        .put("state", state)
        .also { if (uri.isNotBlank()) it.put("uri", uri) }
}
