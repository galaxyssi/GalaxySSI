package com.galaxyssi.chat.voice.modelstream

import kotlinx.coroutines.flow.Flow

enum class ModelStreamProvider {
    OPENAI_COMPATIBLE,
    ANTHROPIC,
    GEMINI
}

enum class ModelStreamTransport {
    SSE,
    JSON_LINES,
    COMPLETE_JSON
}

enum class ModelStreamCancelReason {
    USER_STOP,
    NEW_REQUEST,
    SESSION_CHANGED,
    VOICE_BARGE_IN,
    APP_DESTROYED
}

data class ModelStreamRequest(
    val requestId: String,
    val provider: ModelStreamProvider,
    val endpoint: String,
    val headers: Map<String, String>,
    val bodyJson: String,
    val transport: ModelStreamTransport = ModelStreamTransport.SSE,
    val connectTimeoutMs: Long = 20_000L,
    val readTimeoutMs: Long = 300_000L
) {
    init {
        require(requestId.isNotBlank())
        require(endpoint.startsWith("https://") || endpoint.startsWith("http://127.0.0.1") || endpoint.startsWith("http://localhost"))
        require(bodyJson.isNotBlank())
        require(connectTimeoutMs in 1_000L..120_000L)
        require(readTimeoutMs in 10_000L..900_000L)
    }
}

data class ToolCallPayload(
    val callId: String,
    val index: Int,
    val nameDelta: String = "",
    val argumentsDelta: String = "",
    val argumentsMode: ToolCallArgumentsMode = ToolCallArgumentsMode.DELTA
)

enum class ToolCallArgumentsMode { DELTA, SNAPSHOT }

data class ModelUsage(
    val inputTokens: Long = 0L,
    val outputTokens: Long = 0L,
    val cachedInputTokens: Long = 0L
)

data class ModelStreamError(
    val code: String,
    val message: String,
    val httpStatus: Int? = null,
    val retryable: Boolean = false,
    val partialResponse: Boolean = false
)

sealed interface ModelStreamEvent {
    val requestId: String

    data class Connected(
        override val requestId: String,
        val httpStatus: Int,
        val connectedAtElapsedMs: Long
    ) : ModelStreamEvent

    data class TextDelta(
        override val requestId: String,
        val sequence: Long,
        val text: String,
        val receivedAtElapsedMs: Long
    ) : ModelStreamEvent

    data class ToolCallDelta(
        override val requestId: String,
        val sequence: Long,
        val payload: ToolCallPayload
    ) : ModelStreamEvent

    data class Usage(
        override val requestId: String,
        val usage: ModelUsage
    ) : ModelStreamEvent

    data class Completed(
        override val requestId: String,
        val finishReason: String?,
        val completedAtElapsedMs: Long
    ) : ModelStreamEvent

    data class Failed(
        override val requestId: String,
        val error: ModelStreamError
    ) : ModelStreamEvent
}

interface CloudModelStreamClient {
    fun stream(request: ModelStreamRequest): Flow<ModelStreamEvent>
    suspend fun cancel(requestId: String, reason: ModelStreamCancelReason)
}

data class AssembledToolCall(
    val callId: String,
    val index: Int,
    val name: String,
    val argumentsJson: String
)

class ToolCallDeltaAssembler {
    private data class MutableCall(
        var callId: String,
        val index: Int,
        val name: StringBuilder = StringBuilder(),
        val arguments: StringBuilder = StringBuilder()
    )

    private val calls = linkedMapOf<Int, MutableCall>()

    @Synchronized
    fun accept(payload: ToolCallPayload) {
        val call = calls.getOrPut(payload.index) {
            MutableCall(payload.callId, payload.index)
        }
        if (call.callId.isBlank() && payload.callId.isNotBlank()) call.callId = payload.callId
        appendName(call.name, payload.nameDelta)
        appendArguments(call.arguments, payload.argumentsDelta, payload.argumentsMode)
    }

    @Synchronized
    fun completedCalls(): List<AssembledToolCall> = calls.values
        .mapNotNull { call ->
            val name = call.name.toString().trim()
            if (name.isBlank()) return@mapNotNull null
            AssembledToolCall(
                callId = call.callId.ifBlank { "tool-${call.index}" },
                index = call.index,
                name = name,
                argumentsJson = call.arguments.toString().trim().ifBlank { "{}" }
            )
        }
        .sortedBy(AssembledToolCall::index)

    @Synchronized
    fun clear() = calls.clear()

    private fun appendName(target: StringBuilder, delta: String) {
        if (delta.isEmpty()) return
        val current = target.toString()
        when {
            current.isEmpty() -> target.append(delta)
            delta == current -> Unit
            delta.startsWith(current) -> {
                target.setLength(0)
                target.append(delta)
            }
            current.endsWith(delta) -> Unit
            else -> target.append(delta)
        }
    }

    private fun appendArguments(
        target: StringBuilder,
        value: String,
        mode: ToolCallArgumentsMode
    ) {
        if (value.isEmpty()) return
        if (mode == ToolCallArgumentsMode.SNAPSHOT) target.setLength(0)
        target.append(value)
    }
}
