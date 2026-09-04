package com.galaxyssi.chat

import android.content.Context
import android.media.MediaRecorder
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build

enum class AgentMediaNetworkState {
    NORMAL,
    CONSTRAINED,
    OFFLINE
}

data class AgentMediaNetworkProbe(
    val networkPresent: Boolean,
    val internetCapable: Boolean,
    val validated: Boolean,
    val metered: Boolean,
    val roaming: Boolean,
    val restricted: Boolean,
    val congested: Boolean,
    val cellular: Boolean,
    val downstreamKbps: Int,
    val upstreamKbps: Int
)

data class AgentMediaDeliveryProfile(
    val state: AgentMediaNetworkState,
    val id: String,
    val imageTargetBytes: Int,
    val audioSampleRateHz: Int,
    val audioBitRateBps: Int,
    val deferMediaUpload: Boolean
) {
    val canUploadDeferredMedia: Boolean
        get() = state != AgentMediaNetworkState.OFFLINE
}

object AgentMediaNetworkPolicy {
    const val NORMAL_IMAGE_BYTES = 100_000
    const val CONSTRAINED_IMAGE_BYTES = 64 * 1024
    const val OFFLINE_IMAGE_BYTES = 48 * 1024

    fun evaluate(probe: AgentMediaNetworkProbe): AgentMediaDeliveryProfile {
        val state = when {
            !probe.networkPresent || !probe.internetCapable || !probe.validated ->
                AgentMediaNetworkState.OFFLINE
            probe.metered ||
                probe.roaming ||
                probe.restricted ||
                probe.congested ||
                probe.cellular ||
                probe.downstreamKbps in 1 until MIN_NORMAL_DOWNSTREAM_KBPS ||
                probe.upstreamKbps in 1 until MIN_NORMAL_UPSTREAM_KBPS ->
                AgentMediaNetworkState.CONSTRAINED
            else -> AgentMediaNetworkState.NORMAL
        }
        return when (state) {
            AgentMediaNetworkState.NORMAL -> AgentMediaDeliveryProfile(
                state = state,
                id = "normal",
                imageTargetBytes = NORMAL_IMAGE_BYTES,
                audioSampleRateHz = 44_100,
                audioBitRateBps = 96_000,
                deferMediaUpload = false
            )
            AgentMediaNetworkState.CONSTRAINED -> AgentMediaDeliveryProfile(
                state = state,
                id = "constrained",
                imageTargetBytes = CONSTRAINED_IMAGE_BYTES,
                audioSampleRateHz = 16_000,
                audioBitRateBps = 32_000,
                deferMediaUpload = false
            )
            AgentMediaNetworkState.OFFLINE -> AgentMediaDeliveryProfile(
                state = state,
                id = "offline",
                imageTargetBytes = OFFLINE_IMAGE_BYTES,
                audioSampleRateHz = 16_000,
                audioBitRateBps = 24_000,
                deferMediaUpload = true
            )
        }
    }

    private const val MIN_NORMAL_DOWNSTREAM_KBPS = 1_000
    private const val MIN_NORMAL_UPSTREAM_KBPS = 512
}

object AgentMediaNetworkDetector {
    fun detect(context: Context): AgentMediaDeliveryProfile {
        val manager = context.getSystemService(ConnectivityManager::class.java)
        val network = manager?.activeNetwork
        val capabilities = network?.let(manager::getNetworkCapabilities)
        val congested = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            capabilities?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_CONGESTED) == false
        } else {
            false
        }
        val backgroundRestricted = manager?.restrictBackgroundStatus ==
            ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED
        val networkProfile = AgentMediaNetworkPolicy.evaluate(
            AgentMediaNetworkProbe(
                networkPresent = network != null && capabilities != null,
                internetCapable = capabilities?.hasCapability(
                    NetworkCapabilities.NET_CAPABILITY_INTERNET
                ) == true,
                validated = capabilities?.hasCapability(
                    NetworkCapabilities.NET_CAPABILITY_VALIDATED
                ) == true,
                metered = manager?.isActiveNetworkMetered != false,
                roaming = capabilities?.hasCapability(
                    NetworkCapabilities.NET_CAPABILITY_NOT_ROAMING
                ) == false,
                restricted = backgroundRestricted || capabilities?.hasCapability(
                    NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED
                ) == false,
                congested = congested,
                cellular = capabilities?.hasTransport(
                    NetworkCapabilities.TRANSPORT_CELLULAR
                ) == true,
                downstreamKbps = capabilities?.linkDownstreamBandwidthKbps ?: 0,
                upstreamKbps = capabilities?.linkUpstreamBandwidthKbps ?: 0
            )
        )
        return AgentDeviceProfileDetector.detect(context).adaptMedia(networkProfile)
    }
}

internal fun MediaRecorder.applyAgentAudioProfile(profile: AgentMediaDeliveryProfile) {
    setAudioChannels(1)
    setAudioSamplingRate(profile.audioSampleRateHz)
    setAudioEncodingBitRate(profile.audioBitRateBps)
}
