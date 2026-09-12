package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.io.Closeable
import java.util.UUID

internal class KnowledgeSourceReplaceFixture : Closeable {
    val context = InstrumentationRegistry.getInstrumentation().targetContext
    val name = "test-knowledge-source-replace-${UUID.randomUUID()}.db"
    private val legacy = "legacy-$name"
    val db get() = AgentKnowledgeDatabase.shared(context, name, legacy)
    var events = emptyList<GlobalConversationEvent>()
    var visits = 0
    var observer: ((KnowledgeSourceMutation) -> Unit)? = null
    var store = open(); private set
    private fun open() = SQLiteAgentKnowledgeStore(context, name, legacy, publishSource = { change ->
        visits++
        events = GlobalPersistentContextObservationExtractor.knowledgeSourceMutation(change, 1234)
        observer?.invoke(change)
    }) { _, _ -> }
    fun reopen() { store.close(); store = open() }
    fun item(i: Int, source: String = "\u6765\u6e90") = AgentKnowledgeItem(id = "replace-$i",
        kind = AgentKnowledgeKind.DOCUMENT, title = "\u6d4b\u8bd5 $i", content = "\u52a0\u5bc6\u6b63\u6587 $i",
        summary = "\u6458\u8981 $i", source = source, chunkIndex = i, chunkCount = 200, updatedAtMillis = i.toLong())
    fun items() = store.list(500).sortedBy { it.id }
    override fun close() { store.close(); println("KNOWLEDGE_SOURCE_REPLACE_FIXTURE $name") }
}
