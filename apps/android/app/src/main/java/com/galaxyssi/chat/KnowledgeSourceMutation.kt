package com.galaxyssi.chat

/** Synchronous post-commit view. Its encrypted staging belongs to the replacement call. */
internal class KnowledgeSourceMutation(private val storage: AgentKnowledgeDatabase,
    private val staging: KnowledgeBackupStaging, private val policy: KnowledgeSourcePolicy?) {
    fun normalize(item: AgentKnowledgeItem) = item.copy(
        summary = item.summary.trim().ifBlank { AgentKnowledgeCodec.summarize(item.content) },
        cloudAccess = policy?.cloud ?: item.cloudAccess, agentAccess = policy?.agent ?: item.agentAccess,
        allowedAgentIds = policy?.allowed ?: item.allowedAgentIds)

    fun visit(previous: Boolean, consume: (AgentKnowledgeItem) -> Unit) = storage.exportScratch().use { scratch ->
        val order = KnowledgeExternalOrder(scratch)
        val items = if (previous) staging.previous() else staging.incoming()
        for (item in items) order.add(KnowledgeOrderKey(item.chunkIndex, item.id))
        val file = order.finish()
        KnowledgeOrderRun.Reader(scratch.input(file)).use { reader ->
            while (true) {
                val key = reader.next() ?: break
                val item = requireNotNull(staging.item(key.id, previous))
                check(item.chunkIndex == key.chunk)
                consume(if (previous) item else normalize(item))
            }
        }
    }

    // Explicit adapter for internal small-fixture callbacks. The production publisher uses visit.
    fun items(previous: Boolean): List<AgentKnowledgeItem> = buildList { visit(previous, ::add) }
}
