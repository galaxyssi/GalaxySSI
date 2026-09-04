package com.galaxyssi.chat

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.speech.SpeechRecognizer
import java.io.File

enum class VoiceProviderCapabilityId {
    WHISPER_CPP,
    ANDROID_SYSTEM_ASR,
    ANDROID_OFFLINE_ASR,
    CLOUD_ASR,
    ANDROID_SYSTEM_TTS,
    MICROSOFT_EDGE_TTS
}

enum class VoiceProviderCapabilityState {
    READY,
    CHECKING,
    NEEDS_PERMISSION,
    NEEDS_DOWNLOAD,
    NEEDS_NETWORK,
    UNAVAILABLE
}

enum class VoiceProviderCapabilityReason {
    READY,
    CHECKING,
    MICROPHONE_MISSING,
    MICROPHONE_PERMISSION_REQUIRED,
    WHISPER_RUNTIME_MISSING,
    WHISPER_MODEL_MISSING,
    SYSTEM_RECOGNIZER_MISSING,
    OFFLINE_RECOGNIZER_MISSING,
    ONLINE_AUDIO_PERMISSION_REQUIRED,
    CREDENTIAL_BROKER_REQUIRED,
    NETWORK_REQUIRED,
    TTS_ENGINE_MISSING,
    TTS_LANGUAGE_UNSUPPORTED
}

data class VoiceProviderCapability(
    val id: VoiceProviderCapabilityId,
    val state: VoiceProviderCapabilityState,
    val reason: VoiceProviderCapabilityReason,
    val metadata: Map<String, String> = emptyMap()
) {
    val ready: Boolean
        get() = state == VoiceProviderCapabilityState.READY
}

data class VoiceProviderCapabilitySnapshot(
    val capabilities: List<VoiceProviderCapability>,
    val checkedAtMillis: Long = System.currentTimeMillis()
) {
    operator fun get(id: VoiceProviderCapabilityId): VoiceProviderCapability =
        capabilities.first { it.id == id }
}

data class VoiceDeviceCapabilityProbe(
    val hasMicrophone: Boolean,
    val microphonePermissionGranted: Boolean,
    val whisperRuntimeAvailable: Boolean,
    val whisperModelAvailable: Boolean,
    val whisperModelId: String,
    val whisperModelName: String,
    val systemAsrAvailable: Boolean,
    val offlineAsrAvailable: Boolean,
    val validatedNetworkAvailable: Boolean,
    val ttsInitialized: Boolean,
    val ttsReady: Boolean,
    val ttsEngineCount: Int,
    val ttsLanguageSupported: Boolean,
    val ttsLanguage: String,
    val onlineAsrAllowed: Boolean = false,
    val realtimeAsrCredentialBrokerConfigured: Boolean = false
)

object VoiceProviderCapabilityPolicy {
    fun evaluate(probe: VoiceDeviceCapabilityProbe): VoiceProviderCapabilitySnapshot =
        VoiceProviderCapabilitySnapshot(
            listOf(
                whisper(probe),
                systemAsr(probe),
                offlineAsr(probe),
                cloudAsr(probe),
                systemTts(probe),
                cloudTts(probe)
            )
        )

    private fun whisper(probe: VoiceDeviceCapabilityProbe): VoiceProviderCapability = when {
        !probe.hasMicrophone -> unavailable(
            VoiceProviderCapabilityId.WHISPER_CPP,
            VoiceProviderCapabilityReason.MICROPHONE_MISSING
        )
        !probe.whisperRuntimeAvailable -> unavailable(
            VoiceProviderCapabilityId.WHISPER_CPP,
            VoiceProviderCapabilityReason.WHISPER_RUNTIME_MISSING
        )
        !probe.whisperModelAvailable -> capability(
            VoiceProviderCapabilityId.WHISPER_CPP,
            VoiceProviderCapabilityState.NEEDS_DOWNLOAD,
            VoiceProviderCapabilityReason.WHISPER_MODEL_MISSING,
            probe.whisperMetadata()
        )
        !probe.microphonePermissionGranted -> capability(
            VoiceProviderCapabilityId.WHISPER_CPP,
            VoiceProviderCapabilityState.NEEDS_PERMISSION,
            VoiceProviderCapabilityReason.MICROPHONE_PERMISSION_REQUIRED,
            probe.whisperMetadata()
        )
        else -> ready(VoiceProviderCapabilityId.WHISPER_CPP, probe.whisperMetadata())
    }

