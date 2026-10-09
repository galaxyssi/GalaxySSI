package com.galaxyssi.chat

import java.io.ByteArrayOutputStream
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import org.json.JSONObject

internal class CollaborationRemoteEvidenceImporter(
    private val store: CollaborationRemoteEvidenceStore,
    private val ledger: CollaborationEvidenceLedger
) {
    /** Returns with a durable partial checkpoint on transport failure; never retries an executed operation. */
    suspend fun run(key: String, allowed: (JSONObject) -> Boolean, progress: (JSONObject) -> Unit = {},
        query: suspend (String, JSONObject, JSONObject) -> JSONObject?): Boolean = gate.withJob(key) {
        importSnapshot(key, allowed, progress, query)
    }

    /** Yield between network slices while keeping verified pages and the exact archive cursor. */
    suspend fun runSlice(key: String, allowed: (JSONObject) -> Boolean, progress: (JSONObject) -> Unit = {},
        maxQueries: Int = 4,
        query: suspend (String, JSONObject, JSONObject) -> JSONObject?): CollaborationEvidenceSlice {
        require(maxQueries > 0)
        return gate.withJob(key) {
            var remaining = maxQueries
            var yielded = false
            val complete = importSnapshot(key, allowed, progress) { desktop, fields, selection ->
                if (remaining == 0) { yielded = true; null }
                else { remaining--; query(desktop, fields, selection) }
            }
            when {
                complete -> CollaborationEvidenceSlice.COMPLETE
                yielded -> CollaborationEvidenceSlice.YIELDED
                else -> CollaborationEvidenceSlice.DEFERRED
            }
        }
    }

    private suspend fun importSnapshot(key: String, allowed: (JSONObject) -> Boolean, progress: (JSONObject) -> Unit,
        query: suspend (String, JSONObject, JSONObject) -> JSONObject?): Boolean {
        val job = store.read(key) ?: return true
        if (job.getString("status") != "pending") return true
        val fields = job.getJSONObject("fields")
        val access = ledger.binding(fields.getString("source_message_id").toLong(),
            fields.getString("conversation_id"), fields.getString("turn_id")) ?: return false
        if (access.runId != job.getString("run_id") || access.nodeId != job.getString("node_id")) return false
        fun authorized(): Boolean = allowed(job) && ledger.binding(fields.getString("source_message_id").toLong(),
            access.groupId, access.turnId) == access && store.read(key)?.optString("status") == "pending"
        fun finish(status: String): Boolean {
            store.save(key, job.put("status", status)); return true
        }
        try {
            while (authorized()) {
                currentCoroutineContext().ensureActive()
                var descriptor = job.optJSONObject("active")
                if (descriptor == null) {
                    val cursor = job.getLong("cursor")
                    var entries = job.optJSONArray("index_entries")
                    if (entries == null || entries.length() == 0) {
                        if (job.opt("index_complete") == true)
                            return store.completeSnapshot(key, job)
                        val response = query(job.getString("desktop"), fields,
                            JSONObject().put("mode", "index").put("after_sequence", cursor)
                                .put("inline_page_bytes", CollaborationRemoteEvidenceProtocol.INLINE_PAGE_BYTES)) ?: return false
                        if (!authorized()) return false
                        if (response.optString("status") == "unavailable") return finish("unavailable")
                        require(response.opt("status") == "ready" && response.opt("coverage") == "observed_completed_items_only" &&
                            response.opt("provider_history_complete") == false && response.opt("has_more") is Boolean &&
                            response.opt("archive_final") is Boolean)
                        entries = response.getJSONArray("entries")
                        require(entries.length() <= 20)
                        var last = cursor
                        repeat(entries.length()) { index ->
                            val entry = entries.getJSONObject(index)
                            require(CollaborationRemoteEvidenceProtocol.descriptor(entry, last))
                            last = entry.getLong("sequence")
                        }
                        require(CollaborationRemoteEvidenceProtocol.integer(response, "next_sequence") == last &&
                            (!response.getBoolean("has_more") || entries.length() > 0))
                        cacheInlinePages(key, response, entries)
                        // This boundary is a live snapshot, not proof that the provider has finished.
                        job.put("index_entries", entries).put("index_complete",
                            !response.getBoolean("has_more")).put("archive_final", response.getBoolean("archive_final"))
                        if (entries.length() == 0) return store.completeSnapshot(key, job)
                    }
                    // Keep the remainder of this index page; one query supplies up to twenty observations.
                    descriptor = requireNotNull(entries).getJSONObject(0)
                    val rest = org.json.JSONArray()
                    for (index in 1 until entries.length()) rest.put(entries.getJSONObject(index))
                    store.save(key, job.put("active", descriptor).put("index_entries", rest))
                }
                val entry = requireNotNull(descriptor)
                require(CollaborationRemoteEvidenceProtocol.descriptor(entry, job.getLong("cursor")))
                if (entry.getLong("total_bytes") > CollaborationRemoteEvidenceProtocol.MAX_BODY_BYTES) {
                    store.advance(key, job, entry, imported = false)
                    continue
                }
                val count = entry.getInt("page_count")
                for (index in 0 until count) {
                    currentCoroutineContext().ensureActive()
                    if (!authorized()) return false
                    val cached = store.page(key, entry, index)
                    val existing = cached?.let { decode(it, entry, index) }
                    if (existing != null) { existing.close(); continue }
                    val page = query(job.getString("desktop"), fields, JSONObject().put("mode", "page")
                        .put("evidence_id", entry.getString("evidence_id")).put("sha256", entry.getString("sha256"))
                        .put("page_index", index)) ?: return false
                    if (!authorized()) return false
                    if (page.optString("status") == "unavailable") return finish("unavailable")
                    require(page.opt("evidence_id") == entry.opt("evidence_id"))
                    requireNotNull(decode(page, entry, index)).use { store.savePage(key, entry, index, page) }
                }
                if (!authorized()) return false
                val buffer = object : ByteArrayOutputStream(entry.getInt("total_bytes")) {
                    fun wipe() { buf.fill(0); reset() }
                }
                try {
                    for (index in 0 until count) {
                        currentCoroutineContext().ensureActive()
                        requireNotNull(decode(requireNotNull(store.page(key, entry, index)), entry, index)).use { buffer.write(it.bytes) }
                    }
                    val bytes = buffer.toByteArray()
                    try {
                        val original = CollaborationRemoteEvidenceProtocol.original(bytes, fields, entry)
                            .put("authenticated_desktop_id", job.getString("desktop"))
                        if (!authorized()) return false
                        val at = entry.getLong("recorded_at")
                        ledger.record(access, "desktop:${AgentNativeJsonCodec.sha256(key)}:${entry.getString("evidence_id")}",
                            CollaborationRemoteEvidenceProtocol.recordedTool(entry.getString("item_type")), "{}", original.toString(), at, at,
                            CollaborationEvidenceOrigin.DESKTOP_CODEX_TOOL)
                        // Ledger-first ordering is replay-safe if the process dies before the cursor commit.
                        store.advance(key, job, entry, imported = true)
                        progress(job)
                    } finally { bytes.fill(0) }
                } finally { buffer.wipe() }
            }
            return false
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: IllegalArgumentException) { return finish("integrity_rejected") }
        catch (_: org.json.JSONException) { return finish("integrity_rejected") }
        catch (_: java.nio.charset.CharacterCodingException) { return finish("integrity_rejected") }
        // Storage failures propagate to the read-only recovery worker, preserving the exact descriptor/pages.
    }

    private fun cacheInlinePages(key: String, response: JSONObject, entries: org.json.JSONArray) {
        if (!response.has("inline_pages")) return
        val pages = response.getJSONArray("inline_pages")
        require(pages.length() <= entries.length())
        val descriptors = (0 until entries.length()).map(entries::getJSONObject)
            .associateBy { it.getString("evidence_id") }
        val seen = mutableSetOf<String>()
        var bytes = 0L
        repeat(pages.length()) { index ->
            val page = pages.getJSONObject(index)
            val id = page.getString("evidence_id")
            val entry = requireNotNull(descriptors[id])
            require(seen.add(id) && entry.getInt("page_count") == 1)
            bytes += entry.getLong("total_bytes")
            require(bytes <= CollaborationRemoteEvidenceProtocol.INLINE_PAGE_BYTES)
            requireNotNull(decode(page, entry, 0)).use { store.savePage(key, entry, 0, page) }
        }
    }

    private fun decode(page: JSONObject, descriptor: JSONObject, index: Int): AgentResultRecoveryPageCodec.Page? {
        val decoded = AgentResultRecoveryPageCodec.decode(page, index) ?: return null
        if (decoded.manifest.digest != descriptor.getString("sha256") || decoded.manifest.bytes != descriptor.getLong("total_bytes") ||
            decoded.manifest.pages != descriptor.getInt("page_count")) { decoded.close(); return null }
        return decoded
    }

    companion object {
        private val gate = CollaborationEvidenceImportGate()
    }
}
