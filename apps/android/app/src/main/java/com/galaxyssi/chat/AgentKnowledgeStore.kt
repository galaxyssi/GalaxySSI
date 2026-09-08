package com.galaxyssi.chat

import android.content.Context
import java.util.Locale
import java.util.UUID

data class AgentKnowledgeItem(
    val id: String = UUID.randomUUID().toString(),
    val kind: AgentKnowledgeKind,
    val title: String,
    val content: String,
    val source: String = "",
    val tags: List<String> = emptyList(),
    val summary: String = "",
    val cloudAccess: AgentKnowledgeCloudAccess = AgentKnowledgeCloudAccess.DENY,
    val agentAccess: AgentKnowledgeAgentAccess = AgentKnowledgeAgentAccess.LOCAL_ONLY,
    val allowedAgentIds: List<String> = emptyList(),
    val chunkIndex: Int = 0,
    val chunkCount: Int = 1,
    val updatedAtMillis: Long = System.currentTimeMillis()
)

data class AgentKnowledgeHit(
    val item: AgentKnowledgeItem,
    val score: Double,
    val excerpt: String,
    val matchedTerms: List<String>
)

data class AgentKnowledgeStats(
    val itemCount: Int = 0,
    val sourceCount: Int = 0,
    val lastUpdatedAtMillis: Long = 0L
)

data class AgentKnowledgeQuerySnapshot(
    val items: List<AgentKnowledgeItem> = emptyList(),
    val stats: AgentKnowledgeStats = AgentKnowledgeStats()
)

enum class AgentKnowledgeKind {
    NOTE,
    DOCUMENT,
    SCREEN,
    CHAT,
    TASK
}

enum class AgentKnowledgeCloudAccess {
    DENY,
    SUMMARY_ONLY,
    FULL
}

enum class AgentKnowledgeAgentAccess {
    LOCAL_ONLY,
    SELECTED_AGENTS,
    ANY_PAIRED_AGENT
}

interface AgentKnowledgeStore {
    fun upsert(item: AgentKnowledgeItem)
    fun replaceSource(source: String, items: List<AgentKnowledgeItem>)
    fun search(query: String, limit: Int = 5): List<AgentKnowledgeItem>
    fun searchRanked(query: String, limit: Int = 8): List<AgentKnowledgeHit>
    fun list(limit: Int = 100): List<AgentKnowledgeItem>
    fun findByIds(ids: Set<String>): List<AgentKnowledgeItem>
    fun updateAccess(
        itemIds: Set<String>,
        cloudAccess: AgentKnowledgeCloudAccess,
        agentAccess: AgentKnowledgeAgentAccess,
        allowedAgentIds: List<String>
    ): Int
    fun delete(query: String): Int
    fun stats(): AgentKnowledgeStats
    fun querySnapshot(query: String, limit: Int = 5): AgentKnowledgeQuerySnapshot =
        AgentKnowledgeQuerySnapshot(search(query, limit), stats())
}

class SharedPreferencesAgentKnowledgeStore(context: Context) : AgentKnowledgeStore by SQLiteAgentKnowledgeStore(context)

object AgentKnowledgeTextAnalyzer {
    fun normalize(value: String): String = java.text.Normalizer.normalize(value,
        java.text.Normalizer.Form.NFKC).lowercase(Locale.US)

    fun tokens(value: String): List<String> {
        val normalized = normalize(value)
        val words = Regex("[\\p{L}\\p{N}]{2,}")
            .findAll(normalized)
            .map { it.value }
            .filter { it !in STOP_WORDS }
            .toList()
        val cjk = normalized.filter { it.isCjk() }
            .windowed(size = 2, step = 1, partialWindows = false)
        return (words + cjk).distinct().take(MAX_QUERY_TOKENS)
    }

    fun trigrams(value: String): Set<String> {
        val normalized = normalize(value).filter { it.isLetterOrDigit() }
        if (normalized.length < 3) return emptySet()
        return normalized.windowed(3).take(MAX_TRIGRAMS).toSet()
    }

    private fun Char.isCjk(): Boolean = code in 0x3400..0x9FFF

    private val STOP_WORDS = setOf("the", "and", "for", "with", "from", "this", "that", "what", "when", "where")
    private const val MAX_QUERY_TOKENS = 64
    private const val MAX_TRIGRAMS = 512
}
