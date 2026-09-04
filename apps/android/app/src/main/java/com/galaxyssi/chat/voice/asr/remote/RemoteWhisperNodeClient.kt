package com.galaxyssi.chat.voice.asr.remote

import com.galaxyssi.chat.GalaxySSIMqttClient
import com.galaxyssi.chat.voice.TranscriptHypothesis
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeout
import org.json.JSONObject
import java.util.LinkedHashMap
import java.util.concurrent.ConcurrentHashMap

fun interface RemoteWhisperTransport {
    fun publish(desktopId: String, payload: JSONObject): Boolean
}

object GalaxySSILinkRemoteWhisperTransport : RemoteWhisperTransport {
    override fun publish(desktopId: String, payload: JSONObject): Boolean =
        GalaxySSIMqttClient.publishRemoteWhisperPacket(desktopId, payload)
}

class RemoteWhisperException(val code: String, message: String) : Exception(message)

class RemoteWhisperNodeClient(
    private val transport: RemoteWhisperTransport,
    private val clockMillis: () -> Long = System::currentTimeMillis,
    private val timeoutMillis: Long = 180_000L
) {
    private data class Pending(
        val request: PreparedRemoteWhisperRequest,
        val fastRevision: Int,
        val deferred: CompletableDeferred<RemoteWhisperOutcome>
    )

    private val pending = ConcurrentHashMap<String, Pending>()
    private val completedLock = Any()
    private val completed = object : LinkedHashMap<String, Unit>(96, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Unit>?): Boolean = size > 96
    }

    suspend fun transcribe(
        node: RemoteWhisperNodeCapability,
        clientId: String,
        voiceSessionId: String,
        transcriptId: String,
        pcm16: ShortArray,
        sampleRateHz: Int,
        language: String,
        fastRevision: Int
    ): TranscriptHypothesis {
        val prepared = RemoteWhisperProtocol.prepare(
            node = node,
            clientId = clientId,
            voiceSessionId = voiceSessionId,
            transcriptId = transcriptId,
            pcm16 = pcm16,
            sampleRateHz = sampleRateHz,
            language = language,
            authorizedAtMillis = clockMillis()
        )
        val deferred = CompletableDeferred<RemoteWhisperOutcome>()
        val holder = Pending(prepared, fastRevision, deferred)
        check(pending.putIfAbsent(prepared.requestId, holder) == null) { "Duplicate remote Whisper request" }
        var fullyPublished = false
        try {
            if (!transport.publish(prepared.desktopId, prepared.manifest)) {
                throw RemoteWhisperException("publish_failed", "Remote Whisper manifest could not be sent")
            }
            prepared.chunks.forEach { chunk ->
                if (!transport.publish(prepared.desktopId, chunk)) {
                    throw RemoteWhisperException("publish_failed", "Remote Whisper audio transfer was interrupted")
                }
            }
            fullyPublished = true
            return when (val outcome = withTimeout(timeoutMillis) { deferred.await() }) {
                is RemoteWhisperOutcome.Completed -> TranscriptHypothesis(
                    text = outcome.transcript.text,
                    revision = fastRevision + 1,
                    provider = "faster-whisper@${node.desktopName}",
                    modelProfileId = outcome.transcript.profile.id,
                    confidence = outcome.transcript.confidence,
                    transcriptId = transcriptId,
                    isFinal = true
                )
                is RemoteWhisperOutcome.Failed -> throw RemoteWhisperException(
                    outcome.code,
                    outcome.message
                )
            }
        } catch (error: CancellationException) {
            transport.publish(prepared.desktopId, RemoteWhisperProtocol.cancelPayload(prepared))
            throw error
        } catch (error: Throwable) {
            if (!fullyPublished || error is kotlinx.coroutines.TimeoutCancellationException) {
                transport.publish(prepared.desktopId, RemoteWhisperProtocol.cancelPayload(prepared))
            }
            throw error
        } finally {
            pending.remove(prepared.requestId, holder)
        }
    }

    fun handleIncoming(payload: JSONObject, sourceDesktopId: String): Boolean {
        val type = payload.optString("type")
        if (type !in setOf(REMOTE_WHISPER_RESULT, REMOTE_WHISPER_ERROR, REMOTE_WHISPER_CANCELLED)) return false
        val requestId = payload.optString("request_id")
        val holder = pending[requestId]
        if (holder == null) {
            synchronized(completedLock) { completed[requestId] = Unit }
            return true
        }
        if (sourceDesktopId.isNotBlank() && sourceDesktopId != holder.request.desktopId) {
            holder.deferred.complete(
                RemoteWhisperOutcome.Failed(
                    requestId,
                    "response_identity_mismatch",
                    "Remote node identity could not be verified"
                )
            )
            return true
        }
        val outcome = RemoteWhisperProtocol.parseOutcome(payload, holder.request)
            ?: RemoteWhisperOutcome.Failed(requestId, "response_invalid", "Remote response is invalid")
        if (holder.deferred.complete(outcome)) {
            synchronized(completedLock) { completed[requestId] = Unit }
        }
        return true
    }

    fun cancelAll(): Int {
        val active = pending.values.toList()
        active.forEach { holder ->
            transport.publish(holder.request.desktopId, RemoteWhisperProtocol.cancelPayload(holder.request))
            holder.deferred.cancel(CancellationException("Remote Whisper session closed"))
        }
        pending.clear()
        return active.size
    }

    fun pendingCount(): Int = pending.size
}
