package com.signalasi.chat

import org.json.JSONObject

/** Keeps the Signal PreKey message ahead of all later messages in a fresh session. */
internal object AgentAttachmentPublishOrder {
    data class Step(
        val attachment: AgentPreparedOutboundAttachment,
        val chunkIndex: Int?,
        val eagerChunks: Boolean = false
    ) {
        val type: String
            get() = if (chunkIndex == null) "input_attachment_manifest" else "input_attachment_chunk"

        fun payload(): JSONObject = chunkIndex?.let(attachment::chunkPayload)
            ?: attachment.manifestPayload(resume = false, eagerChunks = eagerChunks)
    }

    fun steps(attachments: List<AgentPreparedOutboundAttachment>): List<Step> = buildList {
        attachments.forEach { attachment ->
            add(Step(attachment, chunkIndex = null))
            repeat(attachment.chunkCount) { chunkIndex ->
                add(Step(attachment, chunkIndex))
            }
        }
    }

    fun initialSteps(attachments: List<AgentPreparedOutboundAttachment>): List<Step> = buildList {
        attachments.forEach { attachment ->
            val eager = attachment.sizeBytes <= EAGER_TRANSFER_BYTES
            add(Step(attachment, chunkIndex = null, eagerChunks = eager))
            if (eager) repeat(attachment.chunkCount) { chunkIndex ->
                add(Step(attachment, chunkIndex = chunkIndex))
            }
        }
    }

    private const val EAGER_TRANSFER_BYTES = 1024L * 1024L
}
