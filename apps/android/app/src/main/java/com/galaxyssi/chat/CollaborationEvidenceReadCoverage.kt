package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Host-served pages, not comprehension or scientific verification. Call under the evidence ledger lock. */
internal object CollaborationEvidenceReadCoverage {
    const val FIELD = "host_read_coverage"
    private const val FORMAT = "galaxyssi.evidence_read_coverage.v1"
    private val identityFields = listOf("group_id", "run_id", "turn_id", "round", "node_id", "person_id")

    fun identity(access: CollaborationWorkspaceAccess) = JSONObject().put("group_id", access.groupId)
        .put("run_id", access.runId).put("turn_id", access.turnId).put("round", access.round)
        .put("node_id", access.nodeId).put("person_id", access.personId)

    fun record(rows: CollaborationWorkspaceRows, prefix: String, reader: CollaborationWorkspaceAccess,
               source: JSONObject, content: String, start: Int, end: Int): JSONObject {
        require(start in 0..content.length && end in start..content.length)
        if (!attributable(reader)) return summary(empty(reader, source, content)).put("mode", "unattributed")
        val state = load(rows, prefix, reader, source, content)
        if (end > start) {
            val ranges = state.getJSONArray("ranges")
            val all = (0 until ranges.length()).map { ranges.getJSONArray(it).let { range -> range.getInt(0) to range.getInt(1) } } +
                (start to end)
            val merged = mutableListOf<Pair<Int, Int>>()
            all.sortedBy { it.first }.forEach { range ->
                val last = merged.lastOrNull()
                if (last != null && range.first <= last.second) merged[merged.lastIndex] = last.first to maxOf(last.second, range.second)
                else merged += range
            }
            state.put("ranges", JSONArray(merged.map { JSONArray(listOf(it.first, it.second)) }))
            val raw = state.toString()
            val value = JSONObject().put("payload", raw).put("sha256", digest(raw)).toString()
            val key = key(prefix, reader, source)
            if (rows.read(key) != value) rows.commit(mapOf(key to value))
        }
        return summary(state)
    }

    fun snapshot(rows: CollaborationWorkspaceRows, prefix: String, reader: CollaborationWorkspaceAccess, source: JSONObject): JSONObject {
        if (!attributable(reader)) return summary(empty(reader, source, source.toString())).put("mode", "unattributed")
        val state = load(rows, prefix, reader, source, source.toString())
        val result = summary(state)
        // Ownership must not hide a separately confirmed full read from the next reviewer.
        return if (sameIdentity(identity(reader), source) && !result.getBoolean("complete"))
            result.put("mode", "same_dispatch_execution") else result
    }

    fun requireComplete(reference: JSONObject, review: JSONObject, source: JSONObject) {
        val coverage = requireNotNull(reference.optJSONObject(FIELD)) {
            "Read every original evidence page with scoped recall before publishing a new independent review"
        }
        require(coverage.optString("format") == FORMAT &&
            sameIdentity(coverage.getJSONObject("reader"), review) &&
            coverage.getString("evidence_id") == source.getString("evidence_id") &&
            coverage.getString("sha256") == source.getString("sha256")) {
            "Original evidence page coverage belongs to a different reviewer dispatch or source"
        }
        val ownExecution = coverage.optString("mode") == "same_dispatch_execution" && sameIdentity(review, source)
        require(ownExecution || coverage.optString("mode") == "scoped_pages" && coverage.getBoolean("complete") &&
            coverage.getInt("covered_characters") == source.toString().length &&
            coverage.getInt("total_characters") == source.toString().length &&
            coverage.getString("content_sha256") == digest(source.toString())) {
            "Original evidence was not fully served to this reviewer before publication; follow all next_offset pages and publish a new review"
        }
    }

    private fun load(rows: CollaborationWorkspaceRows, prefix: String, reader: CollaborationWorkspaceAccess,
                     source: JSONObject, content: String): JSONObject {
        require(attributable(reader))
        val expected = empty(reader, source, content)
        val envelope = rows.read(key(prefix, reader, source))?.let(::JSONObject) ?: return expected
        val raw = envelope.getString("payload")
        check(digest(raw) == envelope.getString("sha256")) { "Evidence page coverage integrity check failed" }
        val saved = JSONObject(raw)
        check(sameIdentity(saved.getJSONObject("reader"), expected.getJSONObject("reader")) &&
            listOf("format", "evidence_id", "sha256", "content_sha256", "total_characters").all { saved.get(it) == expected.get(it) }) {
            "Evidence page coverage source or reader changed"
        }
        val ranges = saved.getJSONArray("ranges")
        var previousEnd = -1
        repeat(ranges.length()) {
            val range = ranges.getJSONArray(it)
            val start = range.getInt(0)
            val end = range.getInt(1)
            check(range.length() == 2 && start > previousEnd && start >= 0 && end > start && end <= content.length) {
                "Invalid evidence page coverage intervals"
            }
            previousEnd = end
        }
        return saved
    }

    private fun summary(state: JSONObject): JSONObject {
        val result = JSONObject(state.toString())
        val ranges = result.getJSONArray("ranges")
        val covered = (0 until ranges.length()).sumOf { ranges.getJSONArray(it).let { range -> range.getInt(1) - range.getInt(0) } }
        val total = result.getInt("total_characters")
        val firstMissing = if (ranges.length() > 0 && ranges.getJSONArray(0).getInt(0) == 0) ranges.getJSONArray(0).getInt(1) else 0
        result.remove("ranges")
        return result.put("mode", "scoped_pages").put("covered_characters", covered).put("complete", covered == total)
            .put("first_missing_offset", firstMissing.takeIf { it < total } ?: JSONObject.NULL)
            .put("trust", "host_served_pages_not_comprehension_or_claim_verification")
    }

    private fun attributable(reader: CollaborationWorkspaceAccess) = reader.runId.isNotBlank() && reader.turnId.isNotBlank() &&
        reader.nodeId.isNotBlank() && reader.personId.isNotBlank()
    private fun empty(reader: CollaborationWorkspaceAccess, source: JSONObject, content: String) = JSONObject()
        .put("format", FORMAT).put("reader", identity(reader)).put("evidence_id", source.getString("evidence_id"))
        .put("sha256", source.getString("sha256")).put("content_sha256", digest(content))
        .put("total_characters", content.length).put("ranges", JSONArray())
    private fun sameIdentity(left: JSONObject, right: JSONObject) = identityFields.all {
        if (it == "round") left.getLong(it) == right.getLong(it) else left.getString(it) == right.getString(it)
    }
    private fun key(prefix: String, reader: CollaborationWorkspaceAccess, source: JSONObject) = prefix + "read:" +
        digest(identity(reader).toString()) + ":" + source.getString("evidence_id") + ":" + source.getString("sha256")
    private fun digest(value: String) = AgentNativeJsonCodec.sha256(value)
}
