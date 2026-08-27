package com.signalasi.chat

import android.content.Context
import android.util.Base64
import org.json.JSONArray
import java.io.ByteArrayOutputStream

internal object SignalASIMqttAttachmentEncoder {
    fun encodeInline(
        context: Context,
        attachments: List<AgentInputAttachment>,
        mediaProfile: AgentMediaDeliveryProfile,
        maximumBytes: Int
    ): JSONArray {
        var remaining = maximumBytes
        val result = JSONArray()
        attachments.forEach { attachment ->
            val item = attachment.descriptor()
            item.remove("uri")
            item.put("transport_profile", mediaProfile.id)
            if (attachment.isImage) {
                val encoded = AgentImagePipeline.encodeForTransport(
                    context,
                    attachment,
                    minOf(remaining, mediaProfile.imageTargetBytes)
                )
                try {
                    if (encoded != null && encoded.bytes.isNotEmpty() && encoded.bytes.size <= remaining) {
                        val transportName = encoded.transportName(attachment.displayName)
                        if (transportName != attachment.displayName) {
                            item.put("original_name", attachment.displayName)
                            item.put("name", transportName)
                        }
                        item.put("mime_type", encoded.mimeType)
                        item.put("transport_size", encoded.bytes.size)
                        item.put("transport_lossless", encoded.lossless)
                        item.put("data_b64", Base64.encodeToString(encoded.bytes, Base64.NO_WRAP))
                        remaining -= encoded.bytes.size
                    } else {
                        item.put("inline_status", "metadata_only")
                    }
                } finally {
                    encoded?.wipe()
                }
            } else {
                val bytes = if (attachment.sizeBytes in 1..remaining.toLong()) {
                    readBoundedBytes(context, attachment, remaining)
                } else null
                try {
                    if (bytes != null && bytes.isNotEmpty() && bytes.size <= remaining) {
                        item.put("data_b64", Base64.encodeToString(bytes, Base64.NO_WRAP))
                        remaining -= bytes.size
                    } else {
                        item.put("inline_status", "metadata_only")
                    }
                } finally {
                    bytes?.wipeSensitive()
                }
            }
            result.put(item)
        }
        return result
    }

    fun isTransportMedia(attachment: AgentInputAttachment): Boolean =
        attachment.mimeType.startsWith("image/", ignoreCase = true) ||
            attachment.mimeType.startsWith("audio/", ignoreCase = true) ||
            attachment.mimeType.startsWith("video/", ignoreCase = true)

    private fun readBoundedBytes(
        context: Context,
        attachment: AgentInputAttachment,
        limit: Int
    ): ByteArray? = runCatching {
        context.contentResolver.openInputStream(attachment.uri)?.use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(16 * 1024)
            try {
                while (true) {
                    val read = input.read(buffer)
                    if (read <= 0) break
                    if (output.size() + read > limit) return@use null
                    output.write(buffer, 0, read)
                }
                output.toByteArray()
            } finally {
                buffer.wipeSensitive()
            }
        }
    }.getOrNull()
}
