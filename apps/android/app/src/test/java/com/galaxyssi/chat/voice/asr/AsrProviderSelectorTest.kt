package com.galaxyssi.chat.voice.asr

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AsrProviderSelectorTest {
    private val online = AsrProviderCandidate("realtime", online = true, available = true, latencyRank = 1)
    private val local = AsrProviderCandidate("whisper", online = false, available = true, latencyRank = 2)

    @Test
    fun autoUsesOnlineOnlyWhenNetworkAndExplicitAudioConsentAllowIt() {
        val selected = AsrProviderSelector.select(config(), listOf(online), listOf(local))

        assertEquals(online, (selected as AsrProviderSelection.Selected).candidate)
        assertTrue(AsrProviderSelector.onlineAllowed(config()))
    }

    @Test
    fun privacyOrMobilePolicyFallsBackToLocal() {
        val private = AsrProviderSelector.select(
            config(preference = VoiceRecognitionPreference.LOCAL_PRIVATE),
            listOf(online),
            listOf(local)
        )
        val mobile = AsrProviderSelector.select(
            config(networkType = AsrNetworkType.MOBILE),
            listOf(online),
            listOf(local)
        )
        val noUpload = AsrProviderSelector.select(
            config(privacy = config().privacy.copy(allowRawAudioUpload = false)),
            listOf(online),
            listOf(local)
        )

        assertEquals(local, (private as AsrProviderSelection.Selected).candidate)
        assertEquals(local, (mobile as AsrProviderSelection.Selected).candidate)
        assertEquals(local, (noUpload as AsrProviderSelection.Selected).candidate)
        assertFalse(AsrProviderSelector.onlineAllowed(config(networkType = AsrNetworkType.MOBILE)))
    }

    @Test
    fun onlineFastFallsBackLocallyInsteadOfRequestingUserToRepeat() {
        val selected = AsrProviderSelector.select(
            config(preference = VoiceRecognitionPreference.ONLINE_FAST),
            listOf(online.copy(available = false)),
            listOf(local)
        )

        assertEquals("online_fallback_local", (selected as AsrProviderSelection.Selected).reasonCode)
    }

    @Test
    fun remotePreferenceRequiresAnAvailableExplicitRemoteCandidate() {
        val remote = AsrProviderCandidate(
            "desktop-whisper",
            online = true,
            available = true,
            accuracyRank = 1
        )
        val selected = AsrProviderSelector.select(
            config(preference = VoiceRecognitionPreference.REMOTE_NODE),
            listOf(online),
            listOf(local),
            listOf(remote)
        )
        val unavailable = AsrProviderSelector.select(
            config(preference = VoiceRecognitionPreference.REMOTE_NODE),
            listOf(online),
            listOf(local)
        )

        assertEquals(remote, (selected as AsrProviderSelection.Selected).candidate)
        assertEquals("remote_node_not_available", (unavailable as AsrProviderSelection.Unavailable).reasonCode)
    }

    private fun config(
        preference: VoiceRecognitionPreference = VoiceRecognitionPreference.AUTO,
        networkType: AsrNetworkType = AsrNetworkType.WIFI,
        privacy: AsrPrivacyPolicy = AsrPrivacyPolicy(
            allowOnlineVoice = true,
            wifiOnly = true,
            allowMobileNetwork = false,
            allowRawAudioUpload = true
        )
    ) = AsrSessionConfig(
        voiceSessionId = "voice-1",
        transcriptId = "transcript-1",
        preference = preference,
        networkType = networkType,
        privacy = privacy
    )
}
