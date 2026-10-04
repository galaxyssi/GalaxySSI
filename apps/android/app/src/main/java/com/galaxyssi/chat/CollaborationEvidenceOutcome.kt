package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Interpret explicit outcome fields only; absent or empty errors are not failures. */
internal object CollaborationEvidenceOutcome {
    fun status(output: String): String {
        val parsed = runCatching { JSONObject(output) }.getOrNull() ?: return "unstructured"
        val error = when (val value = parsed.opt("error")) {
            null, JSONObject.NULL -> false
            is Boolean -> value
            is Number -> value.toDouble() != 0.0
            is String -> value.isNotBlank()
            is JSONObject -> value.length() > 0
            is JSONArray -> value.length() > 0
            else -> false
        }
        return if (error || parsed.opt("success") == false || parsed.opt("ok") == false || parsed.opt("isError") == true ||
            parsed.optString("status") in setOf("failed", "error", "cancelled", "timed_out", "unavailable", "rejected", "verification_failed")) "failed"
        else "returned"
    }
}
