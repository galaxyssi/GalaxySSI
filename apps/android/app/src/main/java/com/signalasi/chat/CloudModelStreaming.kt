package com.signalasi.chat

import android.content.Context
import com.signalasi.chat.voice.modelstream.AssembledToolCall
import com.signalasi.chat.voice.modelstream.CloudModelStreamClient
import com.signalasi.chat.voice.modelstream.ModelStreamCancelReason
import com.signalasi.chat.voice.modelstream.ModelStreamError
import com.signalasi.chat.voice.modelstream.ModelStreamEvent
import com.signalasi.chat.voice.modelstream.ModelStreamProvider
import com.signalasi.chat.voice.modelstream.ModelStreamRequest
import com.signalasi.chat.voice.modelstream.ModelStreamTransport
import com.signalasi.chat.voice.modelstream.ModelUsage
import com.signalasi.chat.voice.modelstream.OkHttpCloudModelStreamClient
import com.signalasi.chat.voice.modelstream.ToolCallDeltaAssembler
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.FlowCollector
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong

data class PreparedCloudConversationStream(
    val requestId: String,
    val provider: ModelStreamProvider,
    val endpoint: String,
    val headers: Map<String, String>,
    val body: JSONObject,
    val conversation: JSONArray,
    val conversationKey: String
)

object CloudConversationStreamEngine : CloudModelStreamClient {
    private const val MAX_TOOL_ROUNDS = 4
    private const val MAX_TOOL_CALLS = 8
    private const val MAX_PARALLEL_TOOL_CALLS = 4
    private val transport = OkHttpCloudModelStreamClient()
    private val activeRoundIds = ConcurrentHashMap<String, String>()

