package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** Indexed, encrypted effect observations in the shared Run Kernel, without TTL eviction. */
class EncryptedAgentNativeToolReplayStore internal constructor(
    private val store: AgentRunEventStore,
    private val legacy: LegacyAgentNativeToolReplayReader? = null
) : AgentNativeToolReplayStore {
    constructor(context: Context) : this(AgentRunEventStore(context), LegacyAgentNativeToolReplayReader(context))

    override fun get(key: AgentNativeToolReplayKey): AgentNativeToolResult? {
        migrate()
        requireBoundLegacy(key)
        return read(key)?.result
    }

    override fun claim(key: AgentNativeToolReplayKey, inputSha256: String, invocationId: String): AgentNativeEffectClaim {
        migrate()
        requireBoundLegacy(key)
        val acquired = store.appendInitialIfAbsent(event(key, "claim", AgentRunControlEventType.RUN_STARTED,
            mapOf("input_sha256" to inputSha256, "owner" to invocationId)))
        return if (acquired) AgentNativeEffectClaim(true, invocationId, inputSha256)
        else requireNotNull(read(key)) { "Native effect claim disappeared" }
    }

    override fun complete(key: AgentNativeToolReplayKey, invocationId: String, result: AgentNativeToolResult) {
        val claim = requireNotNull(read(key)) { "Native effect has no durable claim" }
        require(claim.invocationId == invocationId && result.receipt.invocationId == invocationId &&
            claim.inputSha256 == result.receipt.inputSha256) { "Native effect owner or input changed" }
        if (claim.result != null) {
            require(sameResult(claim.result, result)) { "Native effect outcome changed" }
            return
        }
        writeResult(key, result)
    }

    override fun put(key: AgentNativeToolReplayKey, result: AgentNativeToolResult) {
        migrate()
        require(result.isSuccess) { "Only successful unclaimed results may be cached" }
        requireBoundLegacy(key)
        putObserved(key, result)
    }

    private fun putObserved(key: AgentNativeToolReplayKey, result: AgentNativeToolResult) {
        read(key)?.let { previous ->
            require(previous.result != null && sameResult(previous.result, result)) { "Native effect outcome changed" }
            return
        }
        writeResult(key, result)
    }

    private fun writeResult(key: AgentNativeToolReplayKey, result: AgentNativeToolResult) {
        require(result.receipt.idempotencyKey == key.idempotencyKey && result.provenance.toolId == key.toolId &&
            result.provenance.toolVersion == key.toolVersion) { "Native effect result belongs to another operation" }
        val encoded = result.toJson()
        val chunks = buildList {
            var start = 0
            while (start < encoded.length) {
                var end = minOf(start + CHUNK_CHARS, encoded.length)
                if (end < encoded.length && encoded[end - 1].isHighSurrogate() && encoded[end].isLowSurrogate()) end--
                add(encoded.substring(start, end))
                start = end
            }
        }
        val events = chunks.mapIndexed { index, text ->
            event(key, "result:$index", AgentRunControlEventType.CHECKPOINT_SAVED,
                mapOf("chunk" to text, "index" to index))
        } + event(key, "result", AgentRunControlEventType.RUN_COMPLETED, mapOf(
            "chunks" to chunks.size, "sha256" to AgentNativeJsonCodec.sha256(encoded),
            "input_sha256" to result.receipt.inputSha256, "owner" to result.receipt.invocationId
        ))
        // A reader sees either the prior claim or the entire outcome, never a partial result.
        store.appendNextAll(events)
        check(read(key)?.result?.let { sameResult(it, result) } == true) { "Native effect result was not committed" }
    }

    private fun read(key: AgentNativeToolReplayKey): AgentNativeEffectClaim? {
        val last = store.latestEvent(runId(key)) ?: return null
        require(last.payload["identity_sha256"] == AgentNativeJsonCodec.sha256(key.identity())) {
            "Native effect identity mismatch"
        }
        val owner = last.payload["owner"] as? String ?: error("Native effect owner is missing")
        val input = last.payload["input_sha256"] as? String ?: error("Native effect input digest is missing")
        if (last.type == AgentRunControlEventType.RUN_STARTED) return AgentNativeEffectClaim(false, owner, input)
        check(last.type == AgentRunControlEventType.RUN_COMPLETED) { "Incomplete native effect result" }
        val count = (last.payload["chunks"] as? Number)?.toInt() ?: error("Native effect chunk count is missing")
        check(count > 0) { "Native effect has no result chunks" }
        var sequence = 0L
        var nextIndex = 0
        val encoded = buildString {
            while (sequence < last.sequence) {
                val page = store.eventsPage(last.runId, sequence, 64)
                check(page.isNotEmpty()) { "Native effect journal is incomplete" }
                page.filter { it.type == AgentRunControlEventType.CHECKPOINT_SAVED }.forEach { row ->
                    check((row.payload["index"] as? Number)?.toInt() == nextIndex++) { "Native effect chunks are unordered" }
                    append(row.payload["chunk"] as? String ?: error("Native effect chunk is missing"))
                }
                sequence = page.last().sequence
            }
        }
        check(nextIndex == count && AgentNativeJsonCodec.sha256(encoded) == last.payload["sha256"]) {
            "Native effect result integrity mismatch"
        }
        val result = requireNotNull(JSONObject(encoded).toNativeToolResult()) { "Invalid native effect result" }
        check(result.receipt.invocationId == owner && result.receipt.inputSha256 == input &&
            result.receipt.idempotencyKey == key.idempotencyKey &&
            result.provenance.toolId == key.toolId && result.provenance.toolVersion == key.toolVersion) {
            "Native effect receipt binding mismatch"
        }
        return AgentNativeEffectClaim(false, owner, input, result)
    }

    override fun clear() {
        // Explicit clearing is scoped to this namespace, never unrelated Run history.
        var cursor: Long? = null
        do {
            val page = store.snapshotEventsPage(KIND, cursor, 128)
            store.removeRuns(page.events.map { it.runId }.toSet())
            cursor = page.nextBeforeOrdinal
        } while (cursor != null)
        legacy?.clear()
    }

    private fun migrate() {
        val reader = legacy ?: return
        if (store.latestEvent(MIGRATION_RUN) != null) return
        synchronized(MIGRATION_LOCK) {
            if (store.latestEvent(MIGRATION_RUN) != null) return
            reader.entries().forEach { (key, result) -> putObserved(key, result) }
            store.appendInitialIfAbsent(AgentRunControlEvent(
                eventId = MIGRATION_RUN, idempotencyKey = MIGRATION_RUN, runId = MIGRATION_RUN,
                conversationId = MIGRATION_RUN, messageId = "",
                taskId = MIGRATION_RUN, agentId = "native-effect", deviceId = "local", sequence = 0,
                type = AgentRunControlEventType.RUN_COMPLETED, payload = mapOf("recovery_mode" to "observation_only")
            ))
        }
    }

    private fun requireBoundLegacy(key: AgentNativeToolReplayKey) {
        if (key.scope != AgentNativeEffectScope() && store.latestEvent(runId(key.copy(scope = AgentNativeEffectScope()))) != null) {
            error("legacy_effect_scope_unverified: observe the previous effect before issuing a new scoped operation")
        }
    }

    private fun event(key: AgentNativeToolReplayKey, suffix: String, type: AgentRunControlEventType,
        payload: Map<String, Any>): AgentRunControlEvent {
        val run = runId(key)
        val scope = key.scope
        return AgentRunControlEvent(
            eventId = "$run:$suffix", idempotencyKey = "$run:$suffix", runId = run,
            messageId = "",
            taskId = scope.taskId.ifBlank { scope.sessionId.ifBlank { run } },
            clientRouteId = scope.clientRouteId.ifBlank { "local" },
            conversationId = scope.conversationId.ifBlank { scope.sessionId.ifBlank { run } },
            goalId = scope.goalId.ifBlank { scope.taskId.ifBlank { run } },
            turnId = scope.turnId.ifBlank { run }, actionId = key.idempotencyKey,
            agentId = "native-effect", deviceId = "local", sequence = 0, type = type,
            payload = payload + mapOf("recovery_mode" to "observation_only",
                "identity_sha256" to AgentNativeJsonCodec.sha256(key.identity()), "snapshot_kind" to KIND)
        )
    }

    companion object {
        internal const val KIND = "native_effect"
        private const val CHUNK_CHARS = 24 * 1024
        private const val MIGRATION_RUN = "native-effects:legacy-migration:v1"
        private val MIGRATION_LOCK = Any()
        internal fun runId(key: AgentNativeToolReplayKey) = "native-effect:" + AgentNativeJsonCodec.sha256(key.identity())
        private fun sameResult(first: AgentNativeToolResult, second: AgentNativeToolResult) =
            AgentNativeJsonCodec.sha256(first.toJson()) == AgentNativeJsonCodec.sha256(second.toJson())
    }
}
