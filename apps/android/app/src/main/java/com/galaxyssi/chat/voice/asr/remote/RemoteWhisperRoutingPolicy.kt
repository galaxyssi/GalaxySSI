package com.galaxyssi.chat.voice.asr.remote

import com.galaxyssi.chat.voice.asr.VoiceRecognitionPreference

object RemoteWhisperRoutingPolicy {
    fun shouldUseRemote(
        preference: VoiceRecognitionPreference,
        localAlwaysPreferred: Boolean,
        explicitConsent: Boolean,
        featureEnabled: Boolean,
        nodeAvailable: Boolean,
        localAccurateAvailable: Boolean,
        secondPassRequested: Boolean
    ): Boolean {
        if (!explicitConsent || !featureEnabled || !nodeAvailable) return false
        if (preference == VoiceRecognitionPreference.LOCAL_PRIVATE || localAlwaysPreferred) return false
        if (preference == VoiceRecognitionPreference.REMOTE_NODE) return true
        return secondPassRequested && !localAccurateAvailable
    }
}
