package com.galaxyssi.chat.voice.asr.online

import com.galaxyssi.chat.voice.asr.AsrAvailability
import com.galaxyssi.chat.voice.asr.AsrSessionConfig
import com.galaxyssi.chat.voice.asr.AsrTransport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.security.MessageDigest

class EphemeralAsrCredential(
    val providerId: String,
    val providerSessionId: String,
    val websocketUrl: String,
    authorizationToken: String,
    val authorizationHeader: String = "Authorization",
    val authorizationScheme: String = "Bearer",
    val expiresAtEpochMs: Long,
    val supportedTransports: Set<AsrTransport> = setOf(AsrTransport.WEBSOCKET),
    val serverDataDeletionSupported: Boolean = false
) : AutoCloseable {
    private val secret = authorizationToken.toCharArray()

    init {
        require(providerId.isNotBlank())
        require(providerSessionId.isNotBlank())
        require(websocketUrl.startsWith("wss://") || isLoopbackWebSocket(websocketUrl)) {
            "Realtime ASR requires a secure WebSocket endpoint"
        }
        require(expiresAtEpochMs > 0L)
        require(supportedTransports.isNotEmpty())
    }

    fun isExpired(nowEpochMs: Long, minimumRemainingMs: Long = 0L): Boolean =
        expiresAtEpochMs - nowEpochMs <= minimumRemainingMs

    fun authorizationValue(): String {
        check(secret.any { it != '\u0000' }) { "Realtime ASR credential has been cleared" }
        val token = secret.concatToString()
        return authorizationScheme.trim().takeIf(String::isNotBlank)?.let { "$it $token" } ?: token
    }

    fun duplicate(): EphemeralAsrCredential {
        check(secret.any { it != '\u0000' }) { "Realtime ASR credential has been cleared" }
        return EphemeralAsrCredential(
            providerId = providerId,
            providerSessionId = providerSessionId,
            websocketUrl = websocketUrl,
            authorizationToken = secret.concatToString(),
            authorizationHeader = authorizationHeader,
            authorizationScheme = authorizationScheme,
            expiresAtEpochMs = expiresAtEpochMs,
            supportedTransports = supportedTransports,
            serverDataDeletionSupported = serverDataDeletionSupported
        )
    }

    fun redactedKeyId(): String = MessageDigest.getInstance("SHA-256")
        .digest(secret.concatToString().toByteArray(Charsets.UTF_8))
        .take(4)
        .joinToString("") { byte -> "%02x".format(byte) }

    override fun close() {
        secret.fill('\u0000')
    }

    override fun toString(): String =
        "EphemeralAsrCredential(providerId=$providerId, providerSessionId=$providerSessionId, " +
            "expiresAtEpochMs=$expiresAtEpochMs, credential=redacted)"

    private fun isLoopbackWebSocket(value: String): Boolean =
        value.startsWith("ws://127.0.0.1") || value.startsWith("ws://localhost") || value.startsWith("ws://[::1]")
}

interface RealtimeAsrCredentialSource : AutoCloseable {
    suspend fun availability(config: AsrSessionConfig): AsrAvailability
    suspend fun issue(config: AsrSessionConfig): EphemeralAsrCredential
    override fun close() = Unit
}

class CachingRealtimeAsrCredentialSource(
    private val delegate: RealtimeAsrCredentialSource,
    private val nowEpochMs: () -> Long = System::currentTimeMillis,
    private val minimumRemainingMs: Long = 15_000L
) : RealtimeAsrCredentialSource {
    private val mutex = Mutex()
    private var cached: EphemeralAsrCredential? = null

    override suspend fun availability(config: AsrSessionConfig): AsrAvailability = delegate.availability(config)

    override suspend fun issue(config: AsrSessionConfig): EphemeralAsrCredential = mutex.withLock {
        cached?.takeUnless { it.isExpired(nowEpochMs(), minimumRemainingMs) }?.let {
            return@withLock it.duplicate()
        }
        cached?.close()
        delegate.issue(config).also { cached = it }.duplicate()
    }

    override fun close() {
        cached?.close()
        cached = null
        delegate.close()
    }
}

class HttpRealtimeAsrCredentialSource(
    private val client: OkHttpClient,
    private val brokerUrl: String,
    private val requestHeaders: () -> Map<String, String> = { emptyMap() },
    private val nowEpochMs: () -> Long = System::currentTimeMillis
) : RealtimeAsrCredentialSource {
    override suspend fun availability(config: AsrSessionConfig): AsrAvailability = when {
        brokerUrl.isBlank() -> AsrAvailability.unavailable("credential_broker_not_configured")
        !brokerUrl.startsWith("https://") && !isLoopbackHttp(brokerUrl) ->
            AsrAvailability.unavailable("credential_broker_must_use_https")
        else -> AsrAvailability.ready(AsrTransport.WEBSOCKET)
    }

    override suspend fun issue(config: AsrSessionConfig): EphemeralAsrCredential = withContext(Dispatchers.IO) {
        check(availability(config).available) { "Realtime ASR credential broker is unavailable" }
        val body = JSONObject()
            .put("schema_version", 1)
            .put("voice_session_id", config.voiceSessionId)
            .put("transcript_id", config.transcriptId)
            .put("language", config.language)
            .put("sample_rate_hz", config.sampleRateHz)
            .put("channel_count", config.channelCount)
            .put("request_server_data_deletion", config.privacy.requestServerDataDeletion)
            .toString()
            .toRequestBody(JSON_MEDIA_TYPE)
        val builder = Request.Builder().url(brokerUrl).post(body)
        requestHeaders().forEach { (name, value) ->
            if (name.isNotBlank() && value.isNotBlank()) builder.header(name, value)
        }
        client.newCall(builder.build()).execute().use { response ->
            check(response.isSuccessful) { "Realtime ASR credential request failed (${response.code})" }
            val json = JSONObject(response.body?.string().orEmpty())
            val expiresAt = json.optLong("expires_at_epoch_ms", 0L)
            check(expiresAt - nowEpochMs() >= 5_000L) { "Realtime ASR credential expires too soon" }
            val transports = json.optJSONArray("transports")?.let { values ->
                buildSet {
                    for (index in 0 until values.length()) {
                        runCatching { add(AsrTransport.valueOf(values.optString(index).uppercase())) }
                    }
                }
            }.orEmpty().ifEmpty { setOf(AsrTransport.WEBSOCKET) }
            EphemeralAsrCredential(
                providerId = json.getString("provider_id"),
                providerSessionId = json.getString("provider_session_id"),
                websocketUrl = json.getString("websocket_url"),
                authorizationToken = json.getString("access_token"),
                authorizationHeader = json.optString("authorization_header", "Authorization"),
                authorizationScheme = json.optString("authorization_scheme", "Bearer"),
                expiresAtEpochMs = expiresAt,
                supportedTransports = transports,
                serverDataDeletionSupported = json.optBoolean("server_data_deletion_supported", false)
            )
        }
    }

    private fun isLoopbackHttp(value: String): Boolean =
        value.startsWith("http://127.0.0.1") || value.startsWith("http://localhost") || value.startsWith("http://[::1]")

    private companion object {
        val JSON_MEDIA_TYPE = "application/json; charset=utf-8".toMediaType()
    }
}
