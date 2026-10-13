package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Opaque provider-owned assistant state. It belongs in encrypted journals, never UI text. */
data class AgentProviderContinuation private constructor(
    val provider: AgentModelToolProvider,
    private val payload: String,
    private val binding: String,
    private val route: String = ""
) {
    internal val estimatedTokens: Int get() = ConversationContextCompactor.estimateTokens(payload) + 6

    internal fun bindRoute(value: String) = copy(route = value)
    internal fun matchesRoute(value: String): Boolean = route == value

    internal fun forHistory(response: AgentModelResponse, admitted: List<AgentModelToolCall>): AgentProviderContinuation {
        validate(response.assistantText, response.toolCalls)
        if (shape(response.toolCalls) != shape(admitted)) fail("continuation_calls_changed")
        return copy(binding = fingerprint(response.assistantText, admitted))
    }

    internal fun encode(message: AgentModelMessage, target: AgentModelToolProvider): JSONObject? {
        if (provider != target) return null
        validate(message.text, message.toolCalls)
        return JSONObject(payload)
    }

    internal fun record(): AgentNativeJsonObject = mapOf("provider" to provider.name,
        "payload" to payload, "binding" to binding, "route" to route)

    private fun validate(text: String, calls: List<AgentModelToolCall>) {
        if (binding != fingerprint(text, calls)) fail("continuation_history_changed")
    }

    override fun toString(): String = "AgentProviderContinuation(provider=$provider)"

    companion object {
        internal fun routeFingerprint(provider: AgentModelToolProvider, endpoint: String, model: String,
            credential: String): String = AgentNativeJsonCodec.sha256(mapOf("provider" to provider.wireValue,
            "endpoint" to endpoint, "model" to model, "credential" to AgentNativeJsonCodec.sha256(credential)))

        internal fun capture(provider: AgentModelToolProvider, payload: JSONObject,
            response: AgentModelResponse): AgentProviderContinuation? {
            val needed = when (provider) {
                AgentModelToolProvider.OPENAI_COMPATIBLE -> payload.has("reasoning_content") && !payload.isNull("reasoning_content")
                AgentModelToolProvider.ANTHROPIC -> objects(payload.optJSONArray("content")).any {
                    it.optString("type") in setOf("thinking", "redacted_thinking") }
                AgentModelToolProvider.GEMINI -> objects(payload.optJSONArray("parts")).any {
                    it.has("thoughtSignature") || it.has("thought_signature") || it.optBoolean("thought") }
            }
            if (!needed) return null
            return AgentProviderContinuation(provider, payload.toString(), fingerprint(response.assistantText, response.toolCalls))
        }

        internal fun restore(record: Map<*, *>): AgentProviderContinuation = try {
            AgentProviderContinuation(AgentModelToolProvider.valueOf(record["provider"] as String),
                record["payload"] as String, record["binding"] as String, record["route"] as String)
        } catch (error: Exception) { throw AgentModelLoopRecoveryException("model_loop_continuation_invalid", error) }

        internal fun forRoute(messages: List<AgentModelMessage>, route: String): List<AgentModelMessage> = messages.map {
            if (it.continuation?.matchesRoute(route) == false) it.copy(continuation = null) else it
        }

        private fun fingerprint(text: String, calls: List<AgentModelToolCall>) = AgentNativeJsonCodec.sha256(
            mapOf("text" to text, "calls" to shape(calls), "ids" to calls.map { it.callId }))

        private fun shape(calls: List<AgentModelToolCall>) = calls.map {
            mapOf("tool" to it.toolId, "arguments" to it.arguments, "version" to it.toolVersion) }

        internal fun objects(array: JSONArray?): List<JSONObject> = if (array == null) emptyList() else
            (0 until array.length()).map { array.getJSONObject(it) }

        private fun fail(code: String): Nothing = throw AgentModelToolProtocolException(code, "Provider continuation no longer matches its assistant message")
    }
}

/** Runtime admission IDs may differ from provider IDs; only the transcript uses the original IDs. */
internal class AgentProviderTranscript(messages: List<AgentModelMessage>, private val provider: AgentModelToolProvider) {
    private data class WireCall(val id: String?, val name: String)
    private val replies = mutableMapOf<String, WireCall>()
    private val assistants = java.util.IdentityHashMap<AgentModelMessage, JSONObject>()

    init {
        messages.forEach { message ->
            val payload = assistant(message) ?: return@forEach
            val calls = when (provider) {
                AgentModelToolProvider.OPENAI_COMPATIBLE -> AgentProviderContinuation.objects(payload.optJSONArray("tool_calls"))
                AgentModelToolProvider.ANTHROPIC -> AgentProviderContinuation.objects(payload.optJSONArray("content"))
                    .filter { it.optString("type") == "tool_use" }
                AgentModelToolProvider.GEMINI -> AgentProviderContinuation.objects(payload.optJSONArray("parts"))
                    .mapNotNull { it.optJSONObject("functionCall") }
            }
            if (calls.size != message.toolCalls.size) throw AgentModelToolProtocolException("continuation_calls_changed", "Provider call count changed")
            calls.zip(message.toolCalls).forEach { (wire, native) ->
                val name = if (provider == AgentModelToolProvider.OPENAI_COMPATIBLE) wire.getJSONObject("function").getString("name") else wire.getString("name")
                replies[native.callId] = WireCall(if (wire.has("id") && !wire.isNull("id")) wire.getString("id") else null, name)
            }
        }
    }

    fun assistant(message: AgentModelMessage): JSONObject? = assistants[message] ?: message.continuation?.encode(message, provider)
        ?.also { assistants[message] = it }
    fun replyId(id: String): String? = if (replies.containsKey(id)) replies.getValue(id).id else id
    fun replyName(result: AgentModelToolResultContent): String = replies[result.callId]?.name ?: AgentModelToolWireNames.name(result.toolId)
}
