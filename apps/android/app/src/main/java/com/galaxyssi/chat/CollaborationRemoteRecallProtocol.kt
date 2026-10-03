package com.galaxyssi.chat

import org.json.JSONObject

/** Wire selectors never carry authority; the authenticated host resolves the member binding. */
internal object CollaborationRemoteRecallProtocol {
    const val CONTRACT = "galaxyssi.collaboration-recall/2"
    const val REQUEST = "collaboration_recall_request"
    const val RESPONSE = "collaboration_recall_result"

    fun valid(request: JSONObject, now: Long): Boolean =
        CollaborationRemoteEvidenceProtocol.validScope(request) && request.opt("type") == REQUEST &&
            request.opt("contract") == CONTRACT &&
            (request.opt("request_id") as? String)?.length in 1..128 &&
            CollaborationRemoteEvidenceProtocol.integer(request, "expires_at")?.let { it > now && it - now <= 60_000 } == true &&
            request.optJSONObject("arguments")?.toString()?.length in 1..4096 &&
            when (request.optString("phase")) {
                "read" -> !request.has("delivery")
                "confirm" -> request.optJSONObject("delivery")?.let {
                    it.length() == 2 && (it.opt("receipt_id") as? String)?.length in 1..128 &&
                        (it.opt("content_sha256") as? String)?.matches(Regex("[a-f0-9]{64}")) == true
                } == true
                else -> false
            }

    fun response(request: JSONObject, result: JSONObject): JSONObject = CollaborationRemoteEvidenceProtocol.scope(request)
        .put("type", RESPONSE).put("contract", CONTRACT).put("request_id", request.getString("request_id"))
        .put("phase", request.getString("phase"))
        .put("result", result)

    fun unavailable() = JSONObject().put("success", false).put("status", "unavailable")
        .put("error", "Assignment is paused, stopped, superseded, unavailable or no longer authorized.")
}
