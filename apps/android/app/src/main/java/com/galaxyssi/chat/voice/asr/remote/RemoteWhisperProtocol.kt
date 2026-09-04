package com.galaxyssi.chat.voice.asr.remote

import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID

const val REMOTE_WHISPER_PROTOCOL = "galaxyssi.remote-whisper/1.0"
const val REMOTE_WHISPER_REQUEST = "remote_whisper_request"
const val REMOTE_WHISPER_CHUNK = "remote_whisper_chunk"
const val REMOTE_WHISPER_CANCEL = "remote_whisper_cancel"
const val REMOTE_WHISPER_RESULT = "remote_whisper_result"
const val REMOTE_WHISPER_ERROR = "remote_whisper_error"
const val REMOTE_WHISPER_CANCELLED = "remote_whisper_cancelled"
const val REMOTE_WHISPER_AUDIO_FORMAT = "pcm_s16le_16000_mono"
const val REMOTE_WHISPER_CONSENT_SCOPE = "voice.remote_whisper.correction"
const val REMOTE_WHISPER_CHUNK_BYTES = 128 * 1024

data class RemoteWhisperProfile(
    val id: String,
    val modelName: String,
    val sha256: String,
    val shaKind: String
) {
    init {
        require(id.isNotBlank())
        require(sha256.isSha256())
    }
}

data class RemoteWhisperNodeCapability(
    val desktopId: String,
    val desktopName: String,
    val clientRouteId: String,
    val activeProfile: RemoteWhisperProfile,
    val maxPcmBytes: Int,
    val generatedAtMillis: Long
) {
    init {
        require(desktopId.isNotBlank())
        require(clientRouteId.isNotBlank())
        require(maxPcmBytes >= 32_000)
    }
}

data class PreparedRemoteWhisperRequest(
    val requestId: String,
    val desktopId: String,
    val voiceSessionId: String,
    val transcriptId: String,
    val audioSha256: String,
    val profile: RemoteWhisperProfile,
    val manifest: JSONObject,
    val chunks: List<JSONObject>
)

data class RemoteWhisperTranscript(
    val requestId: String,
    val voiceSessionId: String,
    val transcriptId: String,
    val desktopId: String,
    val text: String,
    val language: String,
    val confidence: Float?,
    val profile: RemoteWhisperProfile,
    val audioSha256: String,
    val processingMillis: Long,
    val cleanupVerified: Boolean
)

sealed interface RemoteWhisperOutcome {
    val requestId: String

    data class Completed(val transcript: RemoteWhisperTranscript) : RemoteWhisperOutcome {
        override val requestId: String get() = transcript.requestId
    }

    data class Failed(
        override val requestId: String,
        val code: String,
        val message: String,
        val cancelled: Boolean = false
    ) : RemoteWhisperOutcome
}

object RemoteWhisperProtocol {
    fun parseCapability(
        payload: JSONObject,
        sourceDesktopId: String,
        generatedAtMillis: Long = payload.optLong("generated_at", System.currentTimeMillis())
    ): RemoteWhisperNodeCapability? {
        if (payload.optString("type") != "capability_manifest") return null
        val capabilities = payload.optJSONObject("protocol_capabilities") ?: return null
        if (!capabilities.optBoolean("remote_whisper", false)) return null
        val node = capabilities.optJSONObject("remote_whisper_node") ?: return null
        if (!node.optBoolean("available", false) || node.optString("protocol") != REMOTE_WHISPER_PROTOCOL) return null
        val executionDevice = node.optJSONObject("execution_device") ?: return null
        val desktopId = sourceDesktopId.ifBlank { executionDevice.optString("device_id") }
        if (desktopId.isBlank() || desktopId != executionDevice.optString("device_id")) return null
        val authorization = node.optJSONObject("authorization") ?: return null
        if (!authorization.optBoolean("explicit_user_consent_required") ||
            !authorization.optBoolean("paired_device_identity_required") ||
            !authorization.optBoolean("only_my_devices") ||
            authorization.optString("scope") != REMOTE_WHISPER_CONSENT_SCOPE
        ) return null
        val profile = parseProfile(node.optJSONObject("active_profile")) ?: return null
        val audioSupported = node.optJSONArray("supported_audio")?.let { values ->
            (0 until values.length()).any { values.optString(it) == REMOTE_WHISPER_AUDIO_FORMAT }
        } == true
        if (!audioSupported) return null
        return RemoteWhisperNodeCapability(
            desktopId = desktopId,
            desktopName = executionDevice.optString("device_name", "GalaxySSI Desktop"),
            clientRouteId = authorization.optString("client_route_id"),
            activeProfile = profile,
            maxPcmBytes = node.optInt("max_pcm_bytes", 0),
            generatedAtMillis = generatedAtMillis
        )
    }

