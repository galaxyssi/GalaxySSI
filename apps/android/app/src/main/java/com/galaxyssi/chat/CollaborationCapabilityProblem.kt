package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Describe observable failures without pretending an error code identifies a capability gap. */
internal object CollaborationCapabilityProblem {
    const val FIELD = "host_problem"

    fun describe(output: String, status: String, origin: CollaborationEvidenceOrigin): JSONObject? {
        if (status != "failed") return null
        val root = runCatching { JSONObject(output) }.getOrNull()
        val signals = JSONArray()
        fun signal(value: JSONObject?, key: String, path: String) {
            val scalar = value?.opt(key)
            if (scalar is String || scalar is Boolean || scalar is Number) {
                signals.put(JSONObject().put("path", path).put("value", scalar.toString().take(160)))
            }
        }
        signal(root, "status", "/status")
        signal(root?.optJSONObject("error"), "code", "/error/code")
        signal(root?.optJSONObject("error"), "retryable", "/error/retryable")
        signal(root?.optJSONObject("verification"), "status", "/verification/status")
        if (origin == CollaborationEvidenceOrigin.DESKTOP_CODEX_TOOL) {
            val item = runCatching { JSONObject(root!!.getString("original_json"))
                .getJSONObject("observation").getJSONObject("item") }.getOrNull()
            signal(item, "status", "/original_json/observation/item/status")
            signal(item, "exitCode", "/original_json/observation/item/exitCode")
            signal(item, "isError", "/original_json/observation/item/isError")
        }
        return JSONObject().put("format", "galaxyssi.capability-problem.v1")
            .put("observed_outcome", status).put("signals", signals)
            .put("signal_sha256", AgentNativeJsonCodec.sha256(signals.toString()))
            .put("output_sha256", AgentNativeJsonCodec.sha256(output))
            .put("cause", "not_diagnosed").put("resolved", false)
            .put("guidance", "Read the original source; distinguish knowledge/tool/method/verification gaps from environment or authorization. " +
                "Propose competing explanations and an authorized discriminating probe. A failed tool is not proof of a missing capability.")
    }
}
