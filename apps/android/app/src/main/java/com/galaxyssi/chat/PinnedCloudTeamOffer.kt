package com.galaxyssi.chat

import com.galaxyssi.chat.voice.modelstream.AssembledToolCall
import com.galaxyssi.chat.voice.modelstream.ModelStreamProvider
import com.galaxyssi.chat.voice.modelstream.ModelStreamRequest
import com.galaxyssi.chat.voice.modelstream.ToolCallPayload
import org.json.JSONObject

/** A terminal answer encoded on the provider's native function channel. Never a callable tool. */
internal object PinnedCloudTeamOffer {
    const val NAME = "answer_with_optional_team_review"
    const val INVALID = "INVALID_TEAM_REVIEW_ANSWER"
    private val limits = McpJsonLimits(maxMessageBytes = 64_000, maxStringLength = 8000,
        maxDepth = 2, maxNodes = 3, maxContainerEntries = 2)

    class Frames {
        private var id = ""
        private var valid = true
        val singleNativeSlot get() = valid && id.isNotBlank()

        fun observe(payload: ToolCallPayload) {
            valid = valid && payload.singleNativeFunction && payload.index == 0 &&
                (id.isEmpty() || payload.callId.isEmpty() || payload.callId == id)
            if (id.isEmpty()) id = payload.callId
        }
    }

    fun advertise(request: ModelStreamRequest): ModelStreamRequest {
        if (request.provider != ModelStreamProvider.OPENAI_COMPATIBLE) return request
        val body = JSONObject(request.bodyJson)
        val tools = body.optJSONArray("tools") ?: return request
        if (tools.length() == 0 || body.optString("tool_choice") != "auto") return request
        tools.put(JSONObject("""{
            "type":"function","function":{
            "name":"$NAME","description":"Optional FINAL answer format, not an action. Only for a self-contained textual task where independent review could materially change the answer. Give the complete ordinary answer now, in the user's language. No other calls or message text. Do not use for private, context-dependent or solo requests, or when actions or research are needed. The phone may offer review; no work has started.",
            "parameters":{"type":"object","properties":{"answer":{"type":"string"},
            "propose_team_review":{"type":"boolean","enum":[true]}},"required":["answer","propose_team_review"],
            "additionalProperties":false}}}"""))
        return request.copy(bodyJson = body.toString())
    }

    fun answer(calls: List<AssembledToolCall>, singleNativeSlot: Boolean, finish: String?, hasText: Boolean): String? {
        val call = calls.singleOrNull() ?: return null
        if (!singleNativeSlot || hasText || finish != "tool_calls" || call.name != NAME ||
            call.argumentsJson.length > limits.maxMessageBytes) return null
        val obj = try { McpJson.parseObject(call.argumentsJson, limits) } catch (_: McpJsonException) { return null }
        return obj.string("answer")?.takeIf { it.isNotBlank() && obj.entries.size == 2 &&
            obj.boolean("propose_team_review") == true }
    }
}
