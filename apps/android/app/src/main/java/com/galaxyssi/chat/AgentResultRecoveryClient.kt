package com.galaxyssi.chat

import java.io.ByteArrayOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import com.galaxyssi.chat.metrics.AgentRecoveryTiming
import kotlinx.coroutines.CancellationException

/** Pulls one canonical reply in bounded pages; it never executes or resumes a tool. */
internal class AgentResultRecoveryClient {
    private data class Pending(val desktop: String, val identity: List<String>, val generation: Long, val page: Int,
        val result: CompletableDeferred<JSONObject> = CompletableDeferred())
    private val pending = ConcurrentHashMap<String, Pending>()

    suspend fun fetch(desktop: String, fields: JSONObject, timeoutMillis: Long = 8_000L,
        stillPending: () -> Boolean = { true }, checkpoint: AgentResultPageCheckpoint? = null,
        timing: AgentRecoveryTiming? = null,
        firstPage: JSONObject? = null,
        publish: (JSONObject) -> Boolean): JSONObject? {
        var seededDigest: String? = null
        var invalid = false
        val result = fetchAttempt(desktop, fields, timeoutMillis, stillPending, checkpoint, timing, firstPage,
            seedUsed = { seededDigest = it }, invalid = { invalid = true }, publish = publish)
        // Retry a definitively invalid optional seed once, never discard checkpoints on a timeout.
        if (result == null && invalid && seededDigest != null && stillPending()) {
            checkpoint?.clear(requireNotNull(seededDigest))
            return fetchAttempt(desktop, fields, timeoutMillis, stillPending, checkpoint, timing, null,
                seedUsed = {}, invalid = {}, publish = publish)
        }
        return result
    }

    private suspend fun fetchAttempt(desktop: String, fields: JSONObject, timeoutMillis: Long,
        stillPending: () -> Boolean, checkpoint: AgentResultPageCheckpoint?, timing: AgentRecoveryTiming?,
        firstPage: JSONObject?, seedUsed: (String) -> Unit, invalid: () -> Unit,
        publish: (JSONObject) -> Boolean): JSONObject? {
        fun invalidResult(): JSONObject? { invalid(); return null }
        val expected = identity(fields)
        val version = AgentRemoteOutcomeCodec.version(fields) ?: return null
        require(desktop.isNotBlank() && expected.all { it.isNotBlank() && it.length <= 200 })
        if (GalaxySSITransportPrivacyPolicy.isLocalOnly(fields)) return null
        val bytes = WipeableBuffer()
        val span = timing?.begin(fields.optString("task_id"), "body")
        try {
            var manifest = checkpoint?.manifest()
            var digest = manifest?.digest.orEmpty()
            var total = manifest?.bytes ?: -1L
            var count = manifest?.pages ?: 1
            var page = 0
            while (page < count) {
                if (!stillPending()) return null
                val cached = manifest?.let { checkpoint?.read(it, page) }
                if (cached != null) {
                    val valid = try { cached.size == manifest!!.pageBytes(page) } finally { cached.fill(0) }
                    if (!valid) { checkpoint?.clear(digest); return null }
                    page++
                    continue
                }
                var decoded = if (page == 0 && firstPage != null &&
                    AgentResultRecoveryPageCodec.inlineMatches(firstPage, desktop, fields)) {
                    AgentResultRecoveryPageCodec.decode(firstPage, 0)
                } else null
                if (decoded != null && manifest != null && decoded.manifest != manifest) {
                    decoded.close(); decoded = null
                }
                if (decoded != null) seedUsed(decoded.manifest.digest)
                else {
                    val response = query(desktop, fields, page, digest, timeoutMillis, timing, publish) ?: return null
                    decoded = AgentResultRecoveryPageCodec.decode(response, page) ?: return invalidResult()
                }
                decoded.use { verified ->
                    val observed = verified.manifest
                    if (manifest == null) {
                        manifest = observed; digest = observed.digest; total = observed.bytes; count = observed.pages
                    } else if (manifest != observed) return invalidResult()
                    if (!stillPending()) return null
                    if (checkpoint != null) {
                        val saved = timing?.begin(fields.optString("task_id"), "checkpoint")
                        try {
                            if (!checkpoint.write(requireNotNull(manifest), page, verified.bytes)) return null
                            saved?.outcome = "completed"
                        } finally { saved?.close() }
                    } else bytes.write(verified.bytes)
                }
                page++
            }
            if (!stillPending()) return null
            if (checkpoint != null) {
                for (index in 0 until count) {
                    if (!stillPending()) return null
                    val chunk = checkpoint.read(requireNotNull(manifest), index) ?: return null
                    try { bytes.write(chunk) } finally { chunk.fill(0) }
                }
            }
            val complete = bytes.toByteArray()
            try {
                if (complete.size.toLong() != total || sha256(complete) != digest) {
                    checkpoint?.clear(digest)
                    return invalidResult()
                }
                val result = runCatching { JSONObject(String(complete, Charsets.UTF_8)) }.getOrNull()
                if (result == null || identity(result) != expected || result.optString("type") != "text" ||
                    result.optString("task_status") !in AgentRemoteOutcomeCodec.TERMINAL ||
                    AgentRemoteOutcomeCodec.version(result)?.generation != version.generation ||
                    (fields.optString("expected_status").isNotBlank() &&
                        fields.optString("expected_status") != result.optString("task_status")) ||
                    (result.optString("content").isBlank() && result.optJSONObject("rich_output") == null &&
                        result.optString("task_status") !in AgentRemoteOutcomeCodec.FAILURES)) {
                    checkpoint?.clear(digest)
                    return invalidResult()
                }
                val recovered = result.put("result_recovery", JSONObject().put("sha256", digest))
                span?.outcome = "completed"
                return recovered
            } finally { complete.fill(0) }
        } catch (cancelled: CancellationException) {
            span?.outcome = "cancelled"
            throw cancelled
        } finally { bytes.wipe(); span?.close() }
    }

