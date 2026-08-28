package com.signalasi.chat

import org.json.JSONObject

internal fun MainActivity.handlePeerAttachmentTransferProgress(event: JSONObject): Boolean {
    if (event.optString("type") != PeerAttachmentTransferProgress.TYPE) return false
    val contactId = event.optString("contact_id").takeIf(String::isNotBlank) ?: return true
    val transferId = event.optString("transfer_id").takeIf(String::isNotBlank) ?: return true
    val outbound = event.optString("direction") == "outbound"
    val sourceMessageId = event.optString("source_message_id").toLongOrNull()
    val ordinal = event.optInt("attachment_ordinal", 0).coerceAtLeast(0)
    val progress = event.optInt("progress", 0).coerceIn(0, 100)
    val state = event.optString("state")
    val remoteSourceMessageId = event.optString("source_message_id")
    val list = messages.getOrPut(contactId) { mutableListOf() }
    var messageIndex = list.indexOfFirst { message ->
        message.attachments.any { it.transferId == transferId } ||
            (outbound && sourceMessageId != null && message.isMine && message.id == sourceMessageId) ||
            (!outbound && remoteSourceMessageId.isNotBlank() &&
                message.taskId == "peer:$remoteSourceMessageId")
    }

    if (messageIndex < 0 && !outbound) {
        val contact = contactById(contactId) ?: return true
        val pending = ChatMessage(
            id = newMessageId(),
            content = "",
            isMine = false,
            contact = contact,
            remoteMessageId = "pending-peer:${event.optString("source_message_id")}:$transferId",
            taskId = "peer:$remoteSourceMessageId",
            attachments = listOf(progressAttachment(event, null, progress, state))
        )
        addMessage(pending, fromIncoming = true)
        return true
    }
    if (messageIndex < 0) return true

    val message = list[messageIndex]
    val updated = message.attachments.toMutableList()
    val attachmentIndex = updated.indexOfFirst { it.transferId == transferId }
        .takeIf { it >= 0 }
        ?: ordinal.takeIf { it in updated.indices }
    if (attachmentIndex != null) {
        updated[attachmentIndex] = progressAttachment(event, updated[attachmentIndex], progress, state)
    } else {
        updated += progressAttachment(event, null, progress, state)
    }
    message.attachments = updated
    saveChatHistory(message)
    if (chatPage.visibility == android.view.View.VISIBLE && selectedContact?.id == contactId) {
        messageAdapter?.syncMessages()
    }
    summaries.getOrPut(contactId) { ContactSummary() }.apply {
        lastMessage = message.attachments.firstOrNull()?.name.orEmpty()
        lastAt = maxOf(lastAt, message.timestamp)
    }
    refreshContactList()
    return true
}

internal fun MainActivity.mergeCompletedPeerAttachmentMessage(message: ChatMessage): Boolean {
    val transferIds = message.attachments.map(PeerChatAttachment::transferId)
        .filter(String::isNotBlank)
        .toSet()
    if (transferIds.isEmpty()) return false
    val contactId = message.contact.id
    val list = messages[contactId] ?: return false
    val index = list.indexOfFirst { existing ->
        !existing.isMine && existing.attachments.any { it.transferId in transferIds }
    }
    if (index < 0) return false
    val pending = list[index]
    val pendingByTransferId = pending.attachments.associateBy(PeerChatAttachment::transferId)
    val merged = message.copy(
        id = pending.id,
        timestamp = pending.timestamp,
        attachments = message.attachments.map { attachment ->
            val progress = pendingByTransferId[attachment.transferId]
            if (progress == null) attachment else attachment.copy(
                uri = progress.uri.ifBlank { attachment.uri },
                transferProgress = progress.transferProgress,
                transferState = progress.transferState
            )
        }
    )
    merged.deliveryTrace.addAll(pending.deliveryTrace.filterNot { prior ->
        merged.deliveryTrace.any { it.stage == prior.stage && it.at == prior.at }
    })
    list[index] = merged
    saveChatHistory(merged)
    summaries.getOrPut(contactId) { ContactSummary() }.apply {
        lastMessage = merged.content.ifBlank { merged.attachments.firstOrNull()?.name.orEmpty() }
        lastAt = merged.timestamp
    }
    if (chatPage.visibility == android.view.View.VISIBLE && selectedContact?.id == contactId) {
        messageAdapter?.syncMessages()
    }
    refreshContactList()
    return true
}

internal fun MainActivity.markPeerAttachmentTransferFailed(messageId: Long, contactId: String) {
    val list = messages[contactId] ?: return
    val index = list.indexOfFirst { it.id == messageId }
    if (index < 0) return
    val message = list[index]
    if (message.attachments.none { it.transferState in setOf(
            PeerAttachmentTransferProgress.STATE_UPLOADING,
            PeerAttachmentTransferProgress.STATE_DOWNLOADING
        )
    }) return
    message.attachments = message.attachments.map { attachment ->
        if (attachment.transferState in setOf(
                PeerAttachmentTransferProgress.STATE_UPLOADING,
                PeerAttachmentTransferProgress.STATE_DOWNLOADING
            )
        ) {
            attachment.copy(transferState = PeerAttachmentTransferProgress.STATE_FAILED)
        } else attachment
    }
    saveChatHistory(message)
    if (chatPage.visibility == android.view.View.VISIBLE && selectedContact?.id == contactId) {
        messageAdapter?.syncMessages()
    }
}

private fun progressAttachment(
    event: JSONObject,
    existing: PeerChatAttachment?,
    progress: Int,
    state: String
): PeerChatAttachment {
    val outbound = event.optString("direction") == "outbound"
    val displayName = if (outbound) {
        event.optString("original_name").ifBlank { event.optString("name", "attachment") }
    } else {
        event.optString("name", "attachment")
    }
    val displaySize = if (outbound) {
        event.optLong("original_size_bytes", event.optLong("size_bytes"))
    } else {
        event.optLong("size_bytes")
    }
    return PeerChatAttachment(
        name = existing?.name?.takeIf(String::isNotBlank) ?: displayName,
        mimeType = event.optString("mime_type").ifBlank {
            existing?.mimeType ?: "application/octet-stream"
        },
        sizeBytes = existing?.sizeBytes?.takeIf { outbound && it > 0L } ?: displaySize,
        uri = event.optString("uri").ifBlank { existing?.uri.orEmpty() },
        artifactUri = existing?.artifactUri.orEmpty(),
        transferId = event.optString("transfer_id"),
        sha256 = event.optString("sha256"),
        durationMillis = event.optLong("duration_ms", existing?.durationMillis ?: 0L),
        transferProgress = progress,
        transferState = state
    )
}
