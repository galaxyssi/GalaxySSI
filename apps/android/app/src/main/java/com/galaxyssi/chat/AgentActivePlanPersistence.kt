package com.galaxyssi.chat

import java.security.MessageDigest
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject

/** Immutable encrypted pages, published through a small root after the stream is durable. */
internal class AgentActivePlanPersistence(
    private val storage: AgentSessionCheckpointStorage,
    private val storageKey: String
) {
    private val prefix = "active-plan:${AgentNativeJsonCodec.sha256(storageKey)}:"

    fun save(sessionId: String, planId: String, revision: Int, records: (() -> Sequence<String>)?,
        publishRoot: (JSONObject?) -> Unit) {
        if (records == null) { publishRoot(null); clear(); return }
        val hash = MessageDigest.getInstance("SHA-256")
        var characters = 0L
        records().forEach { record -> update(hash, record); update(hash, "\n"); characters += record.length + 1L }
        val digest = hex(hash.digest())
        val prior = runCatching { JSONObject(storage.readString(storageKey, ""))
            .optJSONObject(ROOT_KEY) }.getOrNull()
        if (prior?.optInt("version") == VERSION && prior.optString("sha256") == digest &&
            prior.optString("session_id") == sessionId && prior.optString("plan_id") == planId &&
            prior.optInt("revision") == revision && runCatching { visit(sessionId, prior) {} }.isSuccess) {
            publishRoot(prior)
            collect(prior.getString("generation"))
            return
        }
        val generation = UUID.randomUUID().toString()
        val page = StringBuilder(PAGE_CHARS + 1)
        val writtenHash = MessageDigest.getInstance("SHA-256")
        var pageCount = 0
        fun flush(length: Int) {
            val chunk = page.substring(0, length)
            storage.writePlanPage("$prefix$generation:${pageCount++}", chunk)
            update(writtenHash, chunk)
            page.delete(0, length)
        }
        records().forEach { record ->
            for (text in listOf(record, "\n")) {
                var offset = 0
                while (offset < text.length) {
                    val count = minOf(PAGE_CHARS + 1 - page.length, text.length - offset)
                    page.append(text, offset, offset + count)
                    offset += count
                    if (page.length > PAGE_CHARS) {
                        val boundary = if (page[PAGE_CHARS - 1].isHighSurrogate() && page[PAGE_CHARS].isLowSurrogate())
                            PAGE_CHARS - 1 else PAGE_CHARS
                        flush(boundary)
                    }
                }
            }
        }
        if (page.isNotEmpty()) flush(page.length)
        check(hex(writtenHash.digest()) == digest) { "Active plan changed during checkpoint publication" }
        val reference = JSONObject().put("version", VERSION).put("session_id", sessionId)
            .put("storage_scope", AgentNativeJsonCodec.sha256(storageKey)).put("plan_id", planId)
            .put("revision", revision).put("generation", generation).put("sha256", digest)
            .put("pages", pageCount).put("characters", characters)
        // Failed publication may leave orphan pages; it must never remove the prior committed graph.
        publishRoot(reference)
        collect(generation)
    }

    fun read(sessionId: String, reference: JSONObject): JSONObject {
        var plan: JSONObject? = null
        val line = StringBuilder()
        visit(sessionId, reference) { chunk ->
            var offset = 0
            while (offset < chunk.length) {
                val end = chunk.indexOf('\n', offset)
                if (end < 0) { line.append(chunk, offset, chunk.length); break }
                line.append(chunk, offset, end)
                val record = JSONObject(line.toString())
                line.setLength(0)
                val kind = record.getString("kind")
                if (kind == "header") {
                    check(plan == null) { "Duplicate active plan header" }
                    plan = record.getJSONObject("value").also { header ->
                        COLLECTIONS.forEach { header.put(it, JSONArray()) }
                    }
                } else {
                    check(kind in COLLECTIONS && plan != null) { "Invalid active plan record order or kind" }
                    plan!!.getJSONArray(kind).put(record.getJSONObject("value"))
                }
                offset = end + 1
            }
        }
        check(line.isEmpty()) { "Incomplete active plan record" }
        return requireNotNull(plan) { "Active plan header is missing" }.also {
            check(it.getString("plan_id") == reference.getString("plan_id") &&
                it.getInt("revision") == reference.getInt("revision")) { "Active plan revision mismatch" }
        }
    }

    private fun visit(sessionId: String, reference: JSONObject, consume: (String) -> Unit) {
        check(reference.getInt("version") == VERSION) { "Unsupported active plan checkpoint version" }
        check(reference.getString("session_id") == sessionId &&
            reference.getString("storage_scope") == AgentNativeJsonCodec.sha256(storageKey)) {
            "Active plan checkpoint belongs to another session"
        }
        val generation = reference.getString("generation")
        check(runCatching { UUID.fromString(generation).toString() == generation }.getOrDefault(false)) {
            "Invalid active plan generation"
        }
        val count = reference.getInt("pages")
        val expectedCharacters = reference.getLong("characters")
        check(count > 0 && expectedCharacters > 0 &&
            count.toLong() * (PAGE_CHARS - 1) <= expectedCharacters + PAGE_CHARS &&
            count.toLong() * PAGE_CHARS >= expectedCharacters) { "Invalid active plan checkpoint length" }
        val hash = MessageDigest.getInstance("SHA-256")
        var characters = 0L
        repeat(count) { index ->
            val chunk = storage.readPlanPage("$prefix$generation:$index")
            check(chunk.isNotEmpty() && chunk.length <= PAGE_CHARS) { "Active plan checkpoint page $index is missing or invalid" }
            update(hash, chunk)
            characters += chunk.length
            consume(chunk)
        }
        check(characters == expectedCharacters && hex(hash.digest()) == reference.getString("sha256")) {
            "Active plan checkpoint integrity check failed"
        }
    }

    private fun collect(generation: String) = storage.removePlanPages(
        storage.planPageKeys(prefix).filterNot { it.startsWith("$prefix$generation:") })
    fun clear() = storage.removePlanPages(storage.planPageKeys(prefix))

    companion object {
        const val ROOT_KEY = "durable_active_plan"
        const val PAGE_CHARS = 24 * 1024
        private const val VERSION = 2
        private val COLLECTIONS = setOf("actions", "action_history", "checkpoints", "steps", "verification_results")
        private val locks = Array(64) { Any() }
        fun lock(key: String): Any = locks[(key.hashCode() and Int.MAX_VALUE) % locks.size]
        private fun update(hash: MessageDigest, value: String) {
            val bytes = value.toByteArray(Charsets.UTF_8)
            try { hash.update(bytes) } finally { bytes.fill(0) }
        }
        private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }
    }
}
