package com.galaxyssi.chat.voice.modelstream

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.FlowCollector
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import okhttp3.Call
import okhttp3.ConnectionPool
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okio.BufferedSource
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

object SharedCloudModelHttpClient {
    val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectionPool(ConnectionPool(8, 5, TimeUnit.MINUTES))
            .connectTimeout(20, TimeUnit.SECONDS)
            .writeTimeout(60, TimeUnit.SECONDS)
            .readTimeout(5, TimeUnit.MINUTES)
            .callTimeout(0, TimeUnit.MILLISECONDS)
            .retryOnConnectionFailure(true)
            .build()
    }
}

class OkHttpCloudModelStreamClient(
    private val baseClient: OkHttpClient = SharedCloudModelHttpClient.client,
    private val elapsedRealtimeMs: () -> Long = { System.nanoTime() / 1_000_000L }
) : CloudModelStreamClient {
    private val activeCalls = ConcurrentHashMap<String, Call>()
    private val cancelReasons = ConcurrentHashMap<String, ModelStreamCancelReason>()

    override fun stream(request: ModelStreamRequest): Flow<ModelStreamEvent> = flow {
        val adapter = ModelStreamProviderAdapters.create(request.provider)
        val state = StreamEmissionState()
        val client = baseClient.newBuilder()
            .connectTimeout(request.connectTimeoutMs, TimeUnit.MILLISECONDS)
            .readTimeout(request.readTimeoutMs, TimeUnit.MILLISECONDS)
            .build()
        val httpRequest = Request.Builder()
            .url(request.endpoint)
            .post(request.bodyJson.toRequestBody(JSON_MEDIA_TYPE))
            .header("Accept", if (request.transport == ModelStreamTransport.COMPLETE_JSON) "application/json" else "text/event-stream")
            .apply { request.headers.forEach { (name, value) -> header(name, value) } }
            .build()
        val call = client.newCall(httpRequest)
        val existing = activeCalls.putIfAbsent(request.requestId, call)
        if (existing != null) {
            emit(
                ModelStreamEvent.Failed(
                    request.requestId,
                    ModelStreamError("DUPLICATE_REQUEST_ID", "A stream with this request ID is already active")
                )
            )
            return@flow
        }
        try {
            call.execute().use { response ->
                throwIfCancelled(request.requestId)
                emit(
                    ModelStreamEvent.Connected(
                        request.requestId,
                        response.code,
                        elapsedRealtimeMs()
                    )
                )
                val body = response.body
                if (!response.isSuccessful) {
                    val errorBody = body?.string().orEmpty()
                    emit(
                        ModelStreamEvent.Failed(
                            request.requestId,
                            ModelStreamError(
                                code = httpErrorCode(response.code, errorBody),
                                message = providerErrorMessage(errorBody).ifBlank { "HTTP ${response.code}" },
                                httpStatus = response.code,
                                retryable = response.code == 408 || response.code == 429 || response.code >= 500
                            )
                        )
                    )
                    return@use
                }
                if (body == null) {
                    emit(ModelStreamEvent.Failed(request.requestId, ModelStreamError("EMPTY_BODY", "Provider returned no response body")))
                    return@use
                }
                if (request.transport == ModelStreamTransport.COMPLETE_JSON) {
                    emitParsedFrame(request.requestId, adapter.parseCompleteJson(body.string()), state)
                } else {
                    val reader = ModelStreamFrameReader(body.source(), request.transport)
                    while (!state.sawTerminal) {
                        val next = reader.next() ?: break
                        throwIfCancelled(request.requestId)
                        if (emitParsedFrame(request.requestId, adapter.parse(next.data, next.eventName), state)) break
                    }
                }
                if (!state.sawTerminal) {
                    throwIfCancelled(request.requestId)
                    if (!state.finishReason.isNullOrBlank()) {
                        emit(ModelStreamEvent.Completed(request.requestId, state.finishReason, elapsedRealtimeMs()))
                    } else {
                        emit(
                            ModelStreamEvent.Failed(
                                request.requestId,
                                ModelStreamError(
                                    code = "STREAM_INTERRUPTED",
                                    message = "The provider stream ended before a completion event",
                                    retryable = true,
                                    partialResponse = state.emittedPayload
                                )
                            )
                        )
                    }
                }
            }
        } catch (cancelled: CancellationException) {
            call.cancel()
            throw cancelled
        } catch (error: IOException) {
            val cancelledBy = cancelReasons.remove(request.requestId)
            if (cancelledBy != null || call.isCanceled()) {
                emit(
                    ModelStreamEvent.Failed(
                        request.requestId,
                        ModelStreamError(
                            code = "CANCELLED",
                            message = cancelledBy?.name.orEmpty().ifBlank { "Request cancelled" },
                            partialResponse = state.emittedPayload
                        )
                    )
                )
            } else {
                emit(
                    ModelStreamEvent.Failed(
                        request.requestId,
                        ModelStreamError(
                            code = "NETWORK_ERROR",
                            message = error.message.orEmpty().ifBlank { "Network stream failed" },
                            retryable = true,
                            partialResponse = state.emittedPayload
                        )
                    )
                )
            }
        } finally {
            activeCalls.remove(request.requestId, call)
            cancelReasons.remove(request.requestId)
        }
    }.flowOn(Dispatchers.IO)

    override suspend fun cancel(requestId: String, reason: ModelStreamCancelReason) {
        val call = activeCalls.remove(requestId) ?: return
        cancelReasons[requestId] = reason
        call.cancel()
    }

    fun activeRequestIds(): Set<String> = activeCalls.keys.toSet()

    private suspend fun FlowCollector<ModelStreamEvent>.emitParsedFrame(
        requestId: String,
        frame: ParsedModelStreamFrame,
        state: StreamEmissionState
    ): Boolean {
        val providerSequence = frame.providerSequence
        if (providerSequence != null && state.lastProviderSequence != null &&
            providerSequence <= requireNotNull(state.lastProviderSequence)
        ) {
            return false
        }
        if (providerSequence != null) state.lastProviderSequence = providerSequence
        throwIfCancelled(requestId)
        val frameError = frame.error
        if (frameError != null) {
            emit(ModelStreamEvent.Failed(requestId, frameError.copy(partialResponse = state.emittedPayload)))
            state.sawTerminal = true
            return true
        }
        for (delta in frame.textDeltas) {
            if (delta.isEmpty()) continue
            state.emittedPayload = true
            emit(
                ModelStreamEvent.TextDelta(
                    requestId,
                    state.sequence.incrementAndGet(),
                    delta,
                    elapsedRealtimeMs()
                )
            )
        }
        for (payload in frame.toolDeltas) {
            state.emittedPayload = true
            emit(
                ModelStreamEvent.ToolCallDelta(
                    requestId,
                    state.sequence.incrementAndGet(),
                    payload
                )
            )
        }
        frame.usage?.let { emit(ModelStreamEvent.Usage(requestId, it)) }
        if (!frame.finishReason.isNullOrBlank()) state.finishReason = frame.finishReason
        if (!frame.terminal) return false
        throwIfCancelled(requestId)
        state.sawTerminal = true
        emit(ModelStreamEvent.Completed(requestId, state.finishReason, elapsedRealtimeMs()))
        return true
    }

    private fun throwIfCancelled(requestId: String) {
        if (cancelReasons.containsKey(requestId)) throw IOException("Request cancelled")
    }

    private companion object {
        val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()

        fun httpErrorCode(status: Int, body: String): String {
            val lower = body.lowercase()
            return if (status in setOf(404, 405, 415, 501) || ("stream" in lower && "support" in lower)) {
                "STREAM_UNSUPPORTED"
            } else {
                "HTTP_$status"
            }
        }

        fun providerErrorMessage(body: String): String = runCatching {
            val json = org.json.JSONObject(body)
            val error = json.optJSONObject("error") ?: json
            error.optString("message").ifBlank { body.take(1_000) }
        }.getOrDefault(body.take(1_000))
    }
}