    private fun systemAsr(probe: VoiceDeviceCapabilityProbe): VoiceProviderCapability = when {
        !probe.hasMicrophone -> unavailable(
            VoiceProviderCapabilityId.ANDROID_SYSTEM_ASR,
            VoiceProviderCapabilityReason.MICROPHONE_MISSING
        )
        !probe.systemAsrAvailable -> unavailable(
            VoiceProviderCapabilityId.ANDROID_SYSTEM_ASR,
            VoiceProviderCapabilityReason.SYSTEM_RECOGNIZER_MISSING
        )
        !probe.microphonePermissionGranted -> capability(
            VoiceProviderCapabilityId.ANDROID_SYSTEM_ASR,
            VoiceProviderCapabilityState.NEEDS_PERMISSION,
            VoiceProviderCapabilityReason.MICROPHONE_PERMISSION_REQUIRED
        )
        else -> ready(VoiceProviderCapabilityId.ANDROID_SYSTEM_ASR)
    }

    private fun offlineAsr(probe: VoiceDeviceCapabilityProbe): VoiceProviderCapability = when {
        !probe.hasMicrophone -> unavailable(
            VoiceProviderCapabilityId.ANDROID_OFFLINE_ASR,
            VoiceProviderCapabilityReason.MICROPHONE_MISSING
        )
        !probe.offlineAsrAvailable -> unavailable(
            VoiceProviderCapabilityId.ANDROID_OFFLINE_ASR,
            VoiceProviderCapabilityReason.OFFLINE_RECOGNIZER_MISSING
        )
        !probe.microphonePermissionGranted -> capability(
            VoiceProviderCapabilityId.ANDROID_OFFLINE_ASR,
            VoiceProviderCapabilityState.NEEDS_PERMISSION,
            VoiceProviderCapabilityReason.MICROPHONE_PERMISSION_REQUIRED
        )
        else -> ready(VoiceProviderCapabilityId.ANDROID_OFFLINE_ASR)
    }

    private fun cloudAsr(probe: VoiceDeviceCapabilityProbe): VoiceProviderCapability = when {
        !probe.hasMicrophone -> unavailable(
            VoiceProviderCapabilityId.CLOUD_ASR,
            VoiceProviderCapabilityReason.MICROPHONE_MISSING
        )
        !probe.microphonePermissionGranted -> capability(
            VoiceProviderCapabilityId.CLOUD_ASR,
            VoiceProviderCapabilityState.NEEDS_PERMISSION,
            VoiceProviderCapabilityReason.MICROPHONE_PERMISSION_REQUIRED
        )
        !probe.validatedNetworkAvailable -> capability(
            VoiceProviderCapabilityId.CLOUD_ASR,
            VoiceProviderCapabilityState.NEEDS_NETWORK,
            VoiceProviderCapabilityReason.NETWORK_REQUIRED
        )
        !probe.onlineAsrAllowed -> unavailable(
            VoiceProviderCapabilityId.CLOUD_ASR,
            VoiceProviderCapabilityReason.ONLINE_AUDIO_PERMISSION_REQUIRED
        )
        !probe.realtimeAsrCredentialBrokerConfigured -> unavailable(
            VoiceProviderCapabilityId.CLOUD_ASR,
            VoiceProviderCapabilityReason.CREDENTIAL_BROKER_REQUIRED
        )
        else -> ready(VoiceProviderCapabilityId.CLOUD_ASR)
    }

    private fun systemTts(probe: VoiceDeviceCapabilityProbe): VoiceProviderCapability = when {
        !probe.ttsInitialized -> capability(
            VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS,
            VoiceProviderCapabilityState.CHECKING,
            VoiceProviderCapabilityReason.CHECKING,
            probe.ttsMetadata()
        )
        !probe.ttsReady || probe.ttsEngineCount <= 0 -> unavailable(
            VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS,
            VoiceProviderCapabilityReason.TTS_ENGINE_MISSING,
            probe.ttsMetadata()
        )
        !probe.ttsLanguageSupported -> unavailable(
            VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS,
            VoiceProviderCapabilityReason.TTS_LANGUAGE_UNSUPPORTED,
            probe.ttsMetadata()
        )
        else -> ready(VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS, probe.ttsMetadata())
    }

