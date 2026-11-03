package com.galaxyssi.chat

import org.json.JSONObject

/** Ephemeral RPC replay, not delivery acknowledgement or durable publication storage. */
internal class CollaborationExchangeReplay(
    private val clock: () -> Long = { System.nanoTime() / 1_000_000 },
    private val concurrency: Int = 4,
    private val capacity: Int = 128,
    private val maxBytes: Int = 4 * 1024 * 1024
) {
    enum class Outcome { STARTED, REPLAY, IN_FLIGHT, BUSY, CONFLICT, EXPIRED, INVALID }
    data class Admission(val outcome: Outcome, val lease: Lease? = null)
    internal data class Saved(val access: CollaborationWorkspaceAccess, val raw: String, val bytes: Int)
    internal class Lease internal constructor(internal val key: String, internal val fingerprint: String,
        internal val deadline: Long, internal val saved: Saved?) {
        val replay: Boolean get() = saved != null
    }
    private data class Completed(val fingerprint: String, val deadline: Long, val saved: Saved)
    private val active = mutableMapOf<String, Lease>()
    private val completed = linkedMapOf<String, Completed>()
    private var retainedBytes = 0

    init { require(concurrency > 0 && capacity >= 0 && maxBytes >= 0) }

    @Synchronized fun acquire(peer: String, request: JSONObject, now: Long): Admission {
        prune()
        val expires = CollaborationRemoteEvidenceProtocol.integer(request, "expires_at") ?: return Admission(Outcome.INVALID)
        val lifetime = expires - now
        if (lifetime !in 1..60_000L) return Admission(Outcome.EXPIRED)
        val (key, fingerprint) = runCatching {
            val key = MqttImmutableContent.hash(JSONObject().put("peer", peer).put("request_id", request.getString("request_id")))
            // Routing/replay metadata may change between MQTT attempts; RPC selectors and authority may not.
            val semantic = CollaborationRemoteEvidenceProtocol.scope(request)
            listOf("type", "contract", "request_id", "expires_at", "phase", "arguments", "delivery").forEach {
                if (request.has(it)) semantic.put(it, request.get(it))
            }
            key to MqttImmutableContent.hash(semantic)
        }.getOrElse { return Admission(Outcome.INVALID) }
        active[key]?.let { return Admission(if (it.fingerprint == fingerprint) Outcome.IN_FLIGHT else Outcome.CONFLICT) }
        val prior = completed[key]
        if (prior != null && prior.fingerprint != fingerprint) return Admission(Outcome.CONFLICT)
        if (active.size >= concurrency) return Admission(Outcome.BUSY)
        val lease = Lease(key, fingerprint, prior?.deadline ?: (clock() + lifetime), prior?.saved)
        active[key] = lease
        return Admission(if (lease.replay) Outcome.REPLAY else Outcome.STARTED, lease)
    }

    @Synchronized fun read(lease: Lease, access: CollaborationWorkspaceAccess): JSONObject? {
        check(active[lease.key] === lease)
        return lease.saved?.takeIf { it.access == access && lease.deadline > clock() }?.let { JSONObject(it.raw) }
    }

    @Synchronized fun remember(lease: Lease, access: CollaborationWorkspaceAccess, result: JSONObject): Boolean {
        check(active[lease.key] === lease)
        prune()
        if (lease.deadline <= clock() || !result.optBoolean("success") || capacity == 0) return false
        val raw = result.toString()
        val bytes = raw.toByteArray(Charsets.UTF_8).size
        if (bytes > maxBytes) return false
        completed[lease.key]?.let {
            check(it.fingerprint == lease.fingerprint && it.saved.access == access && it.saved.raw == raw) {
                "Completed RPC response cannot change under the same request identity"
            }
            return true
        }
        while (completed.size >= capacity || retainedBytes + bytes > maxBytes) remove(completed.keys.first())
        completed[lease.key] = Completed(lease.fingerprint, lease.deadline, Saved(access, raw, bytes))
        retainedBytes += bytes
        return true
    }

    @Synchronized fun release(lease: Lease) {
        if (active[lease.key] === lease) active.remove(lease.key)
        prune()
    }

    private fun prune() {
        val now = clock()
        completed.filterValues { it.deadline <= now }.keys.toList().forEach(::remove)
    }

    private fun remove(key: String) { completed.remove(key)?.let { retainedBytes -= it.saved.bytes } }
}
