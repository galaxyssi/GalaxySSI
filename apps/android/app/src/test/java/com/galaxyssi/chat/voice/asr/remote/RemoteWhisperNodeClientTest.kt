package com.galaxyssi.chat.voice.asr.remote

import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList

class RemoteWhisperNodeClientTest {
    @Test
    fun `verified result completes one correction and duplicate is consumed`() = runBlocking {
        val packets = CopyOnWriteArrayList<JSONObject>()
        val client = RemoteWhisperNodeClient(
            transport = RemoteWhisperTransport { _, payload -> packets += JSONObject(payload.toString()); true },
            clockMillis = { NOW },
            timeoutMillis = 2_000L
        )
        val transcript = async {
            client.transcribe(
                node = node(),
                clientId = CLIENT_ID,
                voiceSessionId = "voice-1",
                transcriptId = "transcript-1",
                pcm16 = ShortArray(16_000) { 1 },
                sampleRateHz = 16_000,
                language = "en",
                fastRevision = 4
            )
        }
        while (packets.none { it.optString("type") == REMOTE_WHISPER_REQUEST }) delay(5)
        val manifest = packets.first { it.optString("type") == REMOTE_WHISPER_REQUEST }
        val reply = resultFor(manifest)
        assertTrue(client.handleIncoming(reply, DESKTOP_ID))
        assertTrue(client.handleIncoming(reply, DESKTOP_ID))

        val value = transcript.await()
        assertEquals("accurate transcript", value.text)
        assertEquals(5, value.revision)
        assertEquals(0, client.pendingCount())
    }

    @Test
    fun `timeout sends cancellation and never invents a transcript`() = runBlocking {
        val packets = CopyOnWriteArrayList<JSONObject>()
        val client = RemoteWhisperNodeClient(
            transport = RemoteWhisperTransport { _, payload -> packets += JSONObject(payload.toString()); true },
            clockMillis = { NOW },
            timeoutMillis = 30L
        )
        val error = runCatching {
            client.transcribe(
                node(), CLIENT_ID, "voice-2", "transcript-2",
                ShortArray(1_600) { 1 }, 16_000, "en", 1
            )
        }.exceptionOrNull()

        assertTrue(error is kotlinx.coroutines.TimeoutCancellationException)
        assertTrue(packets.any { it.optString("type") == REMOTE_WHISPER_CANCEL })
        assertEquals(0, client.pendingCount())
    }

    private fun node() = RemoteWhisperNodeCapability(
        desktopId = DESKTOP_ID,
        desktopName = "My Desktop",
        clientRouteId = CLIENT_ROUTE,
        activeProfile = RemoteWhisperProfile("medium", "medium", PROFILE_SHA, "profile_manifest_sha256"),
        maxPcmBytes = 3_840_000,
        generatedAtMillis = NOW
    )

    private fun resultFor(manifest: JSONObject): JSONObject = JSONObject()
        .put("type", REMOTE_WHISPER_RESULT)
        .put("protocol", REMOTE_WHISPER_PROTOCOL)
        .put("request_id", manifest.getString("request_id"))
        .put("desktop_id", DESKTOP_ID)
        .put("status", "completed")
        .put("voice_session_id", manifest.getString("voice_session_id"))
        .put("transcript_id", manifest.getString("transcript_id"))
        .put("content", "accurate transcript")
        .put("language", "en")
        .put("confidence", 0.95)
        .put("model_profile_id", "medium")
        .put("model_profile_sha256", PROFILE_SHA)
        .put("audio_sha256", manifest.getJSONObject("audio").getString("sha256"))
        .put("processing_ms", 700)
        .put("cleanup", JSONObject().put("verified", true))

    companion object {
        private const val NOW = 1_900_000_000_000L
        private const val DESKTOP_ID = "desktop-test"
        private const val CLIENT_ID = "galaxyssi:test-phone"
        private const val CLIENT_ROUTE = "abcdefghijklmnopqrstuv"
        private val PROFILE_SHA = "a".repeat(64)
    }
}
