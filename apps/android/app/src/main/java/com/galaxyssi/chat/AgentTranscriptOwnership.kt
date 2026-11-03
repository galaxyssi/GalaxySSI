package com.galaxyssi.chat

/** A projection never acquires ownership merely because its screen is currently selected. */
internal object AgentTranscriptOwnership {
    fun accepts(conversationId: String, owners: List<String?>, canonical: (String) -> String?): Boolean {
        val destination = canonical(conversationId) ?: return false
        return owners.filterNotNull().filter(String::isNotBlank).all { canonical(it) == destination }
    }

    fun filter(entries: List<AgentTranscriptEntry>, owner: (String) -> String?,
               canonical: (String) -> String?): List<AgentTranscriptEntry> {
        val owners = mutableMapOf<String, String?>()
        val conversations = mutableMapOf<String, String?>()
        return entries.filter { entry ->
            entry.turnId.isBlank() || accepts(entry.conversationId,
                listOf(owners.getOrPut(entry.turnId) { owner(entry.turnId) })) { id ->
                    conversations.getOrPut(id) { canonical(id) }
                }
        }
    }
}
