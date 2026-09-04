package com.galaxyssi.chat

import com.galaxyssi.chat.voice.benchmark.WhisperUserVoiceMode
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalWhisperAsrPolicyTest {
    @Test
    fun manualInstalledQnnRunsWithoutBenchmarkCertification() {
        assertTrue(
            shouldBypassWhisperCertificationForManualQnn(
                runtimeMode = WhisperUserVoiceMode.MANUAL,
                acceleration = VoiceAssistantSettings.ASR_ACCELERATION_QNN,
                selectedProfileId = "small",
                qnnProfileId = "small",
                qnnInstalled = true
            )
        )
    }

    @Test
    fun automaticAndIncompletePackagesKeepPolicyProtection() {
        assertFalse(
            shouldBypassWhisperCertificationForManualQnn(
                runtimeMode = WhisperUserVoiceMode.AUTOMATIC,
                acceleration = VoiceAssistantSettings.ASR_ACCELERATION_QNN,
                selectedProfileId = "small",
                qnnProfileId = "small",
                qnnInstalled = true
            )
        )
        assertFalse(
            shouldBypassWhisperCertificationForManualQnn(
                runtimeMode = WhisperUserVoiceMode.MANUAL,
                acceleration = VoiceAssistantSettings.ASR_ACCELERATION_QNN,
                selectedProfileId = "small",
                qnnProfileId = "small",
                qnnInstalled = false
            )
        )
    }

    @Test
    fun aDifferentQnnPackageCannotBypassTheSelectedProfile() {
        assertFalse(
            shouldBypassWhisperCertificationForManualQnn(
                runtimeMode = WhisperUserVoiceMode.MANUAL,
                acceleration = VoiceAssistantSettings.ASR_ACCELERATION_QNN,
                selectedProfileId = "small",
                qnnProfileId = "tiny",
                qnnInstalled = true
            )
        )
    }
}