    internal fun streamConversation(
        context: Context,
        contact: JSONObject,
        turns: List<ChatMessage>,
        requestId: String,
        images: List<CloudImagePayload> = emptyList(),
        connectTimeoutMillis: Long = 20_000L,
        readTimeoutMillis: Long = 300_000L,
        onToolEvent: ((CloudToolEvent) -> Unit)? = null,
        allowExternalTools: Boolean = true
    ): Flow<ModelStreamEvent> = flow {
        if (!contact.optBoolean("cloud_streaming_enabled", true)) {
            emitLegacy(context, contact, turns, requestId, images, onToolEvent)
            return@flow
        }
        val disclosure = AgentDataDisclosureLedger.beginCloudRequest(
            context = context,
            contact = contact,
            text = turns.joinToString("\n") { it.content },
            historyCount = turns.size,
            systemInstructions = true,
            purpose = "Streaming conversation response",
            attachmentKinds = if (images.isEmpty()) emptySet() else setOf(AgentDisclosedDataKind.IMAGE),
            attachmentCount = images.size,
            attachmentBytes = images.sumOf { it.bytes.size.toLong() }
        )
        if (!disclosure.allowed) {
            emit(
                ModelStreamEvent.Failed(
                    requestId,
                    ModelStreamError("DISCLOSURE_BLOCKED", "Cloud data disclosure is not allowed")
                )
            )
            return@flow
        }
        val prepared = runCatching {
            CloudModelClient.prepareConversationStream(context, contact, turns, requestId, images)
        }.getOrElse { error ->
            AgentDataDisclosureLedger.update(context, disclosure, AgentDisclosureStatus.FAILED, error.message.orEmpty())
            emit(ModelStreamEvent.Failed(requestId, error.toStreamError()))
            return@flow
        }
        if (!allowExternalTools) disableExternalTools(prepared)
        val globalSequence = AtomicLong(0L)
        val executedToolKeys = linkedSetOf<String>()
        var toolCallCount = 0
        var emittedText = false
        var connected = false
        var lastFinishReason: String? = null
        try {
            for (round in 0 until MAX_TOOL_ROUNDS) {
                if (round == MAX_TOOL_ROUNDS - 1) prepareFinalRound(prepared)
                val roundId = "$requestId:r$round"
                activeRoundIds[requestId] = roundId
                val assembler = ToolCallDeltaAssembler()
                val inlineProtocolGuard = InlineToolProtocolStreamGuard()
                var roundFailure: ModelStreamEvent.Failed? = null
                var roundCompleted = false
                transport.stream(
                    prepared.toRequest(
                        roundId = roundId,
                        connectTimeoutMillis = connectTimeoutMillis,
                        readTimeoutMillis = readTimeoutMillis
                    )
                ).collect { event ->
                    when (event) {
                        is ModelStreamEvent.Connected -> if (!connected) {
                            connected = true
                            emit(
                                ModelStreamEvent.Connected(
                                    requestId,
                                    event.httpStatus,
                                    event.connectedAtElapsedMs
                                )
                            )
                        }
                        is ModelStreamEvent.TextDelta -> {
                            val visibleText = inlineProtocolGuard.append(event.text)
                            if (visibleText.isNotEmpty()) {
                                emittedText = true
                                emit(
                                    ModelStreamEvent.TextDelta(
                                        requestId,
                                        globalSequence.incrementAndGet(),
                                        visibleText,
                                        event.receivedAtElapsedMs
                                    )
                                )
                            }
                        }
                        is ModelStreamEvent.ToolCallDelta -> {
                            assembler.accept(event.payload)
                            emit(
                                ModelStreamEvent.ToolCallDelta(
                                    requestId,
                                    globalSequence.incrementAndGet(),
                                    event.payload
                                )
                            )
                        }
                        is ModelStreamEvent.Usage -> emit(ModelStreamEvent.Usage(requestId, event.usage))
                        is ModelStreamEvent.Completed -> {
                            roundCompleted = true
                            lastFinishReason = event.finishReason
                        }
                        is ModelStreamEvent.Failed -> roundFailure = ModelStreamEvent.Failed(requestId, event.error)
                    }
                }
                activeRoundIds.remove(requestId, roundId)
                val failure = roundFailure
                if (failure != null) {
                    if (!emittedText && failure.error.code == "STREAM_UNSUPPORTED") {
                        AgentDataDisclosureLedger.update(
                            context,
                            disclosure,
                            AgentDisclosureStatus.FAILED,
                            "stream unsupported; used compatibility request"
                        )
                        emitLegacy(context, contact, turns, requestId, images, onToolEvent)
                    } else {
                        AgentDataDisclosureLedger.update(
                            context,
                            disclosure,
                            AgentDisclosureStatus.FAILED,
                            failure.error.message
                        )
                        emit(failure)
                    }
                    return@flow
                }
                if (!roundCompleted) {
                    val error = ModelStreamError(
                        "STREAM_INTERRUPTED",
                        "The provider stream ended before completion",
                        retryable = true,
                        partialResponse = emittedText
                    )
                    AgentDataDisclosureLedger.update(context, disclosure, AgentDisclosureStatus.FAILED, error.message)
                    emit(ModelStreamEvent.Failed(requestId, error))
                    return@flow
                }
                val visibleTail = inlineProtocolGuard.finishVisibleText()
                if (visibleTail.isNotEmpty()) {
                    emittedText = true
                    emit(
                        ModelStreamEvent.TextDelta(
                            requestId,
                            globalSequence.incrementAndGet(),
                            visibleTail,
                            System.nanoTime() / 1_000_000L
                        )
                    )
                }
                val rawRoundText = inlineProtocolGuard.rawText()
                if (!allowExternalTools) {
                    AgentDataDisclosureLedger.update(context, disclosure, AgentDisclosureStatus.SENT)
                    emit(
                        ModelStreamEvent.Completed(
                            requestId,
                            lastFinishReason,
                            System.nanoTime() / 1_000_000L
                        )
                    )
                    return@flow
                }
                val structuredCalls = assembler.completedCalls()
                val inlineCalls = CloudWebGrounding.parseInlineToolCalls(rawRoundText)
                val usesInlineProtocol = structuredCalls.isEmpty() && inlineCalls.isNotEmpty()
                val calls = if (usesInlineProtocol) {
                    inlineCalls.mapIndexed { index, call ->
                        AssembledToolCall(
                            callId = "inline-r$round-$index",
                            index = index,
                            name = call.name,
                            argumentsJson = call.arguments.toString()
                        )
                    }
                } else {
                    structuredCalls
                }
                if (calls.isEmpty()) {
                    if (CloudWebGrounding.containsInternalToolProtocol(rawRoundText)) {
                        appendInlineToolRepairPrompt(prepared, rawRoundText)
                        continue
                    }
                    AgentDataDisclosureLedger.update(context, disclosure, AgentDisclosureStatus.SENT)
                    emit(
                        ModelStreamEvent.Completed(
                            requestId,
                            lastFinishReason,
                            System.nanoTime() / 1_000_000L
                        )
                    )
                    return@flow
                }
                val remaining = MAX_TOOL_CALLS - toolCallCount
                if (remaining <= 0 || round == MAX_TOOL_ROUNDS - 1) {
                    prepareFinalRound(prepared)
                    continue
                }
                val preparedCalls = mutableListOf<PreparedCloudToolCall>()
                var invalidToolCall: AssembledToolCall? = null
                for (call in calls.take(remaining)) {
                    val key = call.identityKey()
                    val arguments = runCatching { JSONObject(call.argumentsJson) }.getOrNull()
                    if (arguments == null) {
                        invalidToolCall = call
                        break
                    }
                    if (!executedToolKeys.add(key)) continue
                    onToolEvent?.invoke(CloudToolEvent(call.name, "running", arguments.toString().take(240)))
                    preparedCalls += PreparedCloudToolCall(call, arguments)
                }
                if (invalidToolCall != null) {
                    appendToolArgumentRepairPrompt(prepared, invalidToolCall)
                    continue
                }
                val completedCalls = CloudToolBatchExecutor.executeOrdered(
                    calls = preparedCalls,
                    maxParallel = MAX_PARALLEL_TOOL_CALLS
                ) { preparedCall ->
                    CloudWebGrounding.executeTool(
                        context,
                        preparedCall.call.name,
                        preparedCall.arguments
                    )
                }
                completedCalls.forEach { completed ->
                    onToolEvent?.invoke(
                        CloudToolEvent(completed.call.name, "completed", completed.output.take(240))
                    )
                }
                toolCallCount += completedCalls.size
                if (usesInlineProtocol) {
                    appendInlineToolResults(prepared, rawRoundText, completedCalls)
                } else {
                    appendToolResults(prepared, completedCalls.map { it.call to it.output })
                }
            }
            val error = ModelStreamError(
                "TOOL_ROUND_LIMIT",
                "The model did not produce a final answer within the tool-call budget",
                partialResponse = emittedText
            )
            AgentDataDisclosureLedger.update(context, disclosure, AgentDisclosureStatus.FAILED, error.message)
            emit(ModelStreamEvent.Failed(requestId, error))
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Throwable) {
            AgentDataDisclosureLedger.update(context, disclosure, AgentDisclosureStatus.FAILED, error.message.orEmpty())
            emit(ModelStreamEvent.Failed(requestId, error.toStreamError(partialResponse = emittedText)))
        } finally {
            activeRoundIds.remove(requestId)
        }
    }.flowOn(Dispatchers.IO)

