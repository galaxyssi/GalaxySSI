package com.galaxyssi.chat

import org.json.JSONObject
import java.util.UUID

/** Bounded, short-lived delivery challenges. Lost process state requires a new read, never assumed delivery. */
internal class CollaborationRecallDelivery(
    private val clock: () -> Long = { System.nanoTime() / 1_000_000 },
    private val newId: () -> String = { UUID.randomUUID().toString() },
    private val capacity: Int = 128
) {
    private data class Pending(val scope: String, val access: CollaborationWorkspaceAccess,
                               val arguments: String, val pageHash: String, val expires: Long, var confirmed: Boolean = false)
    private val pending = linkedMapOf<String, Pending>()

    @Synchronized fun prepare(request: JSONObject, access: CollaborationWorkspaceAccess, result: JSONObject): JSONObject {
        prune()
        if (!result.optBoolean("success") || request.getJSONObject("arguments").optString("mode") != "evidence" ||
            request.getJSONObject("arguments").optString("evidence_id").isBlank()) return result
        if (pending.size >= capacity) pending.entries.firstOrNull { it.value.confirmed }?.key?.let(pending::remove)
        check(pending.size < capacity) { "Recall confirmation capacity busy; retry after current reads finish" }
        val content = result.getString("content")
        val hash = MqttImmutableContent.sha256(content)
        val id = newId()
        check(id !in pending)
        pending[id] = Pending(identity(request), access, selectors(request), hash, clock() + 60_000)
        return result.put("delivery", JSONObject().put("receipt_id", id).put("content_sha256", hash))
    }

    fun confirm(request: JSONObject, access: CollaborationWorkspaceAccess,
                commit: (JSONObject, String) -> JSONObject?): JSONObject {
        val delivery = request.getJSONObject("delivery")
        val entry = synchronized(this) {
            prune()
            pending[delivery.getString("receipt_id")]?.takeIf {
                it.scope == identity(request) && it.access == access && it.arguments == selectors(request) &&
                    it.pageHash == delivery.getString("content_sha256")
            }
        } ?: return CollaborationRemoteRecallProtocol.unavailable()
        // Keep the small challenge until expiry so a lost confirmation can be retried idempotently.
        val coverage = commit(JSONObject(entry.arguments), entry.pageHash)
            ?: return CollaborationRemoteRecallProtocol.unavailable()
        synchronized(this) {
            if (pending[delivery.getString("receipt_id")] === entry) entry.confirmed = true
        }
        return JSONObject().put("success", true).put("status", "confirmed")
            .put("delivery", JSONObject(delivery.toString())).put(CollaborationEvidenceReadCoverage.FIELD, coverage)
    }

    private fun prune() { val now = clock(); pending.entries.removeAll { it.value.expires <= now } }
    private fun identity(request: JSONObject) = CollaborationRemoteEvidenceProtocol.scope(request).toString()
    private fun selectors(request: JSONObject): String {
        val args = request.getJSONObject("arguments")
        return JSONObject().apply { args.keys().asSequence().sorted().forEach { put(it, args.get(it)) } }.toString()
    }
}