    fun prepare(
        node: RemoteWhisperNodeCapability,
        clientId: String,
        voiceSessionId: String,
        transcriptId: String,
        pcm16: ShortArray,
        sampleRateHz: Int,
        language: String,
        authorizedAtMillis: Long,
        requestId: String = UUID.randomUUID().toString(),
        chunkBytes: Int = REMOTE_WHISPER_CHUNK_BYTES
    ): PreparedRemoteWhisperRequest {
        require(UUID.fromString(requestId).toString() == requestId.lowercase())
        require(clientId.isNotBlank())
        require(voiceSessionId.isNotBlank() && transcriptId.isNotBlank())
        require(sampleRateHz == 16_000)
        require(pcm16.isNotEmpty())
        require(chunkBytes in 2..REMOTE_WHISPER_CHUNK_BYTES && chunkBytes % 2 == 0)
        val pcmBuffer = ByteBuffer.allocate(pcm16.size * 2).order(ByteOrder.LITTLE_ENDIAN)
        pcm16.forEach { sample -> pcmBuffer.putShort(sample) }
        val pcm = pcmBuffer.array()
        require(pcm.size <= node.maxPcmBytes) { "Remote PCM exceeds node limit" }
        val audioSha = pcm.sha256()
        val slices = pcm.asListOfByteArrays(chunkBytes)
        val audio = JSONObject()
            .put("format", REMOTE_WHISPER_AUDIO_FORMAT)
            .put("sample_rate_hz", sampleRateHz)
            .put("channels", 1)
            .put("sample_count", pcm16.size)
            .put("byte_count", pcm.size)
            .put("duration_ms", pcm16.size.toLong() * 1_000L / sampleRateHz)
            .put("sha256", audioSha)
            .put("chunk_count", slices.size)
            .put("chunk_size_bytes", chunkBytes)
        val manifest = JSONObject()
            .put("type", REMOTE_WHISPER_REQUEST)
            .put("protocol", REMOTE_WHISPER_PROTOCOL)
            .put("request_id", requestId)
            .put("voice_session_id", voiceSessionId)
            .put("transcript_id", transcriptId)
            .put("client_route_id", node.clientRouteId)
            .put("client_id", clientId)
            .put("language", language.ifBlank { "auto" })
            .put("authorization", JSONObject()
                .put("explicit", true)
                .put("only_my_devices", true)
                .put("scope", REMOTE_WHISPER_CONSENT_SCOPE)
                .put("authorized_at_ms", authorizedAtMillis)
                .put("request_audio_deletion", true))
            .put("model", JSONObject()
                .put("profile_id", node.activeProfile.id)
                .put("profile_sha256", node.activeProfile.sha256))
            .put("audio", audio)
        val chunks = slices.mapIndexed { index, slice ->
            JSONObject()
                .put("type", REMOTE_WHISPER_CHUNK)
                .put("protocol", REMOTE_WHISPER_PROTOCOL)
                .put("request_id", requestId)
                .put("client_route_id", node.clientRouteId)
                .put("client_id", clientId)
                .put("chunk_index", index)
                .put("chunk_count", slices.size)
                .put("chunk_sha256", slice.sha256())
                .put("data_base64", Base64.getEncoder().encodeToString(slice))
        }
        pcm.fill(0)
        slices.forEach { it.fill(0) }
        return PreparedRemoteWhisperRequest(
            requestId = requestId,
            desktopId = node.desktopId,
            voiceSessionId = voiceSessionId,
            transcriptId = transcriptId,
            audioSha256 = audioSha,
            profile = node.activeProfile,
            manifest = manifest,
            chunks = chunks
        )
    }

