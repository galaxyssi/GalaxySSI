package com.galaxyssi.chat

/** Repairs transcript identifiers only; rejected calls must never reach an executor. */
internal object AgentModelCallAdmission {
    data class Rejection(val originalId: String, val code: String)
    data class Result(val calls: List<AgentModelToolCall>, val rejections: Map<String, Rejection>)

    fun admit(calls: List<AgentModelToolCall>, existingIds: Set<String>, round: Int): Result {
        val seen = existingIds.toMutableSet()
        val reserved = (existingIds + calls.map { it.callId }).toMutableSet()
        val rejected = linkedMapOf<String, Rejection>()
        val admitted = calls.mapIndexed { index, call ->
            val code = when {
                call.callId.isBlank() || call.callId.length > 160 -> "invalid_tool_call_id"
                !seen.add(call.callId) -> "tool_call_id_reused"
                else -> null
            }
            if (code == null) call else {
                var salt = 0
                var id: String
                do {
                    id = "rejected_" + AgentNativeJsonCodec.sha256(mapOf(
                        "round" to round, "index" to index, "original" to call.callId, "salt" to salt++))
                } while (!reserved.add(id))
                seen.add(id)
                rejected[id] = Rejection(call.callId.take(160), code)
                call.copy(callId = id)
            }
        }
        return Result(admitted, rejected)
    }
}