    override fun stream(request: ModelStreamRequest): Flow<ModelStreamEvent> = transport.stream(request)

    override suspend fun cancel(requestId: String, reason: ModelStreamCancelReason) {
        val roundId = activeRoundIds[requestId]
        if (roundId != null) transport.cancel(roundId, reason)
    }

    private suspend fun FlowCollector<ModelStreamEvent>.emitLegacy(
        context: Context,
        contact: JSONObject,
        turns: List<ChatMessage>,
        requestId: String,
        images: List<CloudImagePayload>,
        onToolEvent: ((CloudToolEvent) -> Unit)?
    ) {
        val result = runCatching {
            CloudModelClient.legacyConversationResponse(context, contact, turns, images, onToolEvent)
        }
        val text = result.getOrNull().orEmpty()
        if (text.isNotBlank()) {
            val now = System.nanoTime() / 1_000_000L
            emit(ModelStreamEvent.TextDelta(requestId, 1L, text, now))
            emit(ModelStreamEvent.Completed(requestId, "compatibility", now))
        } else {
            emit(ModelStreamEvent.Failed(requestId, result.exceptionOrNull().toStreamError()))
        }
    }

    private fun PreparedCloudConversationStream.toRequest(
        roundId: String,
        connectTimeoutMillis: Long,
        readTimeoutMillis: Long
    ): ModelStreamRequest =
        ModelStreamRequest(
            requestId = roundId,
            provider = provider,
            endpoint = endpoint,
            headers = headers,
            bodyJson = body.put(conversationKey, conversation).toString(),
            transport = ModelStreamTransport.SSE,
            connectTimeoutMs = connectTimeoutMillis,
            readTimeoutMs = readTimeoutMillis
        )

