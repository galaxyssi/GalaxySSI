package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.util.Locale

/** Presentation receipts only: never infer searches from prose or claim that a URL proves a fact. */
internal data class AgentResearchTrace(
    val queries: List<String> = emptyList(),
    val sources: List<Source> = emptyList(),
    val remote: Boolean = false,
    val truncated: Boolean = false
) {
    data class Source(val url: String, val title: String)
    val visible get() = queries.isNotEmpty() || sources.isNotEmpty()

    fun merge(other: AgentResearchTrace): AgentResearchTrace {
        val queryMap = linkedMapOf<String, String>()
        (queries + other.queries).forEach { raw ->
            val q = raw.trim().replace(Regex("\\s+"), " ").take(1024)
            if (q.isNotBlank()) queryMap.putIfAbsent(q.lowercase(Locale.ROOT), q)
        }
        val sourceMap = linkedMapOf<String, Source>()
        (sources + other.sources).forEach { source ->
            val url = safeUrl(source.url) ?: return@forEach
            val title = source.title.trim().replace(Regex("\\s+"), " ").take(512)
            val previous = sourceMap[url]
            if (previous == null || previous.title.isBlank()) sourceMap[url] = Source(url, title)
        }
        return AgentResearchTrace(queryMap.values.take(128), sourceMap.values.take(512), remote || other.remote,
            truncated || other.truncated || queryMap.size > 128 || sourceMap.size > 512)
    }

    fun toJson(): JSONObject = JSONObject().put("queries", JSONArray(queries))
        .put("sources", JSONArray(sources.map { JSONObject().put("url", it.url).put("title", it.title) }))
        .put("remote", remote).put("truncated", truncated)

    companion object {
        fun safeUrl(raw: String): String? = runCatching {
            val uri = URI(raw.trim())
            if (raw.length > 4096 || uri.scheme?.lowercase(Locale.ROOT) !in setOf("http", "https") ||
                uri.host.isNullOrBlank() || uri.rawUserInfo != null) return null
            // Fragments identify positions in one document, not additional sources. Keep query parameters.
            uri.toASCIIString().substringBefore('#')
        }.getOrNull()

        fun decode(json: JSONObject?): AgentResearchTrace {
            if (json == null) return AgentResearchTrace()
            val qs = json.optJSONArray("queries") ?: JSONArray()
            val ss = json.optJSONArray("sources") ?: JSONArray()
            return AgentResearchTrace().merge(AgentResearchTrace(
                (0 until minOf(qs.length(), 1024)).mapNotNull { qs.opt(it) as? String },
                (0 until minOf(ss.length(), 2048)).mapNotNull { index -> ss.optJSONObject(index)?.let {
                    Source(it.optString("url"), it.optString("title"))
                } }, json.optBoolean("remote"), json.optBoolean("truncated") || qs.length() > 128 || ss.length() > 512))
        }

        fun observe(tool: String, arguments: JSONObject, output: String): AgentResearchTrace {
            if (!tool.startsWith("web_")) return AgentResearchTrace()
            val root = runCatching { JSONObject(output) }.getOrNull()
            val queries = mutableListOf<String>()
            if (tool in setOf("web_search", "web_image_search")) {
                arguments.optString("query").takeIf(String::isNotBlank)?.let(queries::add)
            }
            val pack = root?.optJSONObject("evidence_pack")
                ?: root?.optJSONObject("result")?.optJSONObject("evidence_pack")
            val sources = mutableListOf<Source>()
            fun readSources(array: JSONArray?) {
                if (array == null) return
                for (i in 0 until minOf(array.length(), 2048)) array.optJSONObject(i)?.let {
                    sources += Source(it.optString("url"), it.optString("title"))
                }
            }
            readSources(pack?.optJSONArray("items"))
            // Search result snippets are references, not a claim of full-text reading.
            readSources(root?.optJSONArray("results"))
            readSources(root?.optJSONArray("documents"))
            val research = root?.optJSONObject("research")
            val executed = research?.optJSONArray("executed_queries")
            if (executed != null) for (i in 0 until minOf(executed.length(), 128)) {
                (executed.opt(i) as? String)?.let(queries::add)
            }
            return AgentResearchTrace().merge(AgentResearchTrace(queries, sources))
        }
    }
}
