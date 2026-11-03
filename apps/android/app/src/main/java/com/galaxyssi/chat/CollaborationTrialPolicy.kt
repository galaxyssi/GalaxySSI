package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.ModelCallAdmissionDenied
import org.json.JSONObject

/** Host-configured experiment only. Admission counts are not token or billing limits. */
internal data class CollaborationTrialPolicy(
    val protocolSha256: String,
    val targetId: String,
    val requestedModel: String,
    val maxRequestAdmissions: Int,
    val admitUntilMillis: Long,
    val profile: CollaborationTrialProfile? = null
) {
    init {
        require(Regex("[a-f0-9]{64}").matches(protocolSha256))
        require(targetId.isNotBlank() && requestedModel.isNotBlank() && requestedModel.length <= 256)
        require(maxRequestAdmissions > 0 && admitUntilMillis > 0)
    }

    fun json() = JSONObject().put("format", "galaxyssi.trial-admission.v1")
        .put("protocol_sha256", protocolSha256).put("target_id", targetId).put("requested_model", requestedModel)
        .put("max_request_admissions", maxRequestAdmissions).put("admit_until", admitUntilMillis)
        .apply { profile?.let { put("text_profile", it.json()) } }

    fun requireTarget(target: String, adapterType: String) {
        if (target != targetId || adapterType != "cloud-model-api") deny("unmetered_or_changed_execution_target")
    }

    fun requireRequest(receipt: JSONObject) {
        if (receipt.opt("single_http_request") != true) deny("single_http_request_not_enforced")
        if (receipt.optString("provider") != "OPENAI_COMPATIBLE" ||
            receipt.optString("transport") !in setOf("SSE", "COMPLETE_JSON") ||
            receipt.optString("requested_model") != requestedModel) deny("unmetered_or_changed_model")
        profile?.requireControls(receipt)
    }

    companion object {
        const val REQUIRED_PARAMETER = "_galaxyssi_trial_admission_required"
        fun from(json: JSONObject): CollaborationTrialPolicy {
            require(json.getString("format") == "galaxyssi.trial-admission.v1")
            val cap = strictLong(json.get("max_request_admissions"))
            require(cap <= Int.MAX_VALUE)
            return CollaborationTrialPolicy(json.getString("protocol_sha256"), json.getString("target_id"),
                json.getString("requested_model"), cap.toInt(), strictLong(json.get("admit_until")),
                if (json.has("text_profile")) CollaborationTrialProfile.from(json.getJSONObject("text_profile")) else null)
        }
        fun strictLong(value: Any): Long = when (value) {
            is Int -> value.toLong()
            is Long -> value
            else -> error("Trial admission counter is not an integer")
        }.also { require(it >= 0) }
        fun deny(reason: String): Nothing = throw ModelCallAdmissionDenied(reason)
    }
}
