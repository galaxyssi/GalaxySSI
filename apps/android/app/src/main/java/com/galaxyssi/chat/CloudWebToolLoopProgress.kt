package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.BitSet
import java.util.Locale

/** Tracks semantic tool progress without imposing a fixed round or call count. */
internal class CloudWebToolLoopProgress {
    private val outputsByCall = linkedMapOf<String, String>()
    private val requestedRepairs = linkedSetOf<String>()
    private val evidenceKeys = linkedSetOf<String>()
    private val unavailableResources = linkedMapOf<String, String>()
    private val retrievedResources = linkedMapOf<String, String>()
    private data class GoalPage(val snapshot: String, val reader: String, val index: Long, val hash: String)
    private val goalPagesByOutput = linkedMapOf<String, GoalPage>()
    private val observedGoalPages = linkedMapOf<Triple<String, String, Long>, String>()
    private data class RulePage(val topic: String, val start: Int, val end: Int)
    private val rulePagesByOutput = linkedMapOf<String, RulePage>()
    private val observedRuleCharacters = mutableMapOf<String, BitSet>()
    private val ruleReferences = mutableMapOf<String, String>()
    private val methodHistory = CloudMethodHistoryProgress()
    private var stagnantBatches = 0

    fun observeEvidenceBatch(outputs: List<String>): Boolean {
        var gainedEvidence = false
        outputs.forEach { encoded ->
            val output = runCatching { JSONObject(encoded) }.getOrNull() ?: return@forEach
            methodHistory.observe(encoded)?.let { gained ->
                if (gained) gainedEvidence = true
                return@forEach
            }
            rulePagesByOutput[encoded]?.let { page ->
                val seen = observedRuleCharacters.getOrPut(page.topic) { BitSet() }
                if (seen.nextClearBit(page.start) < page.end) gainedEvidence = true
                seen.set(page.start, page.end)
                return@forEach
            }
            if (output.opt("format") == CloudGoalPageProtocol.FORMAT) {
                val page = goalPagesByOutput[encoded] ?: return@forEach
                val identity = Triple(page.snapshot, page.reader, page.index)
                // A pinned page is immutable; changing its digest cannot manufacture new progress.
                if (identity !in observedGoalPages) {
                    observedGoalPages[identity] = page.hash
                    gainedEvidence = true
                }
                return@forEach
            }
            if (output.optString("tool") == CloudImageAnnotationPlan.TOOL &&
                output.optString("status") == "completed" && output.optBoolean("image_saved")
            ) {
                val hash = output.optString("image_sha256")
                if (hash.matches(Regex("[a-f0-9]{64}")) && evidenceKeys.add("annotation:$hash")) gainedEvidence = true
            }
            val items = output.optJSONObject("evidence_pack")?.optJSONArray("items") ?: JSONArray()
            for (index in 0 until items.length()) {
                val item = items.optJSONObject(index) ?: continue
                val url = item.optString("url")
                if (url.isBlank()) continue
                val key = url + "|" + item.optString("content_sha256") + "|" +
                    item.optString("evidence_level") + "|" + canonicalJson(item.optJSONArray("images")) +
                    "|" + canonicalJson(item.optJSONObject("reading_window"))
                if (evidenceKeys.add(key)) gainedEvidence = true
            }
        }
        stagnantBatches = if (gainedEvidence) 0 else stagnantBatches + 1
        return stagnantBatches >= 3
    }

    var finalizationRequested: Boolean = false
        private set

    fun cached(toolName: String, arguments: JSONObject): String? =
        outputsByCall[semanticKey(toolName, arguments)] ?: resourceKey(toolName, arguments)?.let { url ->
            unavailableResources[url] ?: if (canReuseBody(toolName, arguments)) retrievedResources[url] else null
        }

    fun invalidate(toolName: String, arguments: JSONObject) {
        outputsByCall.remove(semanticKey(toolName, arguments))
    }

    fun record(toolName: String, arguments: JSONObject, output: String): Boolean {
        val key = semanticKey(toolName, arguments)
        if (outputsByCall.containsKey(key)) return false
        outputsByCall[key] = output
        // Only executor/checkpoint observations establish provenance, never a tool name in model content.
        if (toolName == CloudGoalPageProtocol.RECALL_TOOL && arguments.opt("mode") == "goal_contract" &&
            arguments.keys().asSequence().all { it in setOf("mode", "cursor") } &&
            (!arguments.has("cursor") || arguments.opt("cursor") is String)) {
            goalPage(output)?.let { goalPagesByOutput[output] = it }
        }
        if (toolName == CollaborationCloudRecall.NAME && arguments.opt("mode") == "evolution_rules") {
            rulePage(arguments, output)?.let { rulePagesByOutput[output] = it }
        }
        if (toolName == CollaborationCloudRecall.NAME && arguments.opt("mode") == "method_history") {
            methodHistory.record(arguments, output)
        }
        val errorCode = runCatching { JSONObject(output).optString("error_code") }.getOrDefault("")
        if (errorCode in setOf("web_source_timeout", "web_tool_timeout", "renderer_unavailable")) {
            resourceKey(toolName, arguments)?.let { unavailableResources[it] = output }
        }
        if (canReuseBody(toolName, arguments)) {
            val result = runCatching { JSONObject(output) }.getOrNull()
            val items = result?.optJSONObject("evidence_pack")?.optJSONArray("items")
            val requested = resourceKey(toolName, arguments)
            if (result?.optString("status") == "completed" && requested != null && items != null &&
                (0 until items.length()).any { index -> items.optJSONObject(index)?.let {
                    it.optString("evidence_level") == "retrieved_body" &&
                        AgentWebIntelligenceText.canonicalUrl(it.optString("url")) == requested
                } == true }) retrievedResources[requested] = output
        }
        return true
    }

