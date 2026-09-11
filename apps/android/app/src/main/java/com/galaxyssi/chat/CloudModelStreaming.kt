package com.galaxyssi.chat

import android.content.Context
import android.util.Log
import com.galaxyssi.chat.voice.modelstream.AssembledToolCall
import com.galaxyssi.chat.voice.modelstream.CloudModelStreamClient
import com.galaxyssi.chat.voice.modelstream.ModelStreamCancelReason
import com.galaxyssi.chat.voice.modelstream.ModelStreamError
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import com.galaxyssi.chat.voice.modelstream.ModelStreamProvider
import com.galaxyssi.chat.voice.modelstream.ModelStreamRequest
import com.galaxyssi.chat.voice.modelstream.ModelStreamRequestLifetimes
import com.galaxyssi.chat.voice.modelstream.ModelStreamTransport
import com.galaxyssi.chat.voice.modelstream.ModelUsage
import com.galaxyssi.chat.voice.modelstream.OkHttpCloudModelStreamClient
import com.galaxyssi.chat.voice.modelstream.ToolCallDeltaAssembler
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.FlowCollector
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.emitAll
import org.json.JSONArray
import org.json.JSONObject
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
    private const val MAX_PARALLEL_TOOL_CALLS = 4
    private val transport = OkHttpCloudModelStreamClient()
    private val lifetimes = ModelStreamRequestLifetimes()

    internal fun streamConversation(
        context: Context,
        contact: JSONObject,
        turns: List<ChatMessage>,
        requestId: String,
        images: List<CloudImagePayload> = emptyList(),
        connectTimeoutMillis: Long = 20_000L,
        readTimeoutMillis: Long = 300_000L,
        onToolEvent: ((CloudToolEvent) -> Unit)? = null,
        allowExternalTools: Boolean = true,
        systemPromptOverride: String = ""
    ): Flow<ModelStreamEvent> = flow {
        lifetimes.run(requestId) {
            emitAll(streamConversationOwned(context, contact, turns, requestId, images, connectTimeoutMillis,
                readTimeoutMillis, onToolEvent, allowExternalTools, systemPromptOverride))
        }
    }.flowOn(Dispatchers.IO)

    private fun streamConversationOwned(
        context: Context,
        contact: JSONObject,
        turns: List<ChatMessage>,
        requestId: String,
        images: List<CloudImagePayload>,
        connectTimeoutMillis: Long,
        readTimeoutMillis: Long,
        onToolEvent: ((CloudToolEvent) -> Unit)?,
        allowExternalTools: Boolean,
        systemPromptOverride: String
    ): Flow<ModelStreamEvent> = flow {
        if (!contact.optBoolean("cloud_streaming_enabled", true)) {
            emitLegacy(context, contact, turns, requestId, images, onToolEvent, systemPromptOverride)
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
            CloudModelClient.prepareConversationStream(
                context,
                contact,
                turns,
                requestId,
                images,
                systemPromptOverride
            )
        }.getOrElse { error ->
            AgentDataDisclosureLedger.update(context, disclosure, AgentDisclosureStatus.FAILED, error.message.orEmpty())
            emit(ModelStreamEvent.Failed(requestId, error.toStreamError()))
            return@flow
        }
        if (!allowExternalTools) disableExternalTools(prepared)
        val globalSequence = AtomicLong(0L)
        val toolProgress = CloudWebToolLoopProgress()
        var webBudget: AgentWebExecutionBudget? = null
        val evidenceResults = mutableListOf<Pair<String, String>>()
        var emittedText = false
        var connected = false
        var lastFinishReason: String? = null
        try {
            var round = 0L
            while (true) {
                if (webBudget?.expired == true && toolProgress.requestFinalization()) prepareFinalRound(prepared)
                val roundNumber = round++
                val bufferForCitationVerification = evidenceResults.isNotEmpty()
                val roundId = "$requestId:r$roundNumber"
                val roundStarted = System.nanoTime()
                var firstActivity = false
                val assembler = ToolCallDeltaAssembler()
                val inlineProtocolGuard = InlineToolProtocolStreamGuard()
                var roundFailure: ModelStreamEvent.Failed? = null
                var roundCompleted = false
                val roundBudgetMillis = if (toolProgress.finalizationRequested) 30_000L
                    else webBudget?.remainingMillis?.coerceAtLeast(1L) ?: Long.MAX_VALUE
                val finishedWithinBudget = withTimeoutOrNull(roundBudgetMillis) {
                    val roundRequest = prepared.toRequest(
                            roundId = roundId,
                            connectTimeoutMillis = connectTimeoutMillis,
                            readTimeoutMillis = if (toolProgress.finalizationRequested) minOf(readTimeoutMillis, 30_000L)
                                else readTimeoutMillis
                        )
                    Log.i("GalaxySSIWebLatency", "model_round request=$requestId round=$roundNumber stage=request " +
                        "prepare_ms=${(System.nanoTime() - roundStarted) / 1_000_000L} input_chars=${roundRequest.bodyJson.length}")
                    transport.stream(roundRequest).collect { event ->
                        if (!firstActivity && (event is ModelStreamEvent.TextDelta || event is ModelStreamEvent.ToolCallDelta)) {
                            firstActivity = true
                            Log.i("GalaxySSIWebLatency", "model_round request=$requestId round=$roundNumber stage=first_activity " +
                                "elapsed_ms=${(System.nanoTime() - roundStarted) / 1_000_000L} kind=${if (event is ModelStreamEvent.ToolCallDelta) "tool" else "text"}")
                        }
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
                                if (visibleText.isNotEmpty() && !bufferForCitationVerification) {
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
                    true
                } ?: false
                Log.i("GalaxySSIWebLatency", "model_round request=$requestId round=$roundNumber stage=finished " +
                    "elapsed_ms=${(System.nanoTime() - roundStarted) / 1_000_000L} completed=$roundCompleted")
                if (!finishedWithinBudget) {
                    emitEvidenceFallbackAndComplete(context, disclosure, requestId, globalSequence,
                        evidenceResults, "web_deadline")
                    return@flow
                }
                val failure = roundFailure
                if (failure != null) {
                    if (!emittedText && failure.error.code == "STREAM_UNSUPPORTED") {
                        AgentDataDisclosureLedger.update(
                            context,
                            disclosure,
                            AgentDisclosureStatus.FAILED,
                            "stream unsupported; used compatibility request"
                        )
                        emitLegacy(
                            context,
                            contact,
                            turns,
                            requestId,
                            images,
                            onToolEvent,
                            systemPromptOverride
                        )
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
                if (visibleTail.isNotEmpty() && !bufferForCitationVerification) {
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
                            callId = "inline-r$roundNumber-$index",
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
                        if (!toolProgress.requestRepair("stream_internal_protocol")) {
                            emitEvidenceFallbackAndComplete(
                                context,
                                disclosure,
                                requestId,
                                globalSequence,
                                evidenceResults,
                                lastFinishReason
                            )
                            return@flow
                        }
                        appendInlineToolRepairPrompt(prepared, rawRoundText)
                        continue
                    }
                    if (bufferForCitationVerification) {
                        val candidate = CloudWebGrounding.stripInternalToolProtocol(rawRoundText)
                        val validationStarted = System.nanoTime()
                        val citationRepair = CloudWebGrounding.citationRepairPrompt(candidate, evidenceResults)
                        Log.i("GalaxySSIWebLatency", "model_round request=$requestId round=$roundNumber stage=citation_validation " +
                            "elapsed_ms=${(System.nanoTime() - validationStarted) / 1_000_000L} repair=${citationRepair != null}")
                        if (candidate.isNotBlank() && citationRepair != null &&
                            toolProgress.requestRepair("stream_citations")
                        ) {
                            appendPlainConversationTurn(prepared, role = "assistant", text = candidate)
                            appendPlainConversationTurn(prepared, role = "user", text = citationRepair)
                            disableExternalTools(prepared)
                            continue
                        }
                        val visibleAnswer = if (candidate.isNotBlank() && citationRepair == null) {
                            candidate
                        } else {
                            CloudWebGrounding.evidenceFallback(context, evidenceResults)
                        }
                        if (visibleAnswer.isNotBlank()) {
                            emittedText = true
                            emit(
                                ModelStreamEvent.TextDelta(
                                    requestId,
                                    globalSequence.incrementAndGet(),
                                    visibleAnswer,
                                    System.nanoTime() / 1_000_000L
                                )
                            )
                        }
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
                if (toolProgress.finalizationRequested) {
                    emitEvidenceFallbackAndComplete(
                        context,
                        disclosure,
                        requestId,
                        globalSequence,
                        evidenceResults,
                        lastFinishReason
                    )
                    return@flow
                }
                val parsedCalls = mutableListOf<Triple<AssembledToolCall, JSONObject, String>>()
                val preparedCallsByKey = linkedMapOf<String, PreparedCloudToolCall>()
                var invalidToolCall: AssembledToolCall? = null
                for (call in calls) {
                    val arguments = runCatching { JSONObject(call.argumentsJson) }.getOrNull()
                    if (arguments == null) {
                        invalidToolCall = call
                        break
                    }
                    val key = toolProgress.semanticKey(call.name, arguments)
                    parsedCalls += Triple(call, arguments, key)
                    if (toolProgress.cached(call.name, arguments) == null && key !in preparedCallsByKey) {
                        onToolEvent?.invoke(
                            CloudToolEvent(call.name, "running", arguments.toString().take(240))
                        )
                        preparedCallsByKey[key] = PreparedCloudToolCall(call, arguments)
                    }
                }
                if (invalidToolCall != null) {
                    if (toolProgress.requestRepair("stream_arguments:${invalidToolCall.name}")) {
                        appendToolArgumentRepairPrompt(prepared, invalidToolCall)
                    } else {
                        prepareFinalRound(prepared)
                        toolProgress.requestFinalization()
                    }
                    continue
                }
                val budget = webBudget ?: AgentWebExecutionBudget(
                    if (preparedCallsByKey.values.any { it.arguments.optString("profile") == "deep" }) 180_000L else 60_000L
                ).also { webBudget = it }
                val newlyCompleted = CloudToolBatchExecutor.executeOrdered(
                    calls = preparedCallsByKey.values.toList(),
                    maxParallel = MAX_PARALLEL_TOOL_CALLS,
                    onCompleted = { completed ->
                        onToolEvent?.invoke(CloudToolEvent(completed.call.name, "completed", completed.output.take(240)))
                    }
                ) { preparedCall ->
                    try {
                        budget.execute { token, checkpoint ->
                            CloudWebGrounding.executeTool(context, preparedCall.call.name,
                                preparedCall.arguments, token, checkpoint)
                        }
                    } catch (cancelled: CancellationException) {
                        throw cancelled
                    } catch (error: AgentWebBudgetExceededException) {
                        CloudWebGrounding.failureResult(preparedCall.call.name, error).toString()
                    }
                }
                newlyCompleted.forEach { completed ->
                    val arguments = JSONObject(completed.call.argumentsJson)
                    if (toolProgress.record(completed.call.name, arguments, completed.output)) {
                        evidenceResults += completed.call.name to completed.output
                    }
                }
                val completedCalls = parsedCalls.map { (call, arguments, _) ->
                    CompletedCloudToolCall(
                        call,
                        requireNotNull(toolProgress.cached(call.name, arguments)) {
                            "Web tool result was not recorded"
                        }
                    )
                }
                if (usesInlineProtocol) {
                    appendInlineToolResults(prepared, rawRoundText, completedCalls)
                } else {
                    appendToolResults(prepared, completedCalls.map { it.call to it.output })
                }
                val noEvidenceProgress = toolProgress.observeEvidenceBatch(newlyCompleted.map { it.output })
                if ((newlyCompleted.isEmpty() || noEvidenceProgress || budget.expired) && toolProgress.requestFinalization()) {
                    prepareFinalRound(prepared)
                }
            }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (error: Throwable) {
            AgentDataDisclosureLedger.update(context, disclosure, AgentDisclosureStatus.FAILED, error.message.orEmpty())
            emit(ModelStreamEvent.Failed(requestId, error.toStreamError(partialResponse = emittedText)))
        }
    }.flowOn(Dispatchers.IO)

    override fun stream(request: ModelStreamRequest): Flow<ModelStreamEvent> = transport.stream(request)

    override suspend fun cancel(requestId: String, reason: ModelStreamCancelReason) {
        // The captured owner cancels its own child socket; never look up a replacement round.
        if (!lifetimes.cancel(requestId, reason)) transport.cancel(requestId, reason)
    }

    private suspend fun FlowCollector<ModelStreamEvent>.emitEvidenceFallbackAndComplete(
        context: Context,
        disclosure: AgentDisclosureTicket,
        requestId: String,
        sequence: AtomicLong,
        evidenceResults: List<Pair<String, String>>,
        finishReason: String?
    ) {
        val fallback = CloudWebGrounding.evidenceFallback(context, evidenceResults)
        if (fallback.isNotBlank()) {
            emit(
                ModelStreamEvent.TextDelta(
                    requestId,
                    sequence.incrementAndGet(),
                    fallback,
                    System.nanoTime() / 1_000_000L
                )
            )
        }
        AgentDataDisclosureLedger.update(context, disclosure, AgentDisclosureStatus.SENT)
        emit(
            ModelStreamEvent.Completed(
                requestId,
                finishReason ?: "no_progress",
                System.nanoTime() / 1_000_000L
            )
        )
    }

    private suspend fun FlowCollector<ModelStreamEvent>.emitLegacy(
        context: Context,
        contact: JSONObject,
        turns: List<ChatMessage>,
        requestId: String,
        images: List<CloudImagePayload>,
        onToolEvent: ((CloudToolEvent) -> Unit)?,
        systemPromptOverride: String
    ) {
        val result = runCatching {
            CloudBlockingRequestCancellation.run { CloudModelClient.legacyConversationResponse(
                context,
                contact,
                turns,
                images,
                onToolEvent,
                systemPromptOverride
            ) }
        }
        result.exceptionOrNull()?.let { if (it is CancellationException) throw it }
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
        prepared.body.remove("parallel_tool_calls")
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