    private fun prepareFinalRound(prepared: PreparedCloudConversationStream) {
        disableExternalTools(prepared)
        when (prepared.provider) {
            ModelStreamProvider.OPENAI_COMPATIBLE,
            ModelStreamProvider.ANTHROPIC -> prepared.conversation.put(
                JSONObject()
                    .put("role", "user")
                    .put("content", FINALIZE_PROMPT)
            )
            ModelStreamProvider.GEMINI -> prepared.conversation.put(
                JSONObject()
                    .put("role", "user")
                    .put("parts", JSONArray().put(JSONObject().put("text", FINALIZE_PROMPT)))
            )
        }
    }

    private fun disableExternalTools(prepared: PreparedCloudConversationStream) {
        prepared.body.remove("tools")
        prepared.body.remove("tool_choice")
    }

    private fun appendToolArgumentRepairPrompt(
        prepared: PreparedCloudConversationStream,
        call: AssembledToolCall
    ) {
        val prompt = TOOL_ARGUMENT_REPAIR_PROMPT.format(call.name)
        when (prepared.provider) {
            ModelStreamProvider.OPENAI_COMPATIBLE,
            ModelStreamProvider.ANTHROPIC -> prepared.conversation.put(
                JSONObject().put("role", "user").put("content", prompt)
            )
            ModelStreamProvider.GEMINI -> prepared.conversation.put(
                JSONObject()
                    .put("role", "user")
                    .put("parts", JSONArray().put(JSONObject().put("text", prompt)))
            )
        }
    }

    private fun appendInlineToolRepairPrompt(
        prepared: PreparedCloudConversationStream,
        rawText: String
    ) {
        appendPlainConversationTurn(
            prepared,
            role = "assistant",
            text = CloudWebGrounding.stripInternalToolProtocol(rawText)
                .ifBlank { "I need current public evidence to answer." }
        )
        appendPlainConversationTurn(prepared, role = "user", text = INLINE_TOOL_REPAIR_PROMPT)
    }

    private fun appendInlineToolResults(
        prepared: PreparedCloudConversationStream,
        rawText: String,
        results: List<CompletedCloudToolCall>
    ) {
        appendPlainConversationTurn(
            prepared,
            role = "assistant",
            text = CloudWebGrounding.stripInternalToolProtocol(rawText)
                .ifBlank { "I need current public evidence to answer." }
        )
        val evidence = results.map { completed ->
            val arguments = runCatching { JSONObject(completed.call.argumentsJson) }
                .getOrDefault(JSONObject())
            CloudWebGrounding.InlineToolCall(completed.call.name, arguments) to completed.output
        }
        appendPlainConversationTurn(
            prepared,
            role = "user",
            text = CloudWebGrounding.inlineEvidenceMessage(evidence)
        )
    }

    private fun appendPlainConversationTurn(
        prepared: PreparedCloudConversationStream,
        role: String,
        text: String
    ) {
        when (prepared.provider) {
            ModelStreamProvider.OPENAI_COMPATIBLE,
            ModelStreamProvider.ANTHROPIC -> prepared.conversation.put(
                JSONObject().put("role", role).put("content", text)
            )
            ModelStreamProvider.GEMINI -> prepared.conversation.put(
                JSONObject()
                    .put("role", if (role == "assistant") "model" else "user")
                    .put("parts", JSONArray().put(JSONObject().put("text", text)))
            )
        }
    }

    private fun appendToolResults(
        prepared: PreparedCloudConversationStream,
        results: List<Pair<AssembledToolCall, String>>
    ) {
        if (results.isEmpty()) return
        when (prepared.provider) {
            ModelStreamProvider.OPENAI_COMPATIBLE -> appendOpenAiToolResults(prepared.conversation, results)
            ModelStreamProvider.ANTHROPIC -> appendAnthropicToolResults(prepared.conversation, results)
            ModelStreamProvider.GEMINI -> appendGeminiToolResults(prepared.conversation, results)
        }
    }

