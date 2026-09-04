package com.galaxyssi.chat.voice.modelstream

import org.json.JSONArray
import org.json.JSONObject

internal data class ParsedModelStreamFrame(
    val textDeltas: List<String> = emptyList(),
    val toolDeltas: List<ToolCallPayload> = emptyList(),
    val usage: ModelUsage? = null,
    val finishReason: String? = null,
    val terminal: Boolean = false,
    val error: ModelStreamError? = null,
    val providerSequence: Long? = null
)

internal interface ModelStreamProviderAdapter {
    fun parse(data: String, eventName: String? = null): ParsedModelStreamFrame
    fun parseCompleteJson(data: String): ParsedModelStreamFrame
}

internal object ModelStreamProviderAdapters {
    fun create(provider: ModelStreamProvider): ModelStreamProviderAdapter = when (provider) {
        ModelStreamProvider.OPENAI_COMPATIBLE -> OpenAiModelStreamAdapter()
        ModelStreamProvider.ANTHROPIC -> AnthropicModelStreamAdapter()
        ModelStreamProvider.GEMINI -> GeminiModelStreamAdapter()
    }
}

private class OpenAiModelStreamAdapter : ModelStreamProviderAdapter {
    override fun parse(data: String, eventName: String?): ParsedModelStreamFrame {
        if (data.trim() == "[DONE]") return ParsedModelStreamFrame(terminal = true)
        val json = runCatching { JSONObject(data) }.getOrElse { error ->
            return ParsedModelStreamFrame(
                error = ModelStreamError("INVALID_STREAM_JSON", error.message.orEmpty())
            )
        }
        val type = json.optString("type", eventName.orEmpty())
        if (type == "error" || json.has("error")) return providerError(json)
        if (type == "response.output_text.delta") {
            return ParsedModelStreamFrame(
                textDeltas = listOf(json.optString("delta")),
                providerSequence = json.optionalSequence()
            )
        }
        if (type == "response.function_call_arguments.delta") {
            return ParsedModelStreamFrame(
                toolDeltas = listOf(
                    ToolCallPayload(
                        callId = json.optString("item_id", json.optString("call_id")),
                        index = json.optInt("output_index", 0),
                        nameDelta = json.optString("name"),
                        argumentsDelta = json.optString("delta")
                    )
                ),
                providerSequence = json.optionalSequence()
            )
        }
        if (type == "response.completed") {
            val response = json.optJSONObject("response") ?: json
            return ParsedModelStreamFrame(
                usage = response.optJSONObject("usage")?.openAiUsage(),
                finishReason = response.optString("status").ifBlank { "stop" },
                terminal = true,
                providerSequence = json.optionalSequence()
            )
        }
        val choice = json.optJSONArray("choices")?.optJSONObject(0)
        val delta = choice?.optJSONObject("delta")
        val text = textValue(delta?.opt("content"))
        val toolDeltas = buildList {
            val calls = delta?.optJSONArray("tool_calls") ?: JSONArray()
            for (index in 0 until calls.length()) {
                val call = calls.optJSONObject(index) ?: continue
                val function = call.optJSONObject("function")
                add(
                    ToolCallPayload(
                        callId = call.optString("id"),
                        index = call.optInt("index", index),
                        nameDelta = function?.optString("name").orEmpty(),
                        argumentsDelta = function?.optString("arguments").orEmpty()
                    )
                )
            }
        }
        return ParsedModelStreamFrame(
            textDeltas = listOfNotNull(text.takeIf(String::isNotEmpty)),
            toolDeltas = toolDeltas,
            usage = json.optJSONObject("usage")?.openAiUsage(),
            finishReason = choice?.optString("finish_reason")?.takeIf(String::isNotBlank),
            providerSequence = json.optionalSequence()
        )
    }

