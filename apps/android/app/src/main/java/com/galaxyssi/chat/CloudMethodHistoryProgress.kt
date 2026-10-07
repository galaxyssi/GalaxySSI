package com.galaxyssi.chat

import org.json.JSONObject
import java.util.BitSet

/** Reading new host history is tool progress, never evidence of improved task quality. */
internal class CloudMethodHistoryProgress {
    private data class Page(val id: String, val hash: String, val total: Int, val start: Int, val end: Int)
    private val pages = mutableMapOf<String, Page>()
    private val directories = mutableMapOf<String, Set<String>>()
    private val originals = mutableMapOf<String, Pair<String, Int>>()
    private val seen = mutableMapOf<String, BitSet>()
    private val discovered = mutableSetOf<String>()

    fun record(arguments: JSONObject, encoded: String) {
        runCatching {
            require(arguments.optString("mode") == "method_history")
            val output = JSONObject(encoded)
            require(output.optString("status") == "returned" && output.isNull("error") &&
                output.optString("trust") == "host_execution_observation_not_method_effectiveness")
            if (arguments.has("record_id")) {
                require(arguments.keys().asSequence().all { it in setOf("mode", "record_id", "offset") })
                val id = arguments.getString("record_id")
                require(id.matches(HASH) && output.optString("record_id") == id)
                val hash = output.getString("record_sha256").also { require(it.matches(HASH)) }
                val offset = if (arguments.has("offset")) requireNotNull(CollaborationRemoteEvidenceProtocol.integer(arguments, "offset")) else 0L
                val total = requireNotNull(CollaborationRemoteEvidenceProtocol.integer(output, "total_characters"))
                require(total in 1..Int.MAX_VALUE.toLong() && offset in 0..Int.MAX_VALUE.toLong())
                val start = minOf(offset, total).toInt()
                val end = minOf(total, start.toLong() + 8000).toInt()
                require(output.getString("content").length == end - start && output.has("next_offset"))
                require(if (end < total) CollaborationRemoteEvidenceProtocol.integer(output, "next_offset") == end.toLong() else output.isNull("next_offset"))
                pages[encoded] = Page(id, hash, total.toInt(), start, end)
            } else {
                require(arguments.keys().asSequence().all { it in setOf("mode", "object_id", "revision", "sha256", "cursor") })
                require(CollaborationResearchCandidates.same(arguments, output.getJSONObject("method")))
                require(arguments.getString("object_id").matches(HASH) && arguments.getString("sha256").matches(HASH))
                require((CollaborationRemoteEvidenceProtocol.integer(arguments, "revision") ?: 0) > 0)
                val records = output.getJSONArray("records")
                directories[encoded] = (0 until records.length()).map { records.getJSONObject(it).getString("record_id").also { id ->
                    require(id.matches(HASH))
                } }.toSet()
            }
        }
    }

    fun observe(encoded: String): Boolean? {
        pages[encoded]?.let { page ->
            val original = originals.getOrPut(page.id) { page.hash to page.total }
            if (original != (page.hash to page.total)) return false
            val coverage = seen.getOrPut(page.id) { BitSet() }
            val gained = coverage.nextClearBit(page.start) < page.end
            coverage.set(page.start, page.end)
            return gained
        }
        return directories[encoded]?.fold(false) { gained, id -> discovered.add(id) || gained }
    }

    companion object { private val HASH = Regex("[a-f0-9]{64}") }
}
