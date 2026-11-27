package com.galaxyssi.chat

import android.content.Context

internal data class LocalHistoryLine(val id: String, val mine: Boolean, val text: String, val files: List<String>, val time: Long)
internal data class LocalMessageContext(val lines: List<LocalHistoryLine>, val older: Long?, val newer: Long?)

internal fun LocalMessageHit.contextPage(ctx: Context, older: Long? = null, newer: Long? = null): LocalMessageContext? {
    if (kind == ConversationHubItemKind.CONTACT) {
        val raw = AppStore.contactById(ctx, owner) ?: return null
        if (!LocalMessageSearch.visiblePeer(ctx, owner, raw)) return null
        val page = when {
            older != null -> ChatHistoryStore.page(ctx, owner, older, 24).let { ChatHistoryViewportPage(it.messages, it.hasMore, false, it.oldestSequence, it.newestSequence) }
            newer != null -> ChatHistoryStore.pageAfter(ctx, owner, newer, 24).let { ChatHistoryViewportPage(it.messages, false, it.hasMore, null, it.nextAfterSequence) }
            else -> ChatHistoryStore.viewportPage(ctx, owner, sequence, 25)
        }
        val lines = page.messages.filterNot { it.optBoolean("isSystem") }.mapNotNull { row ->
            val body = PeerChatPresentation.storedContent(row.optString("content"))
            val files = PeerChatAttachment.decode(row.optJSONArray("attachments")).map { it.name }
            if (body.isBlank() && files.isEmpty()) null else LocalHistoryLine(row.optLong("id").toString(), row.optBoolean("isMine"), body, files, row.optLong("timestamp"))
        }
        if (older == null && newer == null && lines.none { it.id == message }) return null
        return LocalMessageContext(lines, page.oldestSequence.takeIf { page.hasOlder }, page.newestSequence.takeIf { page.hasNewer })
    }
    val store = AgentTranscriptStore(ctx)
    if (store.conversation(owner)?.let(LocalMessageSearch::ordinary) != true) return null
    val before: Long?
    val after: Long?
    val entries = when {
        older != null -> store.page(owner, older, 24).let { before = it.nextBeforeSequence; after = null; it.entries }
        newer != null -> store.entriesAfter(owner, newer, 24).let { before = null; after = it.newestSequence.takeIf { _ -> it.hasMore }; it.entries }
        else -> (store.messageSearchPage(owner, message) ?: return null).let {
            before = it.nextBeforeSequence
            after = it.newestSequence?.takeIf { seq -> store.entriesAfter(owner, seq, 1).entries.isNotEmpty() }
            it.entries
        }
    }
    val lines = entries.filter { e -> e.conversationId == owner && e.sourceConversationId.isBlank() &&
        e.role != AgentTranscriptRole.PROCESS && !AgentReplyWaitingIndicatorPolicy.isIndicator(e) &&
        !AgentSupervisedProjectControlPayload.isTranscriptControlPayload(e) }.mapNotNull { preview ->
        val row = if (preview.id == message && (preview.textChunkCount > 0 || preview.richOutputChunkCount > 0))
            store.fullEntry(message)?.takeIf { it.conversationId == owner && it.sourceConversationId.isBlank() } ?: return@mapNotNull null else preview
        val files = AgentRichContentCodec.decode(row.richOutputJson).filter { it.type in setOf(AgentRichBlockType.FILE,
            AgentRichBlockType.IMAGE, AgentRichBlockType.AUDIO, AgentRichBlockType.VIDEO) }.map { it.title }.filter(String::isNotBlank)
        LocalHistoryLine(row.id, row.role == AgentTranscriptRole.USER, row.text, files, row.timestampMillis)
    }
    if (older == null && newer == null && lines.none { it.id == message }) return null
    return LocalMessageContext(lines, before, after)
}
