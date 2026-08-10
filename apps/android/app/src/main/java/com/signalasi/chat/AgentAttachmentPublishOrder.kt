package com.signalasi.chat

import org.json.JSONObject

/** Keeps the Signal PreKey message ahead of all later messages in a fresh session. */
internal object AgentAttachmentPublishOrder {
    data class Step(
        val attachment: AgentPreparedOutboundAttachment,
        val chunkIndex: Int?
    ) {
        val type: String
            get() = if (chunkIndex == null) "input_attachment_manifest" else "input_attachment_chunk"

        fun payload(): JSONObject = chunkIndex?.let(attachment::chunkPayload)
            ?: attachment.manifestPayload(resume = false)
    }

    fun steps(attachments: List<AgentPreparedOutboundAttachment>): List<Step> = buildList {
        attachments.forEach { attachment ->
            add(Step(attachment, chunkIndex = null))
            repeat(attachment.chunkCount) { chunkIndex ->
                add(Step(attachment, chunkIndex))
            }
        }
    }
}