private data class StreamEmissionState(
    val sequence: AtomicLong = AtomicLong(0L),
    var emittedPayload: Boolean = false,
    var sawTerminal: Boolean = false,
    var finishReason: String? = null,
    var lastProviderSequence: Long? = null
)

private data class ModelStreamFrame(val eventName: String?, val data: String)

private class ModelStreamFrameReader(
    private val source: BufferedSource,
    private val transport: ModelStreamTransport
) {
    fun next(): ModelStreamFrame? = when (transport) {
        ModelStreamTransport.JSON_LINES -> nextJsonLine()
        ModelStreamTransport.SSE -> nextSseEvent()
        ModelStreamTransport.COMPLETE_JSON -> null
    }

    private fun nextJsonLine(): ModelStreamFrame? {
        while (true) {
            val line = source.readUtf8Line() ?: return null
            if (line.isNotBlank()) return ModelStreamFrame(null, line.trim())
        }
    }

    private fun nextSseEvent(): ModelStreamFrame? {
        var eventName: String? = null
        val data = StringBuilder()
        while (true) {
            val line = source.readUtf8Line()
            if (line == null) {
                return data.takeIf { it.isNotEmpty() }?.let { ModelStreamFrame(eventName, it.toString()) }
            }
            if (line.isEmpty()) {
                if (data.isNotEmpty()) return ModelStreamFrame(eventName, data.toString())
                eventName = null
                continue
            }
            when {
                line.startsWith(":") -> Unit
                line.startsWith("event:") -> eventName = line.substringAfter(':').trim()
                line.startsWith("data:") -> {
                    if (data.isNotEmpty()) data.append('\n')
                    data.append(line.substringAfter(':').removePrefix(" "))
                }
                line.firstOrNull() == '{' || line.firstOrNull() == '[' -> {
                    if (data.isNotEmpty()) data.append('\n')
                    data.append(line)
                }
            }
        }
    }
}
