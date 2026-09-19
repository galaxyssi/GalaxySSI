package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI
import java.security.MessageDigest

/** Task-local public evidence records. Quote matching is provenance, never a truth verdict. */
internal class ResearchEvidenceAudit {
    private val queries = linkedSetOf<String>()
    private val sources = linkedMapOf<String, MutableSet<String>>()
    private val bodies = linkedSetOf<String>()
    private val bodyPassages = linkedSetOf<String>()
    private var chars = 0
    private var truncated = false
    private var snapshot: JSONObject? = null

    @Synchronized fun observe(root: JSONObject) {
        val trace = root.optJSONObject("research_trace")
        rows(trace?.optJSONArray("queries")).forEach { value ->
            if (queries.size < 4096) queries += value.toString() else truncated = true
        }
        rows(trace?.optJSONArray("sources")).filterIsInstance<JSONObject>().forEach { add(it.optString("url"), "", false) }
        if (trace?.optBoolean("truncated") == true) truncated = true
        rows(root.optJSONObject("evidence_pack")?.optJSONArray("items")).filterIsInstance<JSONObject>().forEach {
            add(it.optString("url"), it.optString("excerpt"), it.optString("evidence_level") == "retrieved_body")
        }
        // Only our tool's checkpoint output can restore a submitted audit; web data cannot.
    }

    @Synchronized fun restore(tool: String, arguments: JSONObject) {
        if (tool == TOOL) submit(arguments)
    }

    @Synchronized fun reviewPrompt(request: String): String? {
        if (snapshot != null || sources.isEmpty() || !Regex("(?i)(调查|研究|分析|所有|全面|完整|investigat|research|comprehensive|exhaustive|all.{0,30}publications)").containsMatchIn(request)) return null
        return "Before delivering this investigation, call research_audit once with a compact public evidence ledger: " +
            "important claims and exact observed quotes, entity candidates with unresolved identities left pending, and coverage facets including unavailable databases. " +
            "Do not run searches to inflate counts. A tool quote match proves provenance only. Preserve counterevidence and explicitly qualify unresolved claims."
    }

    private fun add(raw: String, passage: String, body: Boolean) {
        val url = canonical(raw) ?: return
        if (url !in sources && sources.size >= 20000) { truncated = true; return }
        val passages = sources.getOrPut(url) { linkedSetOf() }
        if (passage.isNotBlank() && passage !in passages) {
            if (chars + passage.length <= 8_000_000) { passages += passage; chars += passage.length }
            else truncated = true
        }
        if (body && passage.isNotBlank()) {
            bodies += url
            if (passage in passages) bodyPassages += "$url:${hash(passage)}"
        }
    }

    @Synchronized fun submit(input: JSONObject): JSONObject {
        // Fail closed on oversized/invalid snapshots; never silently drop the last counterevidence.
        if (input.toString().length > 160_000 || input.optString("scope").isBlank() ||
            !validRows(input, "entities", 40) || !validRows(input, "claims", 80) || !validRows(input, "coverage", 40)) {
            return JSONObject().put("status", "invalid").put("tool", TOOL)
                .put("error", "Provide scope and bounded entities, claims, coverage arrays; preserve counterevidence.")
        }
        val issues = linkedSetOf<String>()
        val entities = JSONArray()
        val states = linkedMapOf<String, String>()
        for (row in rows(input.getJSONArray("entities")).filterIsInstance<JSONObject>()) {
            val id = row.optString("id").take(80)
            if (id.isBlank() || id in states) return invalid("Entity IDs must be unique and nonblank")
            val evidence = references(row.optJSONArray("evidence"))
            val anchored = rows(evidence).filterIsInstance<JSONObject>().any { it.optBoolean("passage_observed") }
            var decision = row.optString("decision")
            val basis = row.optString("basis")
            if (decision !in setOf("include", "pending", "exclude") || !anchored ||
                (decision == "include" && basis != "positive_match") ||
                (decision == "exclude" && basis != "positive_mismatch")) decision = "pending"
            if (decision == "pending") issues += "identity_unresolved"
            states[id] = decision
            entities.put(JSONObject().put("id", id).put("name", row.optString("name").take(200))
                .put("decision", decision).put("basis", basis.take(40)).put("reason", row.optString("reason").take(1000))
                .put("evidence", evidence).put("decision_authority", "model_assessment_not_independent_verification"))
        }
        val claims = JSONArray()
        val claimIds = linkedSetOf<String>()
        for (row in rows(input.getJSONArray("claims")).filterIsInstance<JSONObject>()) {
            val id = row.optString("id").take(80)
            if (id.isBlank() || !claimIds.add(id)) return invalid("Claim IDs must be unique and nonblank")
            val refs = references(row.optJSONArray("evidence"))
            val refsList = rows(refs).filterIsInstance<JSONObject>()
            val entityIds = rows(row.optJSONArray("entity_ids")).map { it.toString().take(80) }
            val identityPending = entityIds.any { states[it] != "include" }
            val support = refsList.any { it.optBoolean("passage_observed") && it.optString("relation") == "supports" }
            val conflict = refsList.any { it.optString("relation") == "contradicts" }
            var assessment = row.optString("assessment")
            if (assessment !in setOf("supported", "inference", "disputed", "unknown")) assessment = "unknown"
            if (identityPending || !support && assessment == "supported") assessment = "unknown"
            if (conflict) assessment = "disputed"
            if (assessment != "supported") issues += "claim_requires_qualification"
            claims.put(JSONObject().put("id", id).put("statement", row.optString("statement").take(1500))
                .put("entity_ids", JSONArray(entityIds)).put("assessment", assessment).put("evidence", refs))
        }
        val coverage = JSONArray()
        for (row in rows(input.getJSONArray("coverage")).filterIsInstance<JSONObject>()) {
            val query = row.optString("query").take(1024)
            val executed = query in queries
            val status = row.optString("status").takeIf { it in setOf("searched", "unavailable", "not_searched") } ?: "not_searched"
            val gap = row.optString("gap").take(1000)
            if (!executed || status != "searched" || gap.isNotBlank()) issues += "coverage_incomplete"
            coverage.put(JSONObject().put("facet", row.optString("facet").take(300)).put("status", status)
                .put("query", query).put("query_observed", executed).put("gap", gap))
        }
        if (claims.length() == 0) issues += "claims_missing"
        if (coverage.length() == 0) issues += "coverage_incomplete"
        if (truncated) issues += "observation_truncated"
        snapshot = JSONObject().put("status", "recorded").put("tool", TOOL).put("scope", input.optString("scope").take(2000))
            .put("entities", entities).put("claims", claims).put("coverage", coverage).put("issues", JSONArray(issues))
            .put("completeness", "not_established").put("semantic_verification", "not_independently_verified")
        return report()
    }

