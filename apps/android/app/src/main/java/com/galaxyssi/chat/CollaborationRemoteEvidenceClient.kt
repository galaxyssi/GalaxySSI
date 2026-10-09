package com.galaxyssi.chat

import java.util.UUID
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject

/** Read-only queries; a wait timeout does not revoke a correctly bound late reply. */
internal class CollaborationRemoteEvidenceClient(
    private val nowMillis: () -> Long = { System.nanoTime() / 1_000_000L },
    private val lateRetentionMillis: Long = 120_000L,
    private val maxLateRequests: Int = 128,
    private val maxLateBytes: Int = 2 * 1024 * 1024
) {
    private class Pending(val desktop: String, val request: JSONObject, val key: List<Any?>) {
        val result = CompletableDeferred<JSONObject>()
        var active = true
        var expiresAt = Long.MAX_VALUE
        var retentionGeneration = 0L
        var responseBytes = 0
        var expiry: ScheduledFuture<*>? = null
    }
    private val lock = Any()
    private val pending = linkedMapOf<String, Pending>()
    init { require(lateRetentionMillis > 0 && maxLateRequests > 0 && maxLateBytes > 0) }

    suspend fun query(desktop: String, fields: JSONObject, selection: JSONObject, timeoutMillis: Long = 8_000,
        publish: (JSONObject) -> Boolean): JSONObject? {
        require(CollaborationRemoteEvidenceProtocol.validScope(fields) && desktop.isNotBlank())
        val request = CollaborationRemoteEvidenceProtocol.scope(fields)
            .put("type", "agent_task_evidence_request").put("desktop_id", desktop)
        SELECTION.forEach { if (selection.has(it)) request.put(it, selection.get(it)) }
        val key = listOf(desktop) + (AgentResultRecoveryClient.FIELDS + "execution_generation" + SELECTION).map(request::opt)
        val waiter = synchronized(lock) {
            pruneLocked()
            pending.values.firstOrNull { !it.active && it.key == key }?.also {
                it.active = true
                it.expiresAt = Long.MAX_VALUE
                it.expiry?.cancel(false)
            } ?: Pending(desktop, request.put("request_id", UUID.randomUUID().toString()), key).also {
                pending[it.request.getString("request_id")] = it
            }
        }
        var timedOut = false
        try {
            if (waiter.result.isCompleted) return waiter.result.await()
            if (!publish(JSONObject(waiter.request.toString()))) return null
            return withTimeoutOrNull(timeoutMillis) { waiter.result.await() }.also { timedOut = it == null }
        } finally {
            val retain = timedOut && currentCoroutineContext().isActive
            synchronized(lock) {
                if (retain) retainLocked(waiter) else discardLocked(waiter)
            }
        }
    }

    fun receive(payload: JSONObject, authenticatedDesktop: String, diagnostic: (String) -> Unit = {}): Boolean {
        val outcome = synchronized(lock) {
            pruneLocked()
            val waiter = pending[payload.optString("request_id")] ?: return@synchronized "no_pending_request"
            val request = waiter.request
            if (authenticatedDesktop != waiter.desktop) return@synchronized "desktop_mismatch"
            if (payload.opt("type") != "agent_task_evidence" || payload.opt("contract") != CollaborationRemoteEvidenceProtocol.CONTRACT)
                return@synchronized "contract_mismatch"
            if (!CollaborationRemoteEvidenceProtocol.sameScope(request, payload)) return@synchronized "scope_mismatch"
            if (payload.opt("mode") != request.opt("mode")) return@synchronized "mode_mismatch"
            if (payload.opt("status") !in setOf("ready", "unavailable")) return@synchronized "invalid_status"
            if (payload.opt("status") == "ready" && request.opt("mode") == "page" &&
                listOf("page_index", "sha256", "evidence_id").any { payload.opt(it) != request.opt(it) }) return@synchronized "page_mismatch"
            if (waiter.result.isCompleted) return@synchronized "already_completed"
            val raw = payload.toString()
            waiter.responseBytes = raw.toByteArray(Charsets.UTF_8).size
            if (!waiter.active && waiter.responseBytes > maxLateBytes) {
                discardLocked(waiter)
                return@synchronized "late_retention_full"
            }
            val wasActive = waiter.active
            val accepted = waiter.result.complete(JSONObject(raw))
            boundLateLocked()
            // An immediate continuation may consume and remove its waiter inside complete().
            if (accepted && wasActive) "accepted"
            else if (pending[request.getString("request_id")] !== waiter) "late_retention_full"
            else if (!accepted) "already_completed" else "accepted_late"
        }
        diagnostic(outcome)
        return outcome == "accepted" || outcome == "accepted_late"
    }

    private fun retainLocked(waiter: Pending) {
        if (pending[waiter.request.getString("request_id")] !== waiter) return
        waiter.active = false
        val expiry = nowMillis() + lateRetentionMillis
        waiter.expiresAt = expiry
        val generation = ++waiter.retentionGeneration
        waiter.expiry = expiryExecutor.schedule({
            synchronized(lock) {
                if (!waiter.active && waiter.retentionGeneration == generation) discardLocked(waiter)
            }
        }, lateRetentionMillis, TimeUnit.MILLISECONDS)
        boundLateLocked()
    }

    private fun discardLocked(waiter: Pending) {
        if (pending.remove(waiter.request.getString("request_id"), waiter)) {
            waiter.expiry?.cancel(false)
            waiter.result.cancel()
        }
    }

    private fun pruneLocked() {
        val now = nowMillis()
        pending.values.filter { !it.active && it.expiresAt <= now }.forEach(::discardLocked)
    }

    private fun boundLateLocked() {
        val late = pending.values.filter { !it.active }.sortedBy { it.expiresAt }
        var bytes = late.sumOf { it.responseBytes.toLong() }
        var count = late.size
        for (waiter in late) {
            if (count <= maxLateRequests && bytes <= maxLateBytes) break
            bytes -= waiter.responseBytes
            count--
            discardLocked(waiter)
        }
    }

    internal val pendingCount get() = synchronized(lock) { pruneLocked(); pending.values.count { it.active } }
    internal val lateCount get() = synchronized(lock) { pruneLocked(); pending.values.count { !it.active } }
    internal val lateBytes get() = synchronized(lock) { pruneLocked(); pending.values.filter { !it.active }.sumOf { it.responseBytes } }

    companion object {
        private val SELECTION = listOf("mode", "after_sequence", "evidence_id", "sha256", "page_index", "inline_page_bytes")
        private val expiryExecutor = ScheduledThreadPoolExecutor(1) { runnable ->
            Thread(runnable, "galaxyssi-evidence-correlation-expiry").apply { isDaemon = true }
        }.apply { removeOnCancelPolicy = true }
    }
}
