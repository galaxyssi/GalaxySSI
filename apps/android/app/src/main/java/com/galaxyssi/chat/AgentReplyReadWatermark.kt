package com.galaxyssi.chat

import java.util.concurrent.ConcurrentHashMap

/** Opening the latest page acknowledges older replies even when process rows push them out of the page. */
internal object AgentReplyReadWatermark {
    private val pending = ConcurrentHashMap.newKeySet<String>()

    fun schedule(activity: MainActivity) {
        val id = activity.agentRenderedConversationId
        if (id.isBlank() || id != activity.agentTranscriptWindow.conversationId ||
            activity.renderedAgentTranscriptSourceEntries.isEmpty() ||
            activity.agentOutputList.canScrollVertically(1)) return
        val sequence = activity.agentTranscriptWindow.newestSequence ?: return
        val tokens = AgentReplyUnreadStore.tokens(activity, id)
        if (tokens.isEmpty()) return
        val key = "$id:$sequence"
        if (!pending.add(key)) return
        activity.agentTranscriptContentExecutor.execute {
            var changed = false
            try {
                changed = activity.agentTranscriptStore.readRepliesThrough(id, sequence, tokens) > 0
            } catch (error: Exception) {
                android.util.Log.w("GalaxySSIUnread", "Read watermark deferred: ${error.javaClass.simpleName}")
            } finally {
                pending.remove(key)
                if (changed) activity.runOnUiThread {
                    if (!activity.isFinishing && !activity.isDestroyed) activity.refreshReplyUnreadDot()
                }
            }
        }
    }
}
