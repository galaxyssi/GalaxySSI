package com.galaxyssi.chat

/** Indexed freshness check; authenticates source bodies only when a projection actually reads them. */
internal class KnowledgeSourceExport(private val storage: AgentKnowledgeDatabase,
    reference: AgentKnowledgeSourceReference) {
    private val selection = KnowledgeSourceSelection(storage, reference)
    val revision: String = storage.access(selection::revision)

    fun snapshot(): KnowledgeSourceSnapshot = storage.sourceSnapshot(selection, revision)

    fun scratch() = storage.exportScratch()
    fun forEachOrdered(scratch: KnowledgeEncryptedScratch, visit: (AgentKnowledgeItem) -> Unit) = snapshot().use { view ->
        val order = KnowledgeExternalOrder(scratch)
        view.items().forEach { order.add(KnowledgeOrderKey(it.chunkIndex, it.id)) }
        val file = order.finish()
        try {
            KnowledgeOrderRun.Reader(scratch.input(file)).use { reader ->
                while (true) {
                    val key = reader.next() ?: break
                    val item = view.find(key.id)
                    check(item.chunkIndex == key.chunk) { "Source snapshot chunk order mismatch" }
                    visit(item)
                }
            }
        } finally { scratch.remove(file) }
    }

    // Explicit small-caller adapter. Production projection uses forEachOrdered instead.
    fun items(): List<AgentKnowledgeItem> = snapshot().use { view ->
        view.items().toList().sortedWith(compareBy(AgentKnowledgeItem::chunkIndex, AgentKnowledgeItem::id))
    }
}
