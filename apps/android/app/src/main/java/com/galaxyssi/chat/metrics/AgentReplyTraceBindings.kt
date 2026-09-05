package com.galaxyssi.chat.metrics

/** Diagnostic-only aliases; Run/turn/task identities and routing are never rewritten. */
internal class AgentReplyTraceBindings(private val capacity: Int = AgentLatencyContract.EVENT_LIMIT) {
    private val bindings = LinkedHashMap<Triple<String, String, String>, String>()

    init { require(capacity > 0) }

    @Synchronized
    fun bind(conversationId: String, turnId: String, entryTaskId: String, transportTaskId: String) {
        if (transportTaskId.isBlank()) return
        val key = key(conversationId, turnId, entryTaskId) ?: return
        bindings.remove(key)
        bindings[key] = transportTaskId
        if (bindings.size > capacity) bindings.remove(bindings.keys.first())
    }

    @Synchronized
    fun resolve(conversationId: String, turnId: String, entryTaskId: String): String =
        key(conversationId, turnId, entryTaskId)?.let(bindings::get) ?: entryTaskId

    private fun key(conversationId: String, turnId: String, taskId: String): Triple<String, String, String>? {
        if (conversationId.isBlank() || turnId.isBlank() || taskId.isBlank()) return null
        return Triple(AgentLatencyContract.opaqueId(conversationId), AgentLatencyContract.opaqueId(turnId),
            AgentLatencyContract.opaqueId(taskId))
    }
}
