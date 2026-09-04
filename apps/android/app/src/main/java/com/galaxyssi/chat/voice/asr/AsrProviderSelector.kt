package com.galaxyssi.chat.voice.asr

data class AsrProviderCandidate(
    val providerId: String,
    val online: Boolean,
    val available: Boolean,
    val reasonCode: String = "",
    val latencyRank: Int = Int.MAX_VALUE,
    val accuracyRank: Int = Int.MAX_VALUE
)

sealed interface AsrProviderSelection {
    data class Selected(val candidate: AsrProviderCandidate, val reasonCode: String) : AsrProviderSelection
    data class Unavailable(val reasonCode: String) : AsrProviderSelection
}

object AsrProviderSelector {
    fun select(
        config: AsrSessionConfig,
        onlineCandidates: List<AsrProviderCandidate>,
        localCandidates: List<AsrProviderCandidate>,
        remoteCandidates: List<AsrProviderCandidate> = emptyList()
    ): AsrProviderSelection {
        val onlineAllowed = onlineAllowed(config)
        val online = onlineCandidates
            .asSequence()
            .filter { it.online && it.available }
            .minWithOrNull(compareBy<AsrProviderCandidate> { it.latencyRank }.thenBy { it.providerId })
        val localFast = localCandidates
            .asSequence()
            .filter { !it.online && it.available }
            .minWithOrNull(compareBy<AsrProviderCandidate> { it.latencyRank }.thenBy { it.providerId })
        val localAccurate = localCandidates
            .asSequence()
            .filter { !it.online && it.available }
            .minWithOrNull(compareBy<AsrProviderCandidate> { it.accuracyRank }.thenBy { it.providerId })
        val remoteAccurate = remoteCandidates
            .asSequence()
            .filter { it.available }
            .minWithOrNull(compareBy<AsrProviderCandidate> { it.accuracyRank }.thenBy { it.providerId })

        return when (config.preference) {
            VoiceRecognitionPreference.LOCAL_PRIVATE -> localFast.selectedOrUnavailable("local_private")
            VoiceRecognitionPreference.LOCAL_HIGH_ACCURACY -> localAccurate.selectedOrUnavailable("local_high_accuracy")
            VoiceRecognitionPreference.REMOTE_NODE ->
                remoteAccurate.selectedOrUnavailable("remote_high_accuracy", "remote_node_not_available")
            VoiceRecognitionPreference.ONLINE_FAST -> when {
                onlineAllowed && online != null -> AsrProviderSelection.Selected(online, "online_fast")
                localFast != null -> AsrProviderSelection.Selected(localFast, "online_fallback_local")
                else -> AsrProviderSelection.Unavailable(onlineBlockReason(config))
            }
            VoiceRecognitionPreference.AUTO -> when {
                config.privacy.localAlwaysPreferred && localFast != null ->
                    AsrProviderSelection.Selected(localFast, "local_preferred")
                onlineAllowed && online != null -> AsrProviderSelection.Selected(online, "auto_online")
                localFast != null -> AsrProviderSelection.Selected(localFast, "auto_local")
                else -> AsrProviderSelection.Unavailable(onlineBlockReason(config))
            }
        }
    }

    fun onlineAllowed(config: AsrSessionConfig): Boolean {
        val privacy = config.privacy
        if (config.preference == VoiceRecognitionPreference.LOCAL_PRIVATE || privacy.localAlwaysPreferred) return false
        if (!privacy.allowOnlineVoice || !privacy.allowRawAudioUpload) return false
        return when (config.networkType) {
            AsrNetworkType.OFFLINE -> false
            AsrNetworkType.WIFI -> true
            AsrNetworkType.MOBILE -> !privacy.wifiOnly && privacy.allowMobileNetwork
            AsrNetworkType.OTHER_VALIDATED -> !privacy.wifiOnly
        }
    }

    private fun onlineBlockReason(config: AsrSessionConfig): String = when {
        !config.privacy.allowOnlineVoice -> "online_voice_disabled"
        !config.privacy.allowRawAudioUpload -> "raw_audio_upload_disabled"
        config.networkType == AsrNetworkType.OFFLINE -> "network_unavailable"
        config.networkType == AsrNetworkType.MOBILE && config.privacy.wifiOnly -> "wifi_required"
        config.networkType == AsrNetworkType.MOBILE && !config.privacy.allowMobileNetwork -> "mobile_network_disabled"
        else -> "asr_provider_unavailable"
    }

    private fun AsrProviderCandidate?.selectedOrUnavailable(reasonCode: String): AsrProviderSelection =
        this?.let { AsrProviderSelection.Selected(it, reasonCode) }
            ?: AsrProviderSelection.Unavailable("local_asr_unavailable")

    private fun AsrProviderCandidate?.selectedOrUnavailable(
        reasonCode: String,
        unavailableReason: String
    ): AsrProviderSelection = this?.let { AsrProviderSelection.Selected(it, reasonCode) }
        ?: AsrProviderSelection.Unavailable(unavailableReason)
}
