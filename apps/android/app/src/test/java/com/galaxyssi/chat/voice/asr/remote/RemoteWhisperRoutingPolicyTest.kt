package com.galaxyssi.chat.voice.asr.remote

import com.galaxyssi.chat.voice.asr.VoiceRecognitionPreference
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RemoteWhisperRoutingPolicyTest {
    @Test
    fun `local private mode never uploads audio`() {
        assertFalse(decide(preference = VoiceRecognitionPreference.LOCAL_PRIVATE))
    }

    @Test
    fun `local always preferred never uploads audio`() {
        assertFalse(decide(localAlwaysPreferred = true))
    }

    @Test
    fun `explicit remote mode requires consent feature and verified node`() {
        assertTrue(decide(preference = VoiceRecognitionPreference.REMOTE_NODE, secondPassRequested = false))
        assertFalse(decide(preference = VoiceRecognitionPreference.REMOTE_NODE, explicitConsent = false))
        assertFalse(decide(preference = VoiceRecognitionPreference.REMOTE_NODE, featureEnabled = false))
        assertFalse(decide(preference = VoiceRecognitionPreference.REMOTE_NODE, nodeAvailable = false))
    }

    @Test
    fun `automatic correction uses remote only when local accurate model is unavailable`() {
        assertTrue(decide())
        assertFalse(decide(localAccurateAvailable = true))
        assertFalse(decide(secondPassRequested = false))
    }

    private fun decide(
        preference: VoiceRecognitionPreference = VoiceRecognitionPreference.AUTO,
        localAlwaysPreferred: Boolean = false,
        explicitConsent: Boolean = true,
        featureEnabled: Boolean = true,
        nodeAvailable: Boolean = true,
        localAccurateAvailable: Boolean = false,
        secondPassRequested: Boolean = true
    ): Boolean = RemoteWhisperRoutingPolicy.shouldUseRemote(
        preference = preference,
        localAlwaysPreferred = localAlwaysPreferred,
        explicitConsent = explicitConsent,
        featureEnabled = featureEnabled,
        nodeAvailable = nodeAvailable,
        localAccurateAvailable = localAccurateAvailable,
        secondPassRequested = secondPassRequested
    )
}
