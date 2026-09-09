package com.galaxyssi.chat

import android.content.Context
import java.util.Locale
import java.util.PriorityQueue
import org.json.JSONArray

/** Durable knowledge storage with keyed FTS5 candidate retrieval and lexical reranking. */
class SQLiteAgentKnowledgeStore internal constructor(
    context: Context, private val databaseName: String, legacyName: String,
    private val publish: (List<AgentKnowledgeItem>, List<AgentKnowledgeItem>) -> Unit
) : AgentKnowledgeStore {
    constructor(context: Context) : this(context, "galaxyssi_knowledge_v2.db", "galaxyssi_agent_knowledge",
        { before, after -> GlobalConversationEventBus.publishKnowledgeMutations(context.applicationContext, before, after) })
    private val appContext = context.applicationContext
    private val storage by lazy { AgentKnowledgeDatabase.shared(appContext, databaseName, legacyName) }
    @Volatile private var semanticSearch: KnowledgeSemanticSearch? = null
    internal val semanticSearchStatus: String get() = semanticSearch?.status ?: "not_configured"
    internal fun attachSemanticEncoder(spec: KnowledgeVectorSpec, factory: () -> KnowledgeVectorEncoder, budgetBytes: Long =
        minOf(64L * 1024 * 1024, Runtime.getRuntime().maxMemory() / 8)): KnowledgeSemanticSearch =
        KnowledgeSemanticSearch(storage, spec, factory, budgetBytes).also { next ->
            synchronized(this) { semanticSearch?.close(); semanticSearch = next }
        }
    internal fun indexVectorChunks(encoder: KnowledgeVectorEncoder, maxChunks: Int = 8,
        cancelled: () -> Boolean = { false }): KnowledgeVectorBatchResult =
        KnowledgeVectorIndexer(storage.vectors(encoder.spec), encoder).runBatch(maxChunks, cancelled)

    override fun upsert(item: AgentKnowledgeItem) {
        require(item.id.isNotBlank()) { "Knowledge item has no stable ID" }
        if (item.title.isBlank() || item.content.isBlank()) return
        val next = item.copy(title = item.title.trim(), content = item.content.trim(),
            summary = item.summary.trim().ifBlank { AgentKnowledgeCodec.summarize(item.content.trim()) },
            tags = item.tags.map { it.trim().lowercase(Locale.US) }.filter(String::isNotBlank).distinct().take(24),
            allowedAgentIds = item.allowedAgentIds.map(String::trim).filter(String::isNotBlank).distinct().take(24),
            chunkIndex = item.chunkIndex.coerceAtLeast(0), chunkCount = item.chunkCount.coerceAtLeast(1))
        val previous = storage.transaction { db ->
            // Titles are labels, not identities. Same-named sources must coexist.
            val old = storage.read(db, storage.key("id", next.id))
            require(old == null || old.source == next.source) { "Knowledge ID belongs to another source" }
            // A replay must not invalidate derived vectors or publish a second mutation.
            if (old == next) return@transaction null
            storage.write(db, next)
            listOfNotNull(old)
        } ?: return
        publish(previous, listOf(next))
        KnowledgeSemanticRuntime.forStore(appContext, databaseName)?.requestIndex()
    }

    override fun replaceSource(source: String, items: List<AgentKnowledgeItem>) {
        val cleanSource = source.trim()
        val incoming = items.filter { it.source == cleanSource && it.title.isNotBlank() && it.content.isNotBlank() }
            .distinctBy { it.id }
        if (cleanSource.isBlank() || incoming.isEmpty()) return
        val changed = storage.transaction { db ->
            val keys = storage.keys(db, "source_key=?", arrayOf(storage.key("source", cleanSource)))
            val previous = keys.map { requireNotNull(storage.read(db, it)) }
            val policy = previous.minByOrNull { it.updatedAtMillis }
            val next = incoming.map { item -> item.copy(
                summary = item.summary.trim().ifBlank { AgentKnowledgeCodec.summarize(item.content) },
                cloudAccess = policy?.cloudAccess ?: item.cloudAccess,
                agentAccess = policy?.agentAccess ?: item.agentAccess,
                allowedAgentIds = policy?.allowedAgentIds ?: item.allowedAgentIds) }
            // IDs cannot silently replace content belonging to another source.
            next.forEach { item -> storage.read(db, storage.key("id", item.id))?.let {
                require(it.source == cleanSource) { "Knowledge ID belongs to another source" }
            } }
            keys.forEach { db.delete("knowledge_items", "item_key=?", arrayOf(it)) }
            next.forEach { storage.write(db, it) }
            previous to next
        }
        publish(changed.first, changed.second)
        KnowledgeSemanticRuntime.forStore(appContext, databaseName)?.requestIndex()
    }

    override fun list(limit: Int): List<AgentKnowledgeItem> = storage.access { db ->
        storage.keys(db, limit = limit).map { requireNotNull(storage.read(db, it)) }
    }
    override fun findByIds(ids: Set<String>): List<AgentKnowledgeItem> = storage.access { db ->
        ids.mapNotNull { storage.read(db, storage.key("id", it)) }
    }
    override fun stats(): AgentKnowledgeStats = storage.access(storage::stats)
    override fun querySnapshot(query: String, limit: Int): AgentKnowledgeQuerySnapshot =
        AgentKnowledgeQuerySnapshot(search(query, limit), stats())
    fun exportJson(): JSONArray = storage.access { db ->
        JSONArray().also { array -> storage.scan(db).forEach { array.put(AgentKnowledgeCodec.encodeItem(it)) } }
    }
    fun replaceAllJson(array: JSONArray) {
        val changed = storage.transaction { db ->
            val previous = storage.scan(db).toList()
            db.delete("knowledge_items", null, null)
            val ids = hashSetOf<String>()
            val next = buildList {
                for (index in 0 until array.length()) {
                    val json = array.getJSONObject(index)
                    require(json.optString("id").isNotBlank()) { "Knowledge backup has no stable ID" }
                    val item = requireNotNull(AgentKnowledgeCodec.decodeItem(json)) { "Invalid knowledge backup item" }
                    require(ids.add(item.id)) { "Duplicate knowledge backup ID" }
                    storage.write(db, item)
                    add(item)
                }
            }
            previous to next
        }
        publish(changed.first, changed.second)
        KnowledgeSemanticRuntime.forStore(appContext, databaseName)?.requestIndex()
    }
    override fun search(query: String, limit: Int): List<AgentKnowledgeItem> = searchRanked(query, limit).map { it.item }
    override fun searchRanked(query: String, limit: Int): List<AgentKnowledgeHit> {
        if (query.isBlank() || limit <= 0) return searchLexical(query, limit)
        val semantic = semanticSearch ?: KnowledgeSemanticRuntime.forStore(appContext, databaseName)?.searchSession()
        return semantic?.search(query, limit.coerceAtMost(24)) { searchLexical(query, 24) }
            ?: searchLexical(query, limit)
    }
    private fun searchLexical(query: String, limit: Int): List<AgentKnowledgeHit> = storage.access { db ->
        val size = limit.coerceAtLeast(0)
        if (size == 0) return@access emptyList()
        if (query.isBlank()) return@access storage.keys(db, limit = size).map {
            val item = requireNotNull(storage.read(db, it))
            AgentKnowledgeHit(item, 0.0, AgentKnowledgeCodec.excerpt(item.content, emptyList()), emptyList())
        }
        val clean = AgentKnowledgeTextAnalyzer.normalize(query).trim()
        val tokens = AgentKnowledgeTextAnalyzer.tokens(clean)
        val trigrams = AgentKnowledgeTextAnalyzer.trigrams(clean)
        val order = compareBy<AgentKnowledgeHit> { it.score }.thenBy { it.item.updatedAtMillis }.thenBy { it.item.id }
        val capacity = size.coerceAtMost(24)
        val best = PriorityQueue(capacity, order)
        storage.candidates(db, clean, 256).forEach { item ->
            val score = AgentKnowledgeCodec.semanticScore(item, clean, tokens, trigrams)
            if (score >= 1.2) {
                val text = "${item.title} ${item.summary} ${item.tags.joinToString(" ")} ${item.content}".lowercase(Locale.US)
                val matched = tokens.filter(text::contains).distinct()
                val hit = AgentKnowledgeHit(item, score, AgentKnowledgeCodec.excerpt(item.content, matched), matched)
                if (best.size < capacity) best.add(hit) else if (order.compare(hit, best.peek()) > 0) {
                    best.poll(); best.add(hit)
                }
            }
        }
        best.toList().sortedWith(order.reversed())
    }

    override fun updateAccess(itemIds: Set<String>, cloudAccess: AgentKnowledgeCloudAccess,
        agentAccess: AgentKnowledgeAgentAccess, allowedAgentIds: List<String>): Int {
        val agents = allowedAgentIds.map(String::trim).filter(String::isNotBlank).distinct().take(24)
        val changed = storage.transaction { db ->
            val previous = itemIds.mapNotNull { storage.read(db, storage.key("id", it)) }
            val next = previous.map { it.copy(cloudAccess = cloudAccess, agentAccess = agentAccess,
                allowedAgentIds = if (agentAccess == AgentKnowledgeAgentAccess.SELECTED_AGENTS) agents else emptyList(),
                updatedAtMillis = System.currentTimeMillis()) }
            next.forEach { storage.write(db, it) }
            previous to next
        }
        if (changed.first.isNotEmpty()) publish(changed.first, changed.second)
        if (changed.first.isNotEmpty()) KnowledgeSemanticRuntime.forStore(appContext, databaseName)?.requestIndex()
        return changed.first.size
    }

    override fun delete(query: String): Int {
        if (query.isBlank()) return 0
        val clean = AgentKnowledgeTextAnalyzer.normalize(query).trim()
        val tokens = AgentKnowledgeTextAnalyzer.tokens(clean)
        val trigrams = AgentKnowledgeTextAnalyzer.trigrams(clean)
        val removed = storage.transaction { db ->
            val matches = storage.scan(db).filter {
                AgentKnowledgeCodec.semanticScore(it, clean, tokens, trigrams) >= 1.2
            }.toList()
            matches.forEach { db.delete("knowledge_items", "item_key=?", arrayOf(storage.key("id", it.id))) }
            matches
        }
        if (removed.isNotEmpty()) publish(removed, emptyList())
        if (removed.isNotEmpty()) KnowledgeSemanticRuntime.forStore(appContext, databaseName)?.requestIndex()
        return removed.size
    }
    internal fun close() {
        semanticSearch?.close(); semanticSearch = null
        AgentKnowledgeDatabase.release(appContext, databaseName)
    }
}
