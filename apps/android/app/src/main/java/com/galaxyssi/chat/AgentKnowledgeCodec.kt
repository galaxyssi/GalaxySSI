package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale
import java.util.UUID

internal object AgentKnowledgeCodec {
    fun semanticScore(
        item: AgentKnowledgeItem,
        query: String,
        queryTokens: List<String>,
        queryTrigrams: Set<String>
    ): Double {
        val title = AgentKnowledgeTextAnalyzer.normalize(item.title)
        val summary = AgentKnowledgeTextAnalyzer.normalize(item.summary)
        val content = AgentKnowledgeTextAnalyzer.normalize(item.content)
        val tags = AgentKnowledgeTextAnalyzer.normalize(item.tags.joinToString(" "))
        val phrase = AgentKnowledgeTextAnalyzer.normalize(query).replace(Regex("\\s+"), " ").trim()
        var score = 0.0
        if (title.contains(phrase)) score += 14.0
        if (summary.contains(phrase)) score += 10.0
        if (content.contains(phrase)) score += 7.0
        queryTokens.forEach { token ->
            if (title.contains(token)) score += 4.5
            if (tags.contains(token)) score += 3.5
            if (summary.contains(token)) score += 2.5
            if (content.contains(token)) score += 1.2
        }
        if (queryTokens.isNotEmpty()) {
            val matched = queryTokens.count { item.searchText().contains(it) }
            score += matched.toDouble() / queryTokens.size * 6.0
        }
        val itemTrigrams = AgentKnowledgeTextAnalyzer.trigrams("${item.title} ${item.summary} ${item.content.take(1_200)}")
        if (queryTrigrams.isNotEmpty() && itemTrigrams.isNotEmpty()) {
            val intersection = queryTrigrams.count { it in itemTrigrams }
            val union = queryTrigrams.size + itemTrigrams.size - intersection
            if (union > 0) score += intersection.toDouble() / union * 9.0
        }
        return score
    }

    private fun AgentKnowledgeItem.searchText(): String =
        AgentKnowledgeTextAnalyzer.normalize("$title $summary ${tags.joinToString(" ")} $content")

    fun summarize(content: String): String = content
        .replace(Regex("\\s+"), " ")
        .trim()
        .take(MAX_SUMMARY_CHARACTERS)

    fun excerpt(content: String, terms: List<String>): String {
        val normalized = content.replace(Regex("\\s+"), " ").trim()
        if (normalized.isBlank()) return ""
        val lower = normalized.lowercase(Locale.US)
        val matchIndex = terms.map { lower.indexOf(it) }.filter { it >= 0 }.minOrNull() ?: 0
        val start = (matchIndex - EXCERPT_CONTEXT_BEFORE).coerceAtLeast(0)
        val end = (matchIndex + MAX_EXCERPT_CHARACTERS).coerceAtMost(normalized.length)
        return buildString {
            if (start > 0) append("...")
            append(normalized.substring(start, end))
            if (end < normalized.length) append("...")
        }
    }

    fun encodeItem(item: AgentKnowledgeItem): JSONObject = JSONObject()
        .put("id", item.id)
        .put("kind", item.kind.name)
        .put("title", item.title)
        .put("content", item.content)
        .put("source", item.source)
        .put("tags", JSONArray().also { array -> item.tags.forEach { array.put(it) } })
        .put("summary", item.summary)
        .put("cloud_access", item.cloudAccess.name)
        .put("agent_access", item.agentAccess.name)
        .put("allowed_agent_ids", JSONArray().also { array -> item.allowedAgentIds.forEach { array.put(it) } })
        .put("chunk_index", item.chunkIndex)
        .put("chunk_count", item.chunkCount)
        .put("updated_at_millis", item.updatedAtMillis)

    fun decodeItem(json: JSONObject): AgentKnowledgeItem? {
        val title = json.optString("title")
        val content = json.optString("content")
        if (title.isBlank() || content.isBlank()) return null
        return AgentKnowledgeItem(
            id = json.optString("id").ifBlank { UUID.randomUUID().toString() },
            kind = enumOrDefault(json.optString("kind"), AgentKnowledgeKind.NOTE),
            title = title,
            content = content,
            source = json.optString("source"),
            tags = decodeStringList(json.optJSONArray("tags")),
            summary = json.optString("summary").ifBlank { summarize(content) },
            cloudAccess = enumOrDefault(json.optString("cloud_access"), AgentKnowledgeCloudAccess.DENY),
            agentAccess = enumOrDefault(json.optString("agent_access"), AgentKnowledgeAgentAccess.LOCAL_ONLY),
            allowedAgentIds = decodeStringList(json.optJSONArray("allowed_agent_ids")),
            chunkIndex = json.optInt("chunk_index", 0).coerceAtLeast(0),
            chunkCount = json.optInt("chunk_count", 1).coerceAtLeast(1),
            updatedAtMillis = json.optLong("updated_at_millis", System.currentTimeMillis())
        )
    }

    private fun decodeStringList(array: JSONArray?): List<String> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                array.optString(index).takeIf { it.isNotBlank() }?.let { add(it) }
            }
        }
    }

    private inline fun <reified T : Enum<T>> enumOrDefault(value: String, default: T): T =
        runCatching { enumValueOf<T>(value) }.getOrElse { default }

    private const val MAX_SUMMARY_CHARACTERS = 480
    private const val MAX_EXCERPT_CHARACTERS = 420
    private const val EXCERPT_CONTEXT_BEFORE = 120
}
