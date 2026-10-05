package com.galaxyssi.chat.voice.modelstream

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.UUID

/** Host-only receipts. No prompt, response text, URL, credential or tool argument is retained. */
fun interface ModelCallAuditSink {
    fun write(receipt: JSONObject)
    /** Experimental accounting may require one HTTP request per durable admission. */
    fun singleHttpRequest(): Boolean = false
}

class ModelCallAdmissionDenied(val reason: String) : IllegalStateException("Trial admission denied: $reason") {
    companion object { const val CODE = "TRIAL_ADMISSION_DENIED" }
}

internal class ModelCallAccounting(
    private val request: ModelStreamRequest,
    private val sink: ModelCallAuditSink,
    private val elapsed: () -> Long = { System.nanoTime() / 1_000_000L },
    private val wall: () -> Long = System::currentTimeMillis,
    callId: String = UUID.randomUUID().toString(),
    singleHttpRequest: Boolean = false
) {
    private val startedElapsed = elapsed()
    private val issues = linkedSetOf<String>()
    private var reportedModel: String? = null
    private var responseId: String? = null
    private var usage: JSONObject? = null
    private var status = "interrupted"
    private var errorCode: String? = null
    private var httpStatus: Int? = null
    private var providerTerminal = false
    private var finished = false
    private val requestBody = runCatching { JSONObject(request.bodyJson) }.getOrNull()
    private val initial = JSONObject().put("format", "galaxyssi.model-call.v1")
        .put("call_id", callId).put("request_id", request.requestId)
        .put("provider", request.provider.name).put("transport", request.transport.name)
        .put("requested_model", identifier(requestBody?.opt("model")) ?: JSONObject.NULL)
        .put("request_sha256", sha256(request.bodyJson)).put("started_at", wall())
        .put("status", "started").put("cost_micros", JSONObject.NULL)
        .put("single_http_request", singleHttpRequest)
        .put("request_controls", requestControls(requestBody))
        .put("cost_status", "not_measured").put("tokens_complete", false)

    fun begin() { sink.write(JSONObject(initial.toString())) }

    fun observe(data: String) {
        if (finished) return
        if (data.trim() == "[DONE]") { providerTerminal = true; return }
        val root = runCatching { JSONObject(data) }.getOrNull() ?: return
        if (request.transport == ModelStreamTransport.COMPLETE_JSON || root.optString("type") == "response.completed") {
            providerTerminal = true
        }
        // Other providers have different cache/reasoning semantics; never label them as OpenAI totals.
        if (request.provider != ModelStreamProvider.OPENAI_COMPATIBLE) {
            issues += "unsupported_usage_schema"
            return
        }
        val value = root.optJSONObject("response") ?: root
        identifier(value.opt("model"))?.let {
            if (reportedModel != null && reportedModel != it) issues += "model_identity_changed"
            reportedModel = it
        }
        identifier(value.opt("id"))?.let {
            if (responseId != null && responseId != it) issues += "response_identity_changed"
            responseId = it
        }
        val reported = value.optJSONObject("usage") ?: run {
            if (value.has("usage") && !value.isNull("usage")) issues += "invalid_usage_object"
            return
        }
        val normalized = JSONObject()
        fun count(label: String, vararg values: Any?): Long? {
            val supplied = values.filter { it != null && it != JSONObject.NULL }
            val parsed = supplied.map { strictCount(it) }
            if (parsed.any { it == null } || parsed.filterNotNull().distinct().size > 1) {
                issues += "invalid_$label"
                return null
            }
            return parsed.firstOrNull()
        }
        val input = count("input_tokens", reported.opt("prompt_tokens"), reported.opt("input_tokens"))
        val output = count("output_tokens", reported.opt("completion_tokens"), reported.opt("output_tokens"))
        val total = count("total_tokens", reported.opt("total_tokens"))
        val cached = count("cached_input_tokens", reported.optJSONObject("prompt_tokens_details")?.opt("cached_tokens"),
            reported.optJSONObject("input_tokens_details")?.opt("cached_tokens"), reported.opt("prompt_cache_hit_tokens"))
        val reasoning = count("reasoning_output_tokens", reported.optJSONObject("completion_tokens_details")?.opt("reasoning_tokens"),
            reported.optJSONObject("output_tokens_details")?.opt("reasoning_tokens"))
        val sum = if (input != null && output != null && input <= Long.MAX_VALUE - output) input + output else null
        if (input != null && output != null && sum == null) issues += "token_sum_overflow"
        if (total != null && sum != null && total != sum) issues += "total_tokens_mismatch"
        if (cached != null && input != null && cached > input) issues += "cache_exceeds_input"
        if (reasoning != null && output != null && reasoning > output) issues += "reasoning_exceeds_output"
        normalized.put("input_tokens", input ?: JSONObject.NULL).put("output_tokens", output ?: JSONObject.NULL)
            .put("reported_total_tokens", total ?: JSONObject.NULL).put("total_tokens", sum ?: JSONObject.NULL)
            .put("cached_input_tokens", cached ?: JSONObject.NULL).put("reasoning_output_tokens", reasoning ?: JSONObject.NULL)
        // Provider chunks are per-request snapshots, not additive deltas.
        usage = normalized
    }

    fun event(event: ModelStreamEvent) {
        when (event) {
            is ModelStreamEvent.Connected -> httpStatus = event.httpStatus
            is ModelStreamEvent.Completed -> status = "completed"
            is ModelStreamEvent.Failed -> {
                status = if (event.error.code == "CANCELLED") "cancelled" else "failed"
                errorCode = identifier(event.error.code)
            }
            else -> Unit
        }
    }

    fun cancelled() { status = "cancelled" }

    fun finish(httpAttempts: Long = 1L) {
        if (finished) return
        finished = true
        if (httpAttempts != 1L) issues += "http_attempt_count_not_one"
        val tokens = usage ?: JSONObject()
        val complete = status == "completed" && providerTerminal && issues.isEmpty() &&
            !tokens.isNull("input_tokens") && !tokens.isNull("output_tokens") && !tokens.isNull("total_tokens")
        sink.write(JSONObject(initial.toString()).put("status", status).put("finished_at", wall())
            .put("elapsed_ms", (elapsed() - startedElapsed).coerceAtLeast(0L))
            .put("reported_model", reportedModel ?: JSONObject.NULL).put("response_id", responseId ?: JSONObject.NULL)
            .put("usage", tokens).put("tokens_complete", complete).put("issues", JSONArray(issues.toList()))
            .put("http_request_attempts", httpAttempts)
            .put("provider_terminal_observed", providerTerminal).put("http_status", httpStatus ?: JSONObject.NULL)
            .put("error_code", errorCode ?: JSONObject.NULL))
    }

    companion object {
        private fun requestControls(body: JSONObject?): JSONObject {
            if (body == null) return JSONObject().put("types_valid", false)
            return JSONObject().apply {
                var valid = true
                listOf("max_tokens", "temperature", "top_p").forEach { key ->
                    val value = body.opt(key)
                    if (value != null && value != JSONObject.NULL && value !is Number) valid = false
                    put(key, if (value is Number) value else JSONObject.NULL)
                }
                val effort = body.opt("reasoning_effort")
                val knownEffort = effort in setOf("none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra")
                if (effort != null && effort != JSONObject.NULL && !knownEffort) valid = false
                put("reasoning_effort", if (knownEffort) effort else JSONObject.NULL)
                val thinking = body.optJSONObject("thinking")?.opt("type")
                if (body.has("thinking") && thinking !in setOf("enabled", "disabled")) valid = false
                put("thinking_mode", if (thinking in setOf("enabled", "disabled")) thinking else JSONObject.NULL)
                if (body.has("tools") && body.optJSONArray("tools") == null) valid = false
                put("tool_definitions", body.optJSONArray("tools")?.length() ?: if (body.has("tools")) JSONObject.NULL else 0)
                put("types_valid", valid)
            }
        }

        private fun identifier(value: Any?): String? = (value as? String)?.takeIf {
            it.isNotBlank() && it.length <= 256 && it.all { ch -> ch.isLetterOrDigit() || ch in "-_./:" }
        }
        private fun strictCount(value: Any?): Long? = when (value) {
            is Int -> value.toLong().takeIf { it >= 0 }
            is Long -> value.takeIf { it >= 0 }
            else -> null
        }
        private fun sha256(value: String) = MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }
    }
}