    private suspend fun query(desktop: String, fields: JSONObject, page: Int, digest: String,
        timeoutMillis: Long, timing: AgentRecoveryTiming?, publish: (JSONObject) -> Boolean): JSONObject? {
        val nonce = UUID.randomUUID().toString()
        val generation = requireNotNull(AgentRemoteOutcomeCodec.version(fields)).generation
        val request = Pending(desktop, identity(fields), generation, page)
        pending[nonce] = request
        val span = timing?.begin(fields.optString("task_id"), "page")
        try {
            val payload = JSONObject().apply { FIELDS.forEach { put(it, fields.optString(it)) } }
                .put("type", "agent_task_result_page_request")
                .put("request_id", nonce).put("page_index", page).put("sha256", digest)
                .put("desktop_id", desktop)
                .put("execution_generation", generation)
            if (!publish(payload)) return null
            val response = withTimeoutOrNull(timeoutMillis) { request.result.await() }
            span?.outcome = if (response == null) "timed_out"
                else if (response.optString("status") == "ready") "completed" else "failed"
            return response
        } catch (cancelled: CancellationException) {
            span?.outcome = "cancelled"
            throw cancelled
        } finally { pending.remove(nonce, request); request.result.cancel(); span?.close() }
    }

    fun receive(payload: JSONObject, authenticatedDesktop: String): Boolean {
        val request = pending[payload.optString("request_id")] ?: return false
        if (payload.optString("type") != "agent_task_result_page" || authenticatedDesktop != request.desktop ||
            AgentRemoteOutcomeCodec.version(payload)?.generation != request.generation ||
            identity(payload) != request.identity || payload.optInt("page_index", -1) != request.page) return false
        return request.result.complete(payload)
    }

    internal val pendingCount: Int get() = pending.size

    private class WipeableBuffer : ByteArrayOutputStream() {
        override fun write(bytes: ByteArray, offset: Int, length: Int) {
            val required = count.toLong() + length
            require(required <= Int.MAX_VALUE - 8L)
            if (required > buf.size) {
                val previous = buf
                buf = previous.copyOf(maxOf(required, minOf((Int.MAX_VALUE - 8L), previous.size.toLong() * 2)).toInt())
                previous.fill(0)
            }
            super.write(bytes, offset, length)
        }
        fun wipe() { buf.fill(0); reset() }
    }

    companion object {
        const val PAGE_BYTES = 16 * 1024
        val FIELDS = listOf("client_route_id", "conversation_id", "task_id", "turn_id", "contact_id",
            "source_message_id", "agent_id")
        fun identity(value: JSONObject): List<String> = FIELDS.map { value.optString(it) }
        fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it.toInt() and 255) }
    }
}
