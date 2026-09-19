package com.galaxyssi.chat

import org.json.JSONObject

/** Read-only observations reuse the Run Kernel's encrypted, leased, immutable records. */
internal class CloudResearchCheckpoint(private val records: AgentModelLoopRecords, private val binding: String) {
    data class Observation(val tool: String, val arguments: JSONObject, val output: String)
    private var count = 0
    private var initialized = false

    fun restore(): List<Observation> {
        val initial = records.read("initial") ?: return emptyList()
        check(JSONObject(initial).getString("binding") == binding) { "research_checkpoint_binding_changed" }
        initialized = true
        val restored = mutableListOf<Observation>()
        while (count < 4096) {
            val value = records.read("observation:$count") ?: break
            val item = JSONObject(value)
            val observation = Observation(item.getString("tool"), item.getJSONObject("arguments"), item.getString("output"))
            check(isReadOnly(observation.tool, observation.arguments)) { "research_checkpoint_tool_not_read_only" }
            restored += observation
            count++
        }
        return restored
    }

    fun record(tool: String, arguments: JSONObject, output: String) {
        if (!isReadOnly(tool, arguments)) return
        check(count < 4096) { "research_checkpoint_capacity" }
        initialize()
        records.write("observation:$count", JSONObject().put("tool", tool)
            .put("arguments", arguments).put("output", output).toString())
        count++
    }

    fun finalAnswer(qualityVersion: String? = null): String? = if (initialized)
        records.read(finalKey(qualityVersion))?.let { JSONObject(it).getString("answer") } else null

    fun complete(answer: String, quality: JSONObject? = null) {
        if (!initialized) return
        records.write(finalKey(quality?.optString("contract")), JSONObject().put("answer", answer).put("quality", quality)
            .put("stage", "synthesis_completed").put("delivery", "not_confirmed").toString())
    }

    private fun finalKey(version: String?): String = if (version.isNullOrBlank()) "final" else "final:$version"

    private fun initialize() {
        if (initialized) return
        records.write("initial", JSONObject().put("binding", binding).toString())
        initialized = true
    }

    companion object {
        fun isReadOnly(tool: String, arguments: JSONObject): Boolean = tool in setOf(
            "web_weather", "web_search", "web_image_search", "web_fetch", "web_crawl", "web_extract",
            "web_find_similar", "web_research", "web_agent", "web_diff", ResearchEvidenceAudit.TOOL
        ) || (tool == "web_cache" && arguments.optString("action") in setOf("status", "query", "get", "source_health", "learned_sources"))
    }
}