    override fun parseCompleteJson(data: String): ParsedModelStreamFrame {
        val json = runCatching { JSONObject(data) }.getOrElse { error ->
            return ParsedModelStreamFrame(error = ModelStreamError("INVALID_RESPONSE_JSON", error.message.orEmpty()))
        }
        if (json.has("error")) return providerError(json)
        val choice = json.optJSONArray("choices")?.optJSONObject(0)
        val message = choice?.optJSONObject("message")
        val text = textValue(message?.opt("content"))
            .ifBlank { choice?.optString("text").orEmpty() }
            .ifBlank { json.optString("output_text") }
        val tools = buildList {
            val calls = message?.optJSONArray("tool_calls") ?: JSONArray()
            for (index in 0 until calls.length()) {
                val call = calls.optJSONObject(index) ?: continue
                val function = call.optJSONObject("function")
                add(
                    ToolCallPayload(
                        call.optString("id"),
                        call.optInt("index", index),
                        function?.optString("name").orEmpty(),
                        function?.optString("arguments").orEmpty()
                    )
                )
            }
        }
        return ParsedModelStreamFrame(
            textDeltas = listOfNotNull(text.takeIf(String::isNotBlank)),
            toolDeltas = tools,
            usage = json.optJSONObject("usage")?.openAiUsage(),
            finishReason = choice?.optString("finish_reason")?.takeIf(String::isNotBlank),
            terminal = true
        )
    }
}

private class AnthropicModelStreamAdapter : ModelStreamProviderAdapter {
    private data class ToolBlock(val id: String, val name: String)
    private val toolBlocks = mutableMapOf<Int, ToolBlock>()

    override fun parse(data: String, eventName: String?): ParsedModelStreamFrame {
        val json = runCatching { JSONObject(data) }.getOrElse { error ->
            return ParsedModelStreamFrame(error = ModelStreamError("INVALID_STREAM_JSON", error.message.orEmpty()))
        }
        val type = json.optString("type", eventName.orEmpty())
        if (type == "error") return providerError(json)
        return when (type) {
            "message_start" -> ParsedModelStreamFrame(
                usage = json.optJSONObject("message")?.optJSONObject("usage")?.anthropicUsage(),
                providerSequence = json.optionalSequence()
            )
            "content_block_start" -> {
                val index = json.optInt("index", 0)
                val block = json.optJSONObject("content_block")
                if (block?.optString("type") == "tool_use") {
                    val id = block.optString("id")
                    val name = block.optString("name")
                    toolBlocks[index] = ToolBlock(id, name)
                    val initialInput = block.optJSONObject("input")
                        ?.takeIf { it.length() > 0 }
                        ?.toString()
                        .orEmpty()
                    ParsedModelStreamFrame(
                        toolDeltas = listOf(
                            ToolCallPayload(id, index, name, initialInput)
                        ),
                        providerSequence = json.optionalSequence()
                    )
                } else ParsedModelStreamFrame(providerSequence = json.optionalSequence())
            }
            "content_block_delta" -> {
                val index = json.optInt("index", 0)
                val delta = json.optJSONObject("delta") ?: JSONObject()
                when (delta.optString("type")) {
                    "text_delta" -> ParsedModelStreamFrame(
                        textDeltas = listOf(delta.optString("text")),
                        providerSequence = json.optionalSequence()
                    )
                    "input_json_delta" -> {
                        val block = toolBlocks[index] ?: ToolBlock("tool-$index", "")
                        ParsedModelStreamFrame(
                            toolDeltas = listOf(
                                ToolCallPayload(block.id, index, block.name, delta.optString("partial_json"))
                            ),
                            providerSequence = json.optionalSequence()
                        )
                    }
                    else -> ParsedModelStreamFrame(providerSequence = json.optionalSequence())
                }
            }
            "message_delta" -> ParsedModelStreamFrame(
                usage = json.optJSONObject("usage")?.anthropicUsage(),
                finishReason = json.optJSONObject("delta")?.optString("stop_reason")?.takeIf(String::isNotBlank),
                providerSequence = json.optionalSequence()
            )
            "message_stop" -> ParsedModelStreamFrame(terminal = true, providerSequence = json.optionalSequence())
            else -> ParsedModelStreamFrame(providerSequence = json.optionalSequence())
        }
    }

    override fun parseCompleteJson(data: String): ParsedModelStreamFrame {
        val json = runCatching { JSONObject(data) }.getOrElse { error ->
            return ParsedModelStreamFrame(error = ModelStreamError("INVALID_RESPONSE_JSON", error.message.orEmpty()))
        }
        if (json.has("error")) return providerError(json)
        val text = mutableListOf<String>()
        val tools = mutableListOf<ToolCallPayload>()
        val content = json.optJSONArray("content") ?: JSONArray()
        for (index in 0 until content.length()) {
            val block = content.optJSONObject(index) ?: continue
            when (block.optString("type")) {
                "text" -> text += block.optString("text")
                "tool_use" -> tools += ToolCallPayload(
                    block.optString("id"),
                    index,
                    block.optString("name"),
                    block.optJSONObject("input")?.toString().orEmpty()
                )
            }
        }
        return ParsedModelStreamFrame(
            textDeltas = text,
            toolDeltas = tools,
            usage = json.optJSONObject("usage")?.anthropicUsage(),
            finishReason = json.optString("stop_reason").takeIf(String::isNotBlank),
            terminal = true
        )
    }
}

