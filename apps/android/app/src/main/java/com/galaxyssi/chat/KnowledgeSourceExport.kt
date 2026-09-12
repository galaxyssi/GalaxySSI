package com.galaxyssi.chat

/** Indexed freshness check; authenticates source bodies only when a projection actually reads them. */
internal class KnowledgeSourceExport(private val storage: AgentKnowledgeDatabase,
    reference: AgentKnowledgeSourceReference) {
    private val selection = KnowledgeSourceSelection(storage, reference)
    val revision: String = storage.access(selection::revision)

    fun snapshot(): KnowledgeSourceSnapshot = storage.sourceSnapshot(selection, revision)

    // Existing Markdown rendering still needs a List. Its separate snapshot no longer locks live writes.
    fun items(): List<AgentKnowledgeItem> = snapshot().use { view ->
        view.items().toList().sortedWith(compareBy(AgentKnowledgeItem::chunkIndex, AgentKnowledgeItem::id))
    }
}