    fun parseOutcome(
        payload: JSONObject,
        expected: PreparedRemoteWhisperRequest
    ): RemoteWhisperOutcome? {
        val type = payload.optString("type")
        if (type !in setOf(REMOTE_WHISPER_RESULT, REMOTE_WHISPER_ERROR, REMOTE_WHISPER_CANCELLED)) return null
        if (payload.optString("protocol") != REMOTE_WHISPER_PROTOCOL ||
            payload.optString("request_id") != expected.requestId ||
            payload.optString("desktop_id") != expected.desktopId
        ) return RemoteWhisperOutcome.Failed(expected.requestId, "response_identity_mismatch", "Remote node identity could not be verified")
        if (type != REMOTE_WHISPER_RESULT) {
            return RemoteWhisperOutcome.Failed(
                requestId = expected.requestId,
                code = payload.optString("error_code").ifBlank {
                    if (type == REMOTE_WHISPER_CANCELLED) "cancelled" else "remote_failed"
                },
                message = payload.optString("error_message").ifBlank { "Remote transcription failed" },
                cancelled = type == REMOTE_WHISPER_CANCELLED || payload.optString("status") == "cancelled"
            )
        }
        val profileId = payload.optString("model_profile_id")
        val profileSha = payload.optString("model_profile_sha256").lowercase()
        if (profileId.isBlank() || !profileSha.isSha256()) {
            return RemoteWhisperOutcome.Failed(
                expected.requestId,
                "response_integrity_failed",
                "Remote model identity could not be verified"
            )
        }
        val profile = RemoteWhisperProfile(
            id = profileId,
            modelName = profileId,
            sha256 = profileSha,
            shaKind = expected.profile.shaKind
        )
        if (profile.id != expected.profile.id || profile.sha256 != expected.profile.sha256 ||
            payload.optString("voice_session_id") != expected.voiceSessionId ||
            payload.optString("transcript_id") != expected.transcriptId ||
            payload.optString("audio_sha256") != expected.audioSha256
        ) return RemoteWhisperOutcome.Failed(expected.requestId, "response_integrity_failed", "Remote transcript binding could not be verified")
        val cleanupVerified = payload.optJSONObject("cleanup")?.optBoolean("verified", false) == true
        if (!cleanupVerified) {
            return RemoteWhisperOutcome.Failed(
                expected.requestId,
                "cleanup_not_verified",
                "Remote audio cleanup could not be verified"
            )
        }
        val content = payload.optString("content").trim()
        if (content.isBlank()) return RemoteWhisperOutcome.Failed(expected.requestId, "empty_transcript", "Remote transcription returned no speech")
        return RemoteWhisperOutcome.Completed(
            RemoteWhisperTranscript(
                requestId = expected.requestId,
                voiceSessionId = expected.voiceSessionId,
                transcriptId = expected.transcriptId,
                desktopId = expected.desktopId,
                text = content,
                language = payload.optString("language", "auto"),
                confidence = payload.optDouble("confidence", Double.NaN).takeIf { !it.isNaN() }?.toFloat(),
                profile = profile,
                audioSha256 = expected.audioSha256,
                processingMillis = payload.optLong("processing_ms", 0L).coerceAtLeast(0L),
                cleanupVerified = cleanupVerified
            )
        )
    }

    fun cancelPayload(request: PreparedRemoteWhisperRequest): JSONObject = JSONObject()
        .put("type", REMOTE_WHISPER_CANCEL)
        .put("protocol", REMOTE_WHISPER_PROTOCOL)
        .put("request_id", request.requestId)
        .put("client_route_id", request.manifest.optString("client_route_id"))
        .put("time", System.currentTimeMillis())

    private fun parseProfile(value: JSONObject?): RemoteWhisperProfile? {
        value ?: return null
        return runCatching {
            RemoteWhisperProfile(
                id = value.getString("profile_id"),
                modelName = value.optString("model_name", value.getString("profile_id")),
                sha256 = value.getString("profile_sha256").lowercase(),
                shaKind = value.optString("sha_kind", "profile_manifest_sha256")
            )
        }.getOrNull()
    }
}

private fun ByteArray.asListOfByteArrays(chunkBytes: Int): List<ByteArray> =
    (indices step chunkBytes).map { start -> copyOfRange(start, minOf(size, start + chunkBytes)) }

private fun ByteArray.sha256(): String = MessageDigest.getInstance("SHA-256")
    .digest(this)
    .joinToString("") { "%02x".format(it) }

private fun String.isSha256(): Boolean = matches(Regex("[0-9a-f]{64}"))