private class GeminiModelStreamAdapter : ModelStreamProviderAdapter {
    override fun parse(data: String, eventName: String?): ParsedModelStreamFrame = parseJson(data, terminal = false)

    override fun parseCompleteJson(data: String): ParsedModelStreamFrame = parseJson(data, terminal = true)

    private fun parseJson(data: String, terminal: Boolean): ParsedModelStreamFrame {
        val json = runCatching { JSONObject(data) }.getOrElse { error ->
            return ParsedModelStreamFrame(error = ModelStreamError("INVALID_RESPONSE_JSON", error.message.orEmpty()))
        }
        if (json.has("error")) return providerError(json)
        val candidate = json.optJSONArray("candidates")?.optJSONObject(0)
        val parts = candidate?.optJSONObject("content")?.optJSONArray("parts") ?: JSONArray()
        val text = mutableListOf<String>()
        val tools = mutableListOf<ToolCallPayload>()
        for (index in 0 until parts.length()) {
            val part = parts.optJSONObject(index) ?: continue
            part.optString("text").takeIf(String::isNotEmpty)?.let(text::add)
            val function = part.optJSONObject("functionCall") ?: continue
            tools += ToolCallPayload(
                callId = function.optString("id").ifBlank { "gemini-$index" },
                index = index,
                nameDelta = function.optString("name"),
                argumentsDelta = function.optJSONObject("args")?.toString().orEmpty(),
                argumentsMode = ToolCallArgumentsMode.SNAPSHOT
            )
        }
        val finishReason = candidate?.optString("finishReason")?.takeIf(String::isNotBlank)
        return ParsedModelStreamFrame(
            textDeltas = text,
            toolDeltas = tools,
            usage = json.optJSONObject("usageMetadata")?.geminiUsage(),
            finishReason = finishReason,
            terminal = terminal || finishReason != null,
            providerSequence = json.optionalSequence()
        )
    }
}

private fun providerError(json: JSONObject): ParsedModelStreamFrame {
    val error = json.optJSONObject("error") ?: json
    return ParsedModelStreamFrame(
        error = ModelStreamError(
            code = error.optString("code").ifBlank { error.optString("type").ifBlank { "PROVIDER_ERROR" } },
            message = error.optString("message").ifBlank { json.toString().take(1_000) },
            retryable = error.optInt("code") >= 500
        )
    )
}

private fun JSONObject.optionalSequence(): Long? = when {
    has("sequence") -> optLong("sequence")
    has("seq") -> optLong("seq")
    else -> null
}

private fun JSONObject.openAiUsage(): ModelUsage = ModelUsage(
    inputTokens = optLong("prompt_tokens", optLong("input_tokens", 0L)),
    outputTokens = optLong("completion_tokens", optLong("output_tokens", 0L)),
    cachedInputTokens = optJSONObject("prompt_tokens_details")?.optLong("cached_tokens", 0L) ?: 0L
)

private fun JSONObject.anthropicUsage(): ModelUsage = ModelUsage(
    inputTokens = optLong("input_tokens", 0L),
    outputTokens = optLong("output_tokens", 0L),
    cachedInputTokens = optLong("cache_read_input_tokens", 0L)
)

private fun JSONObject.geminiUsage(): ModelUsage = ModelUsage(
    inputTokens = optLong("promptTokenCount", 0L),
    outputTokens = optLong("candidatesTokenCount", 0L),
    cachedInputTokens = optLong("cachedContentTokenCount", 0L)
)

private fun textValue(value: Any?): String = when (value) {
    is String -> value
    is JSONArray -> buildString {
        for (index in 0 until value.length()) {
            val item = value.opt(index)
            when (item) {
                is String -> append(item)
                is JSONObject -> append(item.optString("text"))
            }
        }
    }
    is JSONObject -> value.optString("text")
    else -> ""
}
