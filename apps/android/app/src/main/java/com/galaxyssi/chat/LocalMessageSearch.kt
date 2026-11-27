package com.galaxyssi.chat

import android.content.Context

internal data class LocalMessageHit(val kind: ConversationHubItemKind, val owner: String, val ownerTitle: String,
    val message: String, val sequence: Long?, val time: Long, val snippet: String, val filename: Boolean)

internal object LocalMessageSearch {
    private const val PAGE = 32
    private val media = setOf(AgentRichBlockType.FILE, AgentRichBlockType.IMAGE, AgentRichBlockType.AUDIO, AgentRichBlockType.VIDEO)

    fun ordinary(c: AgentConversation) = !c.privateMode && !c.trackingPaused && c.globalTopicKey.isBlank() &&
        c.mergedIntoConversationId.isBlank()

    fun visiblePeer(context: Context, id: String, raw: org.json.JSONObject): Boolean =
        id != CONTACT_SYSTEM.id && id != CONTACT_HERMES.id && ConversationHubContactHistoryPolicy.includes(raw) &&
            (DesktopPairingLifecycle.isHistoryOnly(raw) || AppStore.isDirectPeerContact(context, id))

    fun excerpt(text: String, query: String): String? {
        if (query.isBlank()) return null
        val i = text.indexOf(query, ignoreCase = true)
        if (i < 0) return null
        val start = (i - 14).coerceAtLeast(0)
        val end = (i + query.length + 58).coerceAtMost(text.length)
        return (if (start > 0) "…" else "") + text.substring(start, end).replace('\n', ' ').replace('\r', ' ').trim() +
            (if (end < text.length) "…" else "")
    }

    fun inChunks(chunks: Sequence<String>, query: String): String? {
        var tail = ""
        for (chunk in chunks) {
            val window = tail + chunk
            excerpt(window, query)?.let { return it }
            tail = window.takeLast(query.length + 38)
        }
        return null
    }

    /** Read encrypted storage on demand. The iterator and snippets belong only to the open search. */
    fun scan(context: Context, rawQuery: String, archived: Boolean, cancelled: () -> Boolean): Sequence<LocalMessageHit> = sequence {
        val query = rawQuery.trim()
        if (query.isEmpty() || query.length > 256 || cancelled()) return@sequence
        val store = AgentTranscriptStore(context)
        val status = if (archived) AgentConversationStatus.ARCHIVED else AgentConversationStatus.ACTIVE
        var cursor: AgentConversationPageCursor? = null
        do {
            if (cancelled()) return@sequence
            val conversations = store.conversationPage(status, cursor, PAGE)
            for (c in conversations.items) {
                if (!ordinary(c)) continue
                var before: Long? = null
                do {
                    if (cancelled()) return@sequence
                    val page = store.page(c.id, before, PAGE)
                    for (e in page.entries.asReversed()) {
                        if (cancelled()) return@sequence
                        if (e.conversationId != c.id || e.role == AgentTranscriptRole.PROCESS || e.sourceConversationId.isNotBlank() ||
                            AgentReplyWaitingIndicatorPolicy.isIndicator(e) || AgentSupervisedProjectControlPayload.isTranscriptControlPayload(e)) continue
                        val body = if (e.textChunkCount == 0) excerpt(e.text, query) else inChunks(sequence {
                            var offset = 0
                            while (!cancelled()) {
                                val p = store.textChunkPage(e.id, offset, 2) ?: break
                                yieldAll(p.chunks)
                                if (p.done || p.nextOffset <= offset) break
                                offset = p.nextOffset
                            }
                        }, query)
                        if (cancelled()) return@sequence
                        val rich = if (body == null && e.richOutputChunkCount > 0) store.fullEntry(e.id)?.richOutputJson.orEmpty()
                            else e.richOutputJson
                        val match = body ?: AgentRichContentCodec.decode(rich).asSequence()
                            .filter { it.type in media }.mapNotNull { excerpt(it.title, query) }.firstOrNull() ?: continue
                        yield(LocalMessageHit(ConversationHubItemKind.AGENT, c.id, c.title, e.id, null, e.timestampMillis, match, body == null))
                    }
                    before = page.nextBeforeSequence
                } while (before != null)
            }
            cursor = conversations.nextCursor
        } while (cursor != null)
        if (cancelled()) return@sequence
        for (contact in ChatHistoryStore.contactSummaries(context)) {
            val id = contact.contactId
            if (cancelled()) return@sequence
            if (id == CONTACT_SYSTEM.id || id == CONTACT_HERMES.id) continue
            val raw = AppStore.contactById(context, id) ?: continue
            if (!visiblePeer(context, id, raw) || DesktopPairingLifecycle.isHistoryOnly(raw) != archived) continue
            val title = raw.optString("name").ifBlank { id }
            var before: Long? = null
            do {
                if (cancelled()) return@sequence
                val page = ChatHistoryStore.page(context, id, before, PAGE)
                for (msg in page.messages.asReversed()) {
                    if (cancelled()) return@sequence
                    val seq = msg.optLong(ChatHistoryDatabase.HISTORY_SEQUENCE)
                    if (msg.optBoolean("isSystem") || msg.optLong("id") <= 0 || seq <= 0) continue
                    val body = excerpt(PeerChatPresentation.storedContent(msg.optString("content")), query)
                    val match = body ?: PeerChatAttachment.decode(msg.optJSONArray("attachments")).asSequence()
                        .mapNotNull { excerpt(it.name, query) }.firstOrNull() ?: continue
                    yield(LocalMessageHit(ConversationHubItemKind.CONTACT, id, title, msg.optLong("id").toString(), seq,
                        msg.optLong("timestamp"), match, body == null))
                }
                before = page.nextBeforeSequence
            } while (before != null)
        }
    }
}
