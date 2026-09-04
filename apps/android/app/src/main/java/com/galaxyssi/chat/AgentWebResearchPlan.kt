package com.galaxyssi.chat

import java.net.URI
import java.util.Locale

internal data class AgentWebResearchQueryPlanItem(
    val query: String,
    val purpose: String = "",
    val verticals: Set<AgentWebIntelligenceVertical> = emptySet(),
    val categories: Set<String> = emptySet(),
    val engines: List<String> = emptyList()
) {
    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "query" to query,
        "purpose" to purpose,
        "verticals" to verticals.map(AgentWebIntelligenceVertical::wireValue).sorted(),
        "categories" to categories.sorted(),
        "engines" to engines
    )
}

internal data class AgentWebResearchQueryCoverage(
    val item: AgentWebResearchQueryPlanItem,
    val candidateUrls: Set<String>,
    val retrievedUrls: Set<String>,
    val sourceIds: Set<String>,
    val completedSources: Int,
    val failedSources: Int
) {
    val status: String
        get() = when {
            retrievedUrls.isNotEmpty() -> "covered"
            candidateUrls.isNotEmpty() -> "discovered_only"
            else -> "unresolved"
        }

    fun publicValue(): AgentNativeJsonObject = linkedMapOf(
        "query" to item.query,
        "purpose" to item.purpose,
        "status" to status,
        "candidate_count" to candidateUrls.size,
        "retrieved_document_count" to retrievedUrls.size,
        "independent_domain_count" to retrievedUrls.mapNotNull(::webResearchHost).toSet().size,
        "source_ids" to sourceIds.sorted(),
        "sources_completed" to completedSources,
        "sources_failed" to failedSources
    )
}

/** Decodes only the research plan chosen by the current model; it never expands query semantics. */
internal object AgentWebResearchPlanCodec {
    const val MAX_ITEMS = 32
    const val MAX_QUERY_CHARACTERS = 4_096
    const val MAX_PURPOSE_CHARACTERS = 512
    const val MAX_CATEGORIES = 32
    const val MAX_ENGINES = 32

    fun decode(
        primaryQuery: String,
        rawPlan: Any?
    ): List<AgentWebResearchQueryPlanItem> {
        val explicit = (rawPlan as? Iterable<*>)
            ?.asSequence()
            ?.take(MAX_ITEMS)
            ?.mapNotNull(::decodeItem)
            ?.distinctBy { normalizeQueryKey(it.query) }
            ?.toList()
            .orEmpty()
        if (explicit.isNotEmpty()) return explicit
        return listOf(AgentWebResearchQueryPlanItem(primaryQuery.take(MAX_QUERY_CHARACTERS)))
    }

    private fun decodeItem(raw: Any?): AgentWebResearchQueryPlanItem? {
        if (raw is String) {
            return raw.cleanWebResearchText(MAX_QUERY_CHARACTERS)
                .takeIf(String::isNotBlank)
                ?.let(::AgentWebResearchQueryPlanItem)
        }
        val value = raw as? Map<*, *> ?: return null
        val query = value["query"]?.toString().orEmpty()
            .cleanWebResearchText(MAX_QUERY_CHARACTERS)
        if (query.isBlank()) return null
        val verticals = value.stringValues("verticals", AgentWebIntelligenceVertical.entries.size)
            .mapNotNull { requested ->
                AgentWebIntelligenceVertical.entries.firstOrNull {
                    it.wireValue.equals(requested, ignoreCase = true)
                }
            }
            .toSet()
        val categories = value.stringValues("categories", MAX_CATEGORIES)
            .mapNotNull(::normalizeAgentWebCategoryTag)
            .toSet()
        val engines = value.stringValues("engines", MAX_ENGINES)
            .map { it.trim().lowercase(Locale.ROOT) }
            .filter { ENGINE_ID.matches(it) }
            .distinct()
        return AgentWebResearchQueryPlanItem(
            query = query,
            purpose = value["purpose"]?.toString().orEmpty()
                .cleanWebResearchText(MAX_PURPOSE_CHARACTERS),
            verticals = verticals,
            categories = categories,
            engines = engines
        )
    }

    private fun Map<*, *>.stringValues(key: String, maximum: Int): List<String> =
        (get(key) as? Iterable<*>)
            ?.asSequence()
            ?.mapNotNull { it?.toString() }
            ?.take(maximum)
            ?.toList()
            .orEmpty()

    private fun normalizeQueryKey(value: String): String = value
        .lowercase(Locale.ROOT)
        .replace(Regex("\\s+"), " ")
        .trim()

    private val ENGINE_ID = Regex("[a-z0-9][a-z0-9_\\-]{0,63}")
}

internal fun normalizeAgentWebCategoryTag(value: String): String? {
    val normalized = value.cleanWebResearchText(64).lowercase(Locale.ROOT)
    return normalized.takeIf { tag ->
        tag.isNotBlank() && tag.any(Char::isLetterOrDigit)
    }
}

internal fun roundRobinWebResearchResults(
    groups: List<List<AgentNativeJsonObject>>
): LinkedHashMap<String, AgentNativeJsonObject> {
    val merged = linkedMapOf<String, AgentNativeJsonObject>()
    val maximum = groups.maxOfOrNull { it.size } ?: 0
    for (index in 0 until maximum) {
        groups.forEach { group ->
            val item = group.getOrNull(index) ?: return@forEach
            val url = item["url"]?.toString().orEmpty()
            if (url.isNotBlank()) merged.putIfAbsent(url, item)
        }
    }
    return merged
}

private fun String.cleanWebResearchText(maximum: Int): String =
    replace(Regex("\\s+"), " ").trim().take(maximum)

private fun webResearchHost(value: String): String? = runCatching {
    URI(value).host?.lowercase(Locale.ROOT)?.removePrefix("www.")
}.getOrNull()?.takeIf(String::isNotBlank)