    private fun cloudTts(probe: VoiceDeviceCapabilityProbe): VoiceProviderCapability =
        if (probe.validatedNetworkAvailable) {
            ready(VoiceProviderCapabilityId.MICROSOFT_EDGE_TTS)
        } else {
            capability(
                VoiceProviderCapabilityId.MICROSOFT_EDGE_TTS,
                VoiceProviderCapabilityState.NEEDS_NETWORK,
                VoiceProviderCapabilityReason.NETWORK_REQUIRED
            )
        }

    private fun VoiceDeviceCapabilityProbe.whisperMetadata(): Map<String, String> = mapOf(
        "model_id" to whisperModelId,
        "model_name" to whisperModelName
    )

    private fun VoiceDeviceCapabilityProbe.ttsMetadata(): Map<String, String> = mapOf(
        "engine_count" to ttsEngineCount.toString(),
        "language" to ttsLanguage
    )

    private fun ready(
        id: VoiceProviderCapabilityId,
        metadata: Map<String, String> = emptyMap()
    ) = capability(id, VoiceProviderCapabilityState.READY, VoiceProviderCapabilityReason.READY, metadata)

    private fun unavailable(
        id: VoiceProviderCapabilityId,
        reason: VoiceProviderCapabilityReason,
        metadata: Map<String, String> = emptyMap()
    ) = capability(id, VoiceProviderCapabilityState.UNAVAILABLE, reason, metadata)

    private fun capability(
        id: VoiceProviderCapabilityId,
        state: VoiceProviderCapabilityState,
        reason: VoiceProviderCapabilityReason,
        metadata: Map<String, String> = emptyMap()
    ) = VoiceProviderCapability(id, state, reason, metadata)
}

object VoiceProviderCapabilityDetector {
    fun detect(
        context: Context,
        config: VoiceAssistantConfig,
        ttsInitialized: Boolean,
        ttsReady: Boolean,
        ttsEngineCount: Int,
        ttsLanguageSupported: Boolean
    ): VoiceProviderCapabilitySnapshot {
        val model = WhisperModelManager.model(config.asrModel)
        return VoiceProviderCapabilityPolicy.evaluate(
            VoiceDeviceCapabilityProbe(
                hasMicrophone = context.packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE),
                microphonePermissionGranted =
                    context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED,
                whisperRuntimeAvailable = whisperRuntimeAvailable(context),
                whisperModelAvailable = WhisperModelManager.isAvailable(context, model),
                whisperModelId = model.id,
                whisperModelName = model.displayName,
                systemAsrAvailable = SpeechRecognizer.isRecognitionAvailable(context),
                offlineAsrAvailable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    SpeechRecognizer.isOnDeviceRecognitionAvailable(context),
                validatedNetworkAvailable = validatedNetworkAvailable(context),
                ttsInitialized = ttsInitialized,
                ttsReady = ttsReady,
                ttsEngineCount = ttsEngineCount,
                ttsLanguageSupported = ttsLanguageSupported,
                ttsLanguage = config.ttsLanguage,
                onlineAsrAllowed = config.onlineAsrPrivacy.allowOnlineVoice &&
                    config.onlineAsrPrivacy.allowRawAudioUpload,
                realtimeAsrCredentialBrokerConfigured =
                    BuildConfig.REALTIME_ASR_CREDENTIAL_BROKER_URL.isNotBlank()
            )
        )
    }

    private fun whisperRuntimeAvailable(context: Context): Boolean =
        Build.SUPPORTED_ABIS.any { it.equals("arm64-v8a", ignoreCase = true) } &&
            File(context.applicationInfo.nativeLibraryDir, System.mapLibraryName("whisper")).isFile

    private fun validatedNetworkAvailable(context: Context): Boolean {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }
}