    private fun appendOpenAiToolResults(
        conversation: JSONArray,
        results: List<Pair<AssembledToolCall, String>>
    ) {
        val calls = JSONArray()
        results.forEach { (call, _) ->
            calls.put(
                JSONObject()
                    .put("id", call.callId)
                    .put("type", "function")
                    .put(
                        "function",
                        JSONObject().put("name", call.name).put("arguments", call.argumentsJson)
                    )
            )
        }
        conversation.put(JSONObject().put("role", "assistant").put("content", JSONObject.NULL).put("tool_calls", calls))
        results.forEach { (call, result) ->
            conversation.put(
                JSONObject()
                    .put("role", "tool")
                    .put("tool_call_id", call.callId)
                    .put("content", wrappedToolResult(call.name, result))
            )
        }
    }

    private fun appendAnthropicToolResults(
        conversation: JSONArray,
        results: List<Pair<AssembledToolCall, String>>
    ) {
        val uses = JSONArray()
        val toolResults = JSONArray()
        results.forEach { (call, result) ->
            uses.put(
                JSONObject()
                    .put("type", "tool_use")
                    .put("id", call.callId)
                    .put("name", call.name)
                    .put("input", JSONObject(call.argumentsJson))
            )
            toolResults.put(
                JSONObject()
                    .put("type", "tool_result")
                    .put("tool_use_id", call.callId)
                    .put("content", wrappedToolResult(call.name, result))
            )
        }
        conversation.put(JSONObject().put("role", "assistant").put("content", uses))
        conversation.put(JSONObject().put("role", "user").put("content", toolResults))
    }

    private fun appendGeminiToolResults(
        conversation: JSONArray,
        results: List<Pair<AssembledToolCall, String>>
    ) {
        val uses = JSONArray()
        val toolResults = JSONArray()
        results.forEach { (call, result) ->
            uses.put(
                JSONObject().put(
                    "functionCall",
                    JSONObject()
                        .put("name", call.name)
                        .put("args", JSONObject(call.argumentsJson))
                )
            )
            toolResults.put(
                JSONObject().put(
                    "functionResponse",
                    JSONObject()
                        .put("name", call.name)
                        .put("response", JSONObject().put("result", wrappedToolResult(call.name, result)))
                )
            )
        }
        conversation.put(JSONObject().put("role", "model").put("parts", uses))
        conversation.put(JSONObject().put("role", "user").put("parts", toolResults))
    }

    private fun wrappedToolResult(toolName: String, result: String): String =
        AgentUntrustedEvidenceBoundary.wrapText("web_tool_result", toolName, result)

    private fun AssembledToolCall.identityKey(): String {
        val material = "$callId\u0000$name\u0000$argumentsJson"
        return MessageDigest.getInstance("SHA-256")
            .digest(material.toByteArray(Charsets.UTF_8))
            .joinToString("") { byte -> "%02x".format(byte) }
    }

    private fun Throwable?.toStreamError(partialResponse: Boolean = false): ModelStreamError {
        val error = this
        return ModelStreamError(
            code = error?.javaClass?.simpleName?.uppercase().orEmpty().ifBlank { "MODEL_STREAM_FAILED" },
            message = error?.message.orEmpty().ifBlank { "Cloud model request failed" },
            retryable = error is java.io.IOException,
            partialResponse = partialResponse
        )
    }

    private const val TOOL_ARGUMENT_REPAIR_PROMPT =
        "The previous %s tool call contained incomplete JSON arguments. Call that tool again now with one " +
            "complete valid JSON object. Do not expose this repair instruction to the user."

    private const val INLINE_TOOL_REPAIR_PROMPT =
        "The previous inline tool call was incomplete. Call the required web tool again with valid complete " +
            "arguments. Do not expose DSML, XML, JSON protocol, or this repair instruction to the user."

    private const val FINALIZE_PROMPT =
        "Tool execution is complete. Use the evidence already supplied and return the final user-facing answer now. " +
            "Do not call another tool or expose internal protocol text."
}
