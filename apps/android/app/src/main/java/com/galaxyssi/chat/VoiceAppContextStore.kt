package com.galaxyssi.chat

/** Short-lived identity anchors only; no transcripts, article bodies or contact names. */
internal class VoiceAppContextStore(private val now: () -> Long = { System.nanoTime() / 1_000_000 }) {
    private data class Anchor(val expiresAt: Long, val value: AgentNativeJsonObject)
    private val pending = linkedMapOf<String, Anchor>()
    private val turns = linkedMapOf<Pair<String, String>, Anchor>()

    @Synchronized fun capture(traceId: String, context: AgentNativeJsonObject) {
        if (traceId.isBlank() || context["voice_active"] != true) return
        pending[traceId] = Anchor(now() + 600_000, context.filterKeys { it in FIELDS }.toMap())
        prune(pending)
    }

    @Synchronized fun bind(traceId: String, conversationId: String, turnId: String) {
        prune(pending)
        val anchor = pending.remove(traceId) ?: return
        if (turnId.isNotBlank() && conversationId.isNotBlank() && anchor.value["conversation_id"] == conversationId) {
            turns[conversationId to turnId] = anchor
            prune(turns)
        }
    }

    @Synchronized fun get(conversationId: String, turnId: String): AgentNativeJsonObject? {
        prune(turns)
        return turns[conversationId to turnId]?.value
    }

    @Synchronized fun clear() { pending.clear(); turns.clear() }

    private fun <K> prune(values: LinkedHashMap<K, Anchor>) {
        val time = now()
        values.entries.removeAll { it.value.expiresAt <= time }
        while (values.size > 64) values.remove(values.keys.first())
    }

    companion object {
        private val FIELDS = setOf("voice_active", "conversation_id", "contact_id", "article_id", "surface", "playback_state")
    }
}
