package com.galaxyssi.chat

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceProviderCapabilityPolicyTest {
    @Test
    fun fullyCapableDeviceReportsEveryProviderReady() {
        val snapshot = VoiceProviderCapabilityPolicy.evaluate(probe())

        assertTrue(snapshot.capabilities.all(VoiceProviderCapability::ready))
        assertEquals("tiny", snapshot[VoiceProviderCapabilityId.WHISPER_CPP].metadata["model_id"])
        assertEquals("2", snapshot[VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS].metadata["engine_count"])
    }

    @Test
    fun missingMicrophoneBlocksAsrButNotTts() {
        val snapshot = VoiceProviderCapabilityPolicy.evaluate(probe(hasMicrophone = false))

        listOf(
            VoiceProviderCapabilityId.WHISPER_CPP,
            VoiceProviderCapabilityId.ANDROID_SYSTEM_ASR,
            VoiceProviderCapabilityId.ANDROID_OFFLINE_ASR,
            VoiceProviderCapabilityId.CLOUD_ASR
        ).forEach { id ->
            assertEquals(VoiceProviderCapabilityState.UNAVAILABLE, snapshot[id].state)
            assertEquals(VoiceProviderCapabilityReason.MICROPHONE_MISSING, snapshot[id].reason)
        }
        assertTrue(snapshot[VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS].ready)
    }

    @Test
    fun microphonePermissionIsReportedAsActionableSetup() {
        val snapshot = VoiceProviderCapabilityPolicy.evaluate(
            probe(microphonePermissionGranted = false)
        )

        listOf(
            VoiceProviderCapabilityId.WHISPER_CPP,
            VoiceProviderCapabilityId.ANDROID_SYSTEM_ASR,
            VoiceProviderCapabilityId.ANDROID_OFFLINE_ASR,
            VoiceProviderCapabilityId.CLOUD_ASR
        ).forEach { id ->
            assertEquals(VoiceProviderCapabilityState.NEEDS_PERMISSION, snapshot[id].state)
        }
    }

    @Test
    fun whisperSeparatesRuntimeAndModelFailures() {
        val runtimeMissing = VoiceProviderCapabilityPolicy.evaluate(
            probe(whisperRuntimeAvailable = false)
        )[VoiceProviderCapabilityId.WHISPER_CPP]
        val modelMissing = VoiceProviderCapabilityPolicy.evaluate(
            probe(whisperModelAvailable = false)
        )[VoiceProviderCapabilityId.WHISPER_CPP]

        assertEquals(VoiceProviderCapabilityReason.WHISPER_RUNTIME_MISSING, runtimeMissing.reason)
        assertEquals(VoiceProviderCapabilityState.NEEDS_DOWNLOAD, modelMissing.state)
        assertEquals(VoiceProviderCapabilityReason.WHISPER_MODEL_MISSING, modelMissing.reason)
    }

    @Test
    fun systemOfflineAndCloudAsrFailuresRemainDistinct() {
        val noSystem = VoiceProviderCapabilityPolicy.evaluate(
            probe(systemAsrAvailable = false)
        )
        val noOffline = VoiceProviderCapabilityPolicy.evaluate(
            probe(offlineAsrAvailable = false)
        )
        val noNetwork = VoiceProviderCapabilityPolicy.evaluate(
            probe(validatedNetworkAvailable = false)
        )

        assertEquals(
            VoiceProviderCapabilityReason.SYSTEM_RECOGNIZER_MISSING,
            noSystem[VoiceProviderCapabilityId.ANDROID_SYSTEM_ASR].reason
        )
        assertTrue(noSystem[VoiceProviderCapabilityId.CLOUD_ASR].ready)
        assertEquals(
            VoiceProviderCapabilityReason.OFFLINE_RECOGNIZER_MISSING,
            noOffline[VoiceProviderCapabilityId.ANDROID_OFFLINE_ASR].reason
        )
        assertEquals(
            VoiceProviderCapabilityState.NEEDS_NETWORK,
            noNetwork[VoiceProviderCapabilityId.CLOUD_ASR].state
        )
        assertEquals(
            VoiceProviderCapabilityState.NEEDS_NETWORK,
            noNetwork[VoiceProviderCapabilityId.MICROSOFT_EDGE_TTS].state
        )
    }

    @Test
    fun systemTtsReportsInitializationEngineAndLanguageStates() {
        val checking = VoiceProviderCapabilityPolicy.evaluate(
            probe(ttsInitialized = false)
        )[VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS]
        val noEngine = VoiceProviderCapabilityPolicy.evaluate(
            probe(ttsReady = false, ttsEngineCount = 0)
        )[VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS]
        val unsupportedLanguage = VoiceProviderCapabilityPolicy.evaluate(
            probe(ttsLanguageSupported = false)
        )[VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS]

        assertEquals(VoiceProviderCapabilityState.CHECKING, checking.state)
        assertEquals(VoiceProviderCapabilityReason.TTS_ENGINE_MISSING, noEngine.reason)
        assertEquals(
            VoiceProviderCapabilityReason.TTS_LANGUAGE_UNSUPPORTED,
            unsupportedLanguage.reason
        )
    }

    private fun probe(
        hasMicrophone: Boolean = true,
        microphonePermissionGranted: Boolean = true,
        whisperRuntimeAvailable: Boolean = true,
        whisperModelAvailable: Boolean = true,
        systemAsrAvailable: Boolean = true,
        offlineAsrAvailable: Boolean = true,
        validatedNetworkAvailable: Boolean = true,
        ttsInitialized: Boolean = true,
        ttsReady: Boolean = true,
        ttsEngineCount: Int = 2,
        ttsLanguageSupported: Boolean = true,
        onlineAsrAllowed: Boolean = true,
        realtimeAsrCredentialBrokerConfigured: Boolean = true
    ) = VoiceDeviceCapabilityProbe(
        hasMicrophone = hasMicrophone,
        microphonePermissionGranted = microphonePermissionGranted,
        whisperRuntimeAvailable = whisperRuntimeAvailable,
        whisperModelAvailable = whisperModelAvailable,
        whisperModelId = "tiny",
        whisperModelName = "Tiny",
        systemAsrAvailable = systemAsrAvailable,
        offlineAsrAvailable = offlineAsrAvailable,
        validatedNetworkAvailable = validatedNetworkAvailable,
        ttsInitialized = ttsInitialized,
        ttsReady = ttsReady,
        ttsEngineCount = ttsEngineCount,
        ttsLanguageSupported = ttsLanguageSupported,
        ttsLanguage = "en-US",
        onlineAsrAllowed = onlineAsrAllowed,
        realtimeAsrCredentialBrokerConfigured = realtimeAsrCredentialBrokerConfigured
    )
}
