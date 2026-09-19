package com.galaxyssi.chat

import org.json.JSONObject

/** Observed retrieval gaps, not a model-generated claim of truth or completeness. */
internal class CloudResearchCoverage {
    private val bodies = linkedSetOf<String>()
    private val discovered = linkedSetOf<String>()
    private val pendingWindows = linkedMapOf<String, Int>()
    private val gaps = linkedMapOf<String, String>()
    private var complexResearchObserved = false

    fun observe(root: JSONObject) {
        val pack = root.optJSONObject("evidence_pack") ?: return
        if (root.optString("operation") in setOf("research", "agent") || pack.has("research_context")) complexResearchObserved = true
        val items = pack.optJSONArray("items")
        for (i in 0 until (items?.length() ?: 0)) {
            val item = items?.optJSONObject(i) ?: continue
            val url = AgentResearchTrace.safeUrl(item.optString("url")) ?: continue
            discovered += url
            if (item.optString("evidence_level") == "retrieved_body" && item.optString("excerpt").isNotBlank()) bodies += url
            item.optJSONObject("reading_window")?.let { window ->
                if (!window.isNull("next_offset")) pendingWindows[url] = window.optInt("next_offset")
                else pendingWindows.remove(url)
            }
        }
        val coverage = pack.optJSONObject("research_context")?.optJSONArray("coverage")
        for (i in 0 until (coverage?.length() ?: 0)) {
            val item = coverage?.optJSONObject(i) ?: continue
            val query = item.optString("query").take(1024)
            if (query.isBlank()) continue
            if (item.optString("status") == "body_retrieved") gaps.remove(query)
            else gaps[query] = item.optString("subquestion").ifBlank { item.optString("purpose") }.take(512)
        }
    }

    fun readingReview(answer: String): String? {
        if (!complexResearchObserved) return null
        val unreadCitations = AgentResearchTrace.citedUrls(answer).filter { it in discovered && it !in bodies }
        if (unreadCitations.isEmpty()) return null
        return "The deep-research draft cites sources observed only as search snippets: " +
            unreadCitations.take(8).joinToString(", ") + ". Read the decisive original bodies and surrounding context " +
            "before relying on these claims; use cached sequential windows for long documents. Do not repeat discovery searches. " +
            "If access fails or a source is irrelevant, replace, qualify or omit its claim. Reconcile material contradictions " +
            "and return a thematic synthesis covering the user's subquestions, not a list of source summaries. " +
            "No retrieval receipt proves semantic correctness."
    }

    fun guidance(): String = buildString {
        append(" Body retrieval: ${bodies.size}/${discovered.size} recorded URLs; this is not claim verification.")
        if (gaps.isNotEmpty()) append(" Unresolved retrieval gaps (sample): ").append(
            gaps.entries.take(6).joinToString("; ") { "${it.value}: ${it.key}" })
        if (pendingWindows.isNotEmpty()) append(" Long bodies with more text (sample): ").append(
            pendingWindows.entries.take(6).joinToString("; ") { "${it.key} next_offset=${it.value}" })
        append(" Prioritize relevant original sources and decisive unread passages, cross-check important claims, and synthesize by subquestion. ")
        append("A body_retrieved status covers retrieval only. Explain unverified, unread or inaccessible evidence; never inflate completeness.")
    }
}
