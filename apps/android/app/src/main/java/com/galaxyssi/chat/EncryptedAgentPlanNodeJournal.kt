package com.galaxyssi.chat

import android.content.Context
import org.json.JSONObject

/** Per-attempt observations share the encrypted Run ledger, not the UI/session blob. */
internal class EncryptedAgentPlanNodeJournal(private val store: AgentRunEventStore) : AgentPlanNodeJournal {
    constructor(context: Context) : this(AgentRunEventStore(context))

    override fun start(key: AgentPlanNodeKey) {
        check(store.appendInitialIfAbsent(event(key, "started", AgentRunControlEventType.RUN_STARTED,
            emptyMap()))) { "Plan node attempt was already dispatched; recover its observation instead" }
    }

    override fun record(key: AgentPlanNodeKey, observation: AgentPlanNodeObservation) {
        require(observation.result.actionId == key.actionId) { "Plan result belongs to another action" }
        val previous = store.latestEvent(runId(key)) ?: error("Plan node has no durable dispatch")
        val phase = if (observation.verified) "verified" else "returned"
        val encoded = encode(observation)
        if (previous.payload["stage"] == phase) {
            check(encode(requireNotNull(read(key))) == encoded) { "Plan observation changed after commit" }
            return
        }
        check(previous.type == AgentRunControlEventType.RUN_STARTED ||
            (observation.verified && previous.payload["stage"] == "returned")) {
            "Plan observation cannot move backwards"
        }
        val chunks = buildList {
            var start = 0
            while (start < encoded.length) {
                var end = minOf(start + 24 * 1024, encoded.length)
                if (end < encoded.length && encoded[end - 1].isHighSurrogate() && encoded[end].isLowSurrogate()) end--
                add(encoded.substring(start, end))
                start = end
            }
        }
        val rows = chunks.mapIndexed { index, text -> event(key, "$phase:$index",
            AgentRunControlEventType.CHECKPOINT_SAVED, mapOf("chunk_stage" to phase, "index" to index, "chunk" to text)) }
        store.appendNextAll(rows + event(key, phase,
            if (observation.verified) AgentRunControlEventType.RUN_COMPLETED else AgentRunControlEventType.CHECKPOINT_SAVED,
            mapOf("stage" to phase, "chunks" to chunks.size, "sha256" to AgentNativeJsonCodec.sha256(encoded))))
        check(encode(requireNotNull(read(key))) == encoded) { "Plan observation was not committed" }
    }

    override fun read(key: AgentPlanNodeKey): AgentPlanNodeObservation? {
        val last = store.latestEvent(runId(key)) ?: return null
        require(last.payload["identity_sha256"] == AgentNativeJsonCodec.sha256(key.identity()))
        if (last.type == AgentRunControlEventType.RUN_STARTED) return null
        val stage = last.payload["stage"] as? String ?: error("Plan observation is incomplete")
        check(stage == "returned" || stage == "verified")
        val count = (last.payload["chunks"] as? Number)?.toInt() ?: error("Plan chunk count is missing")
        var sequence = 0L
        var index = 0
        val encoded = buildString {
            while (sequence < last.sequence) {
                val page = store.eventsPage(last.runId, sequence, 64)
                check(page.isNotEmpty()) { "Plan observation chunks are missing" }
                page.filter { it.payload["chunk_stage"] == stage }.forEach { row ->
                    check((row.payload["index"] as? Number)?.toInt() == index++) { "Plan chunks are unordered" }
                    append(row.payload["chunk"] as? String ?: error("Plan chunk is missing"))
                }
                sequence = page.last().sequence
            }
        }
        check(index == count && count > 0 && AgentNativeJsonCodec.sha256(encoded) == last.payload["sha256"])
        val body = JSONObject(encoded)
        val result = body.getJSONObject("result")
        val metadata = result.getJSONObject("metadata")
        return AgentPlanNodeObservation(AgentActionResult(result.getString("action_id"),
            result.getBoolean("success"), result.getString("message"),
            metadata.keys().asSequence().associateWith { metadata.getString(it) }),
            body.getBoolean("verified"), body.getString("evidence")).also {
            check(it.result.actionId == key.actionId && it.verified == (stage == "verified"))
        }
    }

    private fun encode(observation: AgentPlanNodeObservation): String = AgentNativeJsonCodec.stringify(mapOf(
        "result" to mapOf("action_id" to observation.result.actionId, "success" to observation.result.success,
            "message" to observation.result.message, "metadata" to observation.result.metadata),
        "verified" to observation.verified, "evidence" to observation.evidence))

    private fun event(key: AgentPlanNodeKey, suffix: String, type: AgentRunControlEventType,
        payload: Map<String, Any>): AgentRunControlEvent {
        val run = runId(key)
        return AgentRunControlEvent(eventId = "$run:$suffix", idempotencyKey = "$run:$suffix", runId = run,
            taskId = key.planId, goalId = key.planId, conversationId = key.conversationId,
            clientRouteId = key.sessionId, turnId = key.turnId, actionId = key.actionId,
            messageId = "", agentId = "android-plan-node", deviceId = "local", sequence = 0, type = type,
            payload = payload + mapOf("recovery_mode" to "observation_only",
                "identity_sha256" to AgentNativeJsonCodec.sha256(key.identity())))
    }

    companion object {
        internal fun runId(key: AgentPlanNodeKey) = "plan-node:" + AgentNativeJsonCodec.sha256(key.identity())
    }
}
