package com.galaxyssi.chat

import org.json.JSONObject

internal data class ChatHistoryViewportPage(
    val messages: List<JSONObject>,
    val hasOlder: Boolean,
    val hasNewer: Boolean,
    val oldestSequence: Long?,
    val newestSequence: Long?
)

internal fun ChatHistoryDatabase.viewportPage(
    contactId: String,
    anchorSequence: Long?,
    pageSize: Int
): ChatHistoryViewportPage = synchronized(this) {
    if (anchorSequence == null || anchorSequence <= 0L) {
        val page = page(contactId, pageSize = pageSize)
        ChatHistoryViewportPage(page.messages, page.hasMore, false, page.oldestSequence, page.newestSequence)
    } else {
        // Two indexed range queries keep a historical viewport contiguous and bounded.
        val before = page(contactId, anchorSequence, (pageSize / 2).coerceAtLeast(1))
        val after = pageAfter(contactId, anchorSequence - 1L, (pageSize - before.messages.size).coerceAtLeast(1))
        ChatHistoryViewportPage(before.messages + after.messages, before.hasMore, after.hasMore,
            before.oldestSequence ?: after.oldestSequence, after.newestSequence ?: before.newestSequence)
    }
}