    @Synchronized fun report(): JSONObject = (snapshot?.let { JSONObject(it.toString()) }
        ?: JSONObject().put("status", "not_submitted").put("tool", TOOL)).put("observed", JSONObject()
            .put("unique_queries", queries.size).put("source_urls", sources.size).put("body_urls", bodies.size)
            .put("canonical_records", sources.keys.map(::recordKey).toSet().size)
            .put("record_grouping", "explicit_identifier_url_aliases_only_not_independent_evidence")
            .put("scope", "host_observed_only_not_full_agent_activity").put("truncated", truncated))

    private fun references(array: JSONArray?): JSONArray = JSONArray().apply {
        for (row in rows(array).filterIsInstance<JSONObject>()) {
            val url = canonical(row.optString("url"))
            val quote = row.optString("quote").trim().take(1200)
            val match = if (quote.length < 8) null else sources[url]?.firstOrNull { it.contains(quote) }
            put(JSONObject().put("url", url ?: "").put("quote", quote)
                .put("relation", row.optString("relation").takeIf { it in setOf("supports", "contradicts", "context") } ?: "context")
                .put("source_observed", url in sources).put("passage_observed", match != null)
                .put("passage_sha256", match?.let(::hash) ?: "").put("quote_offset", match?.indexOf(quote) ?: -1)
                .put("evidence_scope", if (match != null && "$url:${hash(match)}" in bodyPassages) "retrieved_excerpt" else "search_snippet_or_unavailable"))
        }
    }

    companion object {
        const val TOOL = "research_audit"
        private fun invalid(message: String) = JSONObject().put("tool", TOOL).put("status", "invalid").put("error", message)
        private fun rows(array: JSONArray?): List<Any> = (0 until (array?.length() ?: 0)).mapNotNull { array?.opt(it) }
        private fun validRows(root: JSONObject, key: String, limit: Int): Boolean {
            val list = root.optJSONArray(key) ?: return false
            val fields = when (key) {
                "entities" -> listOf("id", "name", "decision", "basis", "reason")
                "claims" -> listOf("id", "statement", "assessment")
                else -> listOf("facet", "status", "query", "gap")
            }
            return list.length() <= limit && rows(list).all { row -> row is JSONObject &&
                fields.all { row.opt(it) is String } &&
                (key == "coverage" || row.optJSONArray("evidence")?.let { refs -> refs.length() <= 8 && rows(refs).all {
                    it is JSONObject && it.opt("url") is String && it.opt("quote") is String &&
                        it.optString("quote").length <= 1200 && it.optString("url").length <= 4096
                } } == true) &&
                (key != "claims" || row.optJSONArray("entity_ids")?.let { ids -> ids.length() <= 8 && rows(ids).all { it is String } } == true) }
        }
        private fun canonical(raw: String): String? = AgentResearchTrace.safeUrl(raw)
        private fun hash(value: String) = MessageDigest.getInstance("SHA-256").digest(value.toByteArray())
            .joinToString("") { "%02x".format(it) }
        private fun recordKey(url: String): String {
            val uri = runCatching { URI(url) }.getOrNull() ?: return url
            val host = uri.host?.lowercase()
            if (host in setOf("doi.org", "dx.doi.org")) return "doi:${uri.path.trim('/').lowercase()}"
            if (host == "pubmed.ncbi.nlm.nih.gov" && uri.path.trim('/').all(Char::isDigit) && uri.path.trim('/').isNotEmpty())
                return "pmid:${uri.path.trim('/')}"
            return url
        }
    }
}
