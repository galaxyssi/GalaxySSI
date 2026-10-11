package com.galaxyssi.chat

import org.json.JSONObject

/** Correlatable phase observations contain no request arguments, research content or raw peer IDs. */
internal object CollaborationExchangeTrace {
    enum class Stage { ADMISSION, RESOLVED, RESPONSE_READY, REPLAY_SCOPE_CHANGED, AUTHORIZATION_CHANGED,
        RESPONSE_EXPIRED_OR_UNPAIRED, PUBLISH_ACCEPTED, PUBLISH_REJECTED, FAILED }
    private val modes = setOf("goal_contract", "workspace", "evidence", "archive", "evolution", "capabilities",
        "method_history", "evolution_rules", "problems", "numeric_cases", "publish", "list", "status", "validate_assessment")
    private val phases = setOf("read", "confirm", "publish", "list", "status", "validate_assessment")

    fun line(peer: String, request: JSONObject, stage: Stage, elapsedMillis: Long = 0,
             admission: CollaborationExchangeReplay.Outcome? = null): String {
        val token = MqttImmutableContent.hash(JSONObject().put("peer", peer).put("request_id", request.optString("request_id"))).take(16)
        val phase = request.optString("phase").takeIf { it in phases } ?: "unknown"
        val mode = request.optJSONObject("arguments")?.optString("mode")?.takeIf { it in modes } ?: "unknown"
        return "rpc=$token phase=$phase mode=$mode stage=${stage.name.lowercase()} elapsed_ms=${elapsedMillis.coerceAtLeast(0)}" +
            (admission?.let { " admission=${it.name.lowercase()}" } ?: "")
    }
}
