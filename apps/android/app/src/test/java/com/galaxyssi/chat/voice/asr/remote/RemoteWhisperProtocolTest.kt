package com.galaxyssi.chat.voice.asr.remote

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID

class RemoteWhisperProtocolTest {
    @Test
    fun `capability requires verified paired-device privacy contract`() {
        val payload = manifest()
        val node = RemoteWhisperProtocol.parseCapability(payload, DESKTOP_ID, NOW)
        assertNotNull(node)
        assertEquals("medium", node?.activeProfile?.id)
        assertEquals(CLIENT_ROUTE, node?.clientRouteId)

        payload.getJSONObject("protocol_capabilities")
            .getJSONObject("remote_whisper_node")
            .getJSONObject("authorization")
            .put("only_my_devices", false)
        assertNull(RemoteWhisperProtocol.parseCapability(payload, DESKTOP_ID, NOW))
    }

    @Test
    fun `pcm is split into bounded independently hashed packets`() {
        val node = requireNotNull(RemoteWhisperProtocol.parseCapability(manifest(), DESKTOP_ID, NOW))
        val pcm = ShortArray(20_000) { index -> index.toShort() }
        val prepared = RemoteWhisperProtocol.prepare(
            node = node,
            clientId = CLIENT_ID,
            voiceSessionId = "voice-1",
            transcriptId = "transcript-1",
            pcm16 = pcm,
            sampleRateHz = 16_000,
            language = "en",
            authorizedAtMillis = NOW,
            requestId = UUID.randomUUID().toString(),
            chunkBytes = 4_096
        )

        assertEquals(10, prepared.chunks.size)
        assertFalse(prepared.manifest.getJSONObject("audio").has("data_base64"))
        val rebuilt = prepared.chunks.flatMap { packet ->
            val bytes = Base64.getDecoder().decode(packet.getString("data_base64"))
            assertEquals(sha256(bytes), packet.getString("chunk_sha256"))
            bytes.toList()
        }.toByteArray()
        assertEquals(40_000, rebuilt.size)
        assertEquals(prepared.audioSha256, sha256(rebuilt))
    }

    @Test
    fun `result must bind desktop model session transcript and audio identities`() {
        val node = requireNotNull(RemoteWhisperProtocol.parseCapability(manifest(), DESKTOP_ID, NOW))
        val prepared = RemoteWhisperProtocol.prepare(
            node,
            CLIENT_ID,
            "voice-1",
            "transcript-1",
            ShortArray(16_000) { 2 },
            16_000,
            "en",
            NOW
        )
        val valid = result(prepared)
        val outcome = RemoteWhisperProtocol.parseOutcome(valid, prepared)
        assertTrue(outcome is RemoteWhisperOutcome.Completed)
        assertEquals("accurate transcript", (outcome as RemoteWhisperOutcome.Completed).transcript.text)

        valid.put("model_profile_sha256", "0".repeat(64))
        val rejected = RemoteWhisperProtocol.parseOutcome(valid, prepared)
        assertEquals("response_integrity_failed", (rejected as RemoteWhisperOutcome.Failed).code)
    }

    @Test
    fun `result is rejected when remote audio cleanup is not verified`() {
        val node = requireNotNull(RemoteWhisperProtocol.parseCapability(manifest(), DESKTOP_ID, NOW))
        val prepared = RemoteWhisperProtocol.prepare(
            node,
            CLIENT_ID,
            "voice-1",
            "transcript-1",
            ShortArray(16_000) { 2 },
            16_000,
            "en",
            NOW
        )
        val payload = result(prepared).put("cleanup", JSONObject().put("verified", false))

        val rejected = RemoteWhisperProtocol.parseOutcome(payload, prepared)

        assertEquals("cleanup_not_verified", (rejected as RemoteWhisperOutcome.Failed).code)
    }

    private fun manifest(): JSONObject = JSONObject()
        .put("type", "capability_manifest")
        .put("generated_at", NOW)
        .put("protocol_capabilities", JSONObject()
            .put("remote_whisper", true)
            .put("remote_whisper_node", JSONObject()
                .put("available", true)
                .put("protocol", REMOTE_WHISPER_PROTOCOL)
                .put("execution_device", JSONObject()
                    .put("device_id", DESKTOP_ID)
                    .put("device_name", "My Desktop"))
                .put("active_profile", JSONObject()
                    .put("profile_id", "medium")
                    .put("model_name", "medium")
                    .put("profile_sha256", PROFILE_SHA)
                    .put("sha_kind", "profile_manifest_sha256"))
                .put("supported_audio", JSONArray().put(REMOTE_WHISPER_AUDIO_FORMAT))
                .put("max_pcm_bytes", 3_840_000)
                .put("authorization", JSONObject()
                    .put("explicit_user_consent_required", true)
                    .put("paired_device_identity_required", true)
                    .put("only_my_devices", true)
                    .put("scope", REMOTE_WHISPER_CONSENT_SCOPE)
                    .put("client_route_id", CLIENT_ROUTE))))

    private fun result(prepared: PreparedRemoteWhisperRequest): JSONObject = JSONObject()
        .put("type", REMOTE_WHISPER_RESULT)
        .put("protocol", REMOTE_WHISPER_PROTOCOL)
        .put("request_id", prepared.requestId)
        .put("desktop_id", DESKTOP_ID)
        .put("status", "completed")
        .put("voice_session_id", prepared.voiceSessionId)
        .put("transcript_id", prepared.transcriptId)
        .put("content", "accurate transcript")
        .put("language", "en")
        .put("confidence", 0.96)
        .put("model_profile_id", prepared.profile.id)
        .put("model_profile_sha256", prepared.profile.sha256)
        .put("audio_sha256", prepared.audioSha256)
        .put("processing_ms", 850)
        .put("cleanup", JSONObject().put("verified", true))

    private fun sha256(value: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(value)
        .joinToString("") { "%02x".format(it) }

    companion object {
        private const val NOW = 1_900_000_000_000L
        private const val DESKTOP_ID = "desktop-test"
        private const val CLIENT_ID = "galaxyssi:test-phone"
        private const val CLIENT_ROUTE = "abcdefghijklmnopqrstuv"
        private val PROFILE_SHA = "a".repeat(64)
    }
}