    private fun goalPage(encoded: String): GoalPage? = runCatching {
        val page = JSONObject(encoded)
        require(page.opt("status") == "returned" && page.opt("format") == CloudGoalPageProtocol.FORMAT &&
            page.opt("trust") == "host_goal_contract_not_comprehension_or_claim_verification" && page.isNull("error"))
        fun hash(key: String): String = requireNotNull(page.opt(key) as? String).also {
            require(it.matches(Regex("[a-f0-9]{64}")))
        }
        val snapshot = hash("snapshot_id")
        require(hash("snapshot_sha256") == snapshot)
        val reader = hash("reader_sha256")
        val index = requireNotNull(CloudGoalPageProtocol.integer(page, "page_index"))
        val count = requireNotNull(CloudGoalPageProtocol.integer(page, "page_count"))
        require(count in 1..Int.MAX_VALUE.toLong() && index in 0 until count)
        require(page.getJSONArray("fragments").length() > 0 && page.has("next_cursor"))
        require(if (index + 1 == count) page.isNull("next_cursor")
            else (page.opt("next_cursor") as? String)?.matches(Regex("[A-Za-z0-9_-]{54}")) == true)
        GoalPage(snapshot, reader, index, hash("page_sha256"))
    }.getOrNull()

    private fun rulePage(arguments: JSONObject, encoded: String): RulePage? = runCatching {
        require(arguments.keys().asSequence().all { it in setOf("mode", "topic", "offset") })
        val topic = if (arguments.has("topic")) requireNotNull(arguments.opt("topic") as? String) else "all"
        val offset = if (arguments.has("offset")) requireNotNull(CollaborationRemoteEvidenceProtocol.integer(arguments, "offset")) else 0L
        require(offset in 0..Int.MAX_VALUE.toLong())
        val reference = ruleReferences.getOrPut(topic) { CollaborationEvolutionProtocol.rules(topic).toString() }
        val start = offset.toInt().coerceAtMost(reference.length)
        val end = minOf(reference.length, start + 8_000)
        val page = JSONObject(encoded)
        require(page.opt("status") == "returned" && page.opt("topic") == topic && page.isNull("error") &&
            page.opt("trust") == "host_schema_not_execution_authority")
        require(page.opt("content") == reference.substring(start, end) &&
            CollaborationRemoteEvidenceProtocol.integer(page, "total_characters") == reference.length.toLong())
        require(page.has("next_offset") && if (end < reference.length)
            CollaborationRemoteEvidenceProtocol.integer(page, "next_offset") == end.toLong() else page.isNull("next_offset"))
        RulePage(topic, start, end)
    }.getOrNull()

    private fun canReuseBody(toolName: String, arguments: JSONObject): Boolean =
        toolName.lowercase(Locale.ROOT) in setOf("web_fetch", "web_extract") &&
            !arguments.optBoolean("force") && !arguments.has("content") &&
            (arguments.optJSONArray("fields")?.length() ?: 0) == 0 &&
            !arguments.has("focus") && !arguments.has("offset") && !arguments.has("length") &&
            !arguments.has("document_sha256")

    private fun resourceKey(toolName: String, arguments: JSONObject): String? {
        if (toolName.lowercase(Locale.ROOT) !in setOf("web_fetch", "web_extract", "web_diff")) return null
        val url = arguments.optString("url").trim()
        return url.takeIf { it.isNotBlank() }?.let(AgentWebIntelligenceText::canonicalUrl)
    }

    fun requestRepair(kind: String): Boolean = requestedRepairs.add(kind)

    fun requestDeadlineSynthesis(hasEvidence: Boolean): Boolean =
        hasEvidence && requestFinalization()

    fun requestEmptySynthesisRepair(answer: String, hasEvidence: Boolean): Boolean =
        hasEvidence && answer.isBlank() && requestRepair("empty_synthesis")

    fun requestSynthesisCitationRepair(): Boolean {
        if (!requestRepair("stream_citations")) return false
        requestFinalization()
        return true
    }

    fun requestPartialSynthesisRepair(): Boolean =
        "stream_citations" in requestedRepairs && requestRepair("partial_synthesis")

    fun requestFinalization(): Boolean {
        if (finalizationRequested) return false
        finalizationRequested = true
        return true
    }

    internal fun semanticKey(toolName: String, arguments: JSONObject): String {
        val material = toolName.trim().lowercase(Locale.ROOT) + "\u0000" + canonicalJson(arguments)
        return MessageDigest.getInstance("SHA-256")
            .digest(material.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
    }

    private fun canonicalJson(value: Any?): String = when (value) {
        null, JSONObject.NULL -> "null"
        is JSONObject -> value.keys().asSequence().toList().sorted().joinToString(",", "{", "}") { key ->
            JSONObject.quote(key) + ":" + canonicalJson(value.opt(key))
        }
        is JSONArray -> (0 until value.length()).joinToString(",", "[", "]") { index ->
            canonicalJson(value.opt(index))
        }
        is Number, is Boolean -> value.toString()
        else -> JSONObject.quote(value.toString())
    }
}
