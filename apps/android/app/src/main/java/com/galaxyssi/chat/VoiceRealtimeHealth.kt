package com.galaxyssi.chat

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager

enum class VoiceHealthComponent {
    WAKE_WORD,
    ASR,
    TTS
}

enum class VoiceHealthState {
    ACTIVE,
    HEALTHY,
    READY,
    CHECKING,
    DEGRADED,
    BLOCKED,
    DISABLED
}

enum class VoiceHealthIssue {
    NONE,
    DISABLED,
    CHECKING,
    MICROPHONE_MISSING,
    PERMISSION_REQUIRED,
    RUNTIME_MISSING,
    MODEL_MISSING,
    PROVIDER_UNAVAILABLE,
    NETWORK_REQUIRED,
    LANGUAGE_UNSUPPORTED,
    RECENT_FAILURE
}

enum class VoiceRuntimeChannel {
    OPEN_WAKE_WORD,
    ANDROID_WAKE_ASR,
    LOCAL_WHISPER_ASR,
    ONLINE_REALTIME_ASR,
    ANDROID_SYSTEM_ASR,
    ANDROID_SYSTEM_TTS,
    MICROSOFT_EDGE_TTS
}

data class VoiceRuntimeHealthRecord(
    val active: Boolean = false,
    val startedAtMillis: Long = 0L,
    val lastSuccessAtMillis: Long = 0L,
    val lastFailureAtMillis: Long = 0L,
    val lastFailureReason: String = ""
) {
    val lastEventAtMillis: Long
        get() = maxOf(startedAtMillis, lastSuccessAtMillis, lastFailureAtMillis)
}

object VoiceRuntimeHealthRegistry {
    private val lock = Any()
    private val records = mutableMapOf<VoiceRuntimeChannel, VoiceRuntimeHealthRecord>()

    fun begin(channel: VoiceRuntimeChannel, nowMillis: Long = System.currentTimeMillis()) {
        synchronized(lock) {
            val current = records[channel] ?: VoiceRuntimeHealthRecord()
            records[channel] = current.copy(active = true, startedAtMillis = nowMillis)
        }
    }

    fun success(channel: VoiceRuntimeChannel, nowMillis: Long = System.currentTimeMillis()) {
        synchronized(lock) {
            val current = records[channel] ?: VoiceRuntimeHealthRecord()
            records[channel] = current.copy(
                active = false,
                lastSuccessAtMillis = nowMillis
            )
        }
    }

    fun failure(
        channel: VoiceRuntimeChannel,
        reason: String,
        nowMillis: Long = System.currentTimeMillis()
    ) {
        synchronized(lock) {
            val current = records[channel] ?: VoiceRuntimeHealthRecord()
            records[channel] = current.copy(
                active = false,
                lastFailureAtMillis = nowMillis,
                lastFailureReason = reason.trim().replace(Regex("\\s+"), " ").take(160)
            )
        }
    }

    fun idle(channel: VoiceRuntimeChannel) {
        synchronized(lock) {
            val current = records[channel] ?: return
            records[channel] = current.copy(active = false)
        }
    }

    fun record(channel: VoiceRuntimeChannel): VoiceRuntimeHealthRecord =
        synchronized(lock) { records[channel] ?: VoiceRuntimeHealthRecord() }

    internal fun resetForTests() {
        synchronized(lock) { records.clear() }
    }
}

data class VoiceHealthDependency(
    val ready: Boolean,
    val checking: Boolean = false,
    val issue: VoiceHealthIssue = VoiceHealthIssue.NONE
)

data class VoiceHealthProbe(
    val component: VoiceHealthComponent,
    val enabled: Boolean,
    val provider: String,
    val dependency: VoiceHealthDependency,
    val runtime: VoiceRuntimeHealthRecord
)

data class VoiceHealthEntry(
    val component: VoiceHealthComponent,
    val provider: String,
    val state: VoiceHealthState,
    val issue: VoiceHealthIssue,
    val runtime: VoiceRuntimeHealthRecord
)

data class VoiceRealtimeHealthSnapshot(
    val entries: List<VoiceHealthEntry>,
    val checkedAtMillis: Long
) {
    operator fun get(component: VoiceHealthComponent): VoiceHealthEntry =
        entries.first { it.component == component }
}

object VoiceRealtimeHealthPolicy {
    internal const val RECENT_FAILURE_WINDOW_MS = 5 * 60 * 1000L
    internal const val SUCCESS_FRESHNESS_MS = 10 * 60 * 1000L

    fun evaluate(
        probes: List<VoiceHealthProbe>,
        nowMillis: Long = System.currentTimeMillis()
    ): VoiceRealtimeHealthSnapshot = VoiceRealtimeHealthSnapshot(
        entries = probes.map { probe -> evaluate(probe, nowMillis) },
        checkedAtMillis = nowMillis
    )

    private fun evaluate(probe: VoiceHealthProbe, nowMillis: Long): VoiceHealthEntry {
        val runtime = probe.runtime
        val recentFailure = runtime.lastFailureAtMillis > runtime.lastSuccessAtMillis &&
            nowMillis - runtime.lastFailureAtMillis in 0..RECENT_FAILURE_WINDOW_MS
        val recentSuccess = runtime.lastSuccessAtMillis > 0L &&
            nowMillis - runtime.lastSuccessAtMillis in 0..SUCCESS_FRESHNESS_MS
        val state = when {
            !probe.enabled -> VoiceHealthState.DISABLED
            probe.dependency.checking -> VoiceHealthState.CHECKING
            !probe.dependency.ready -> VoiceHealthState.BLOCKED
            runtime.active -> VoiceHealthState.ACTIVE
            recentFailure -> VoiceHealthState.DEGRADED
            recentSuccess -> VoiceHealthState.HEALTHY
            else -> VoiceHealthState.READY
        }
        val issue = when (state) {
            VoiceHealthState.DISABLED -> VoiceHealthIssue.DISABLED
            VoiceHealthState.CHECKING -> VoiceHealthIssue.CHECKING
            VoiceHealthState.DEGRADED -> VoiceHealthIssue.RECENT_FAILURE
            VoiceHealthState.BLOCKED -> probe.dependency.issue
            else -> VoiceHealthIssue.NONE
        }
        return VoiceHealthEntry(
            component = probe.component,
            provider = probe.provider,
            state = state,
            issue = issue,
            runtime = runtime
        )
    }
}

object VoiceRealtimeHealthDetector {
    fun detect(
        context: Context,
        config: VoiceAssistantConfig,
        capabilities: VoiceProviderCapabilitySnapshot
    ): VoiceRealtimeHealthSnapshot {
        val wakeChannel = if (
            config.wakeProvider == VoiceAssistantSettings.WAKE_PROVIDER_ANDROID_ASR
        ) {
            VoiceRuntimeChannel.ANDROID_WAKE_ASR
        } else {
            VoiceRuntimeChannel.OPEN_WAKE_WORD
        }
        val wakeDependency = if (wakeChannel == VoiceRuntimeChannel.OPEN_WAKE_WORD) {
            openWakeWordDependency(context, config)
        } else {
            dependency(capabilities[VoiceProviderCapabilityId.ANDROID_SYSTEM_ASR])
        }
        val ttsChannel = if (
            config.ttsProvider == VoiceAssistantSettings.PROVIDER_ANDROID
        ) {
            VoiceRuntimeChannel.ANDROID_SYSTEM_TTS
        } else {
            VoiceRuntimeChannel.MICROSOFT_EDGE_TTS
        }
        val ttsCapability = capabilities[
            if (ttsChannel == VoiceRuntimeChannel.ANDROID_SYSTEM_TTS) {
                VoiceProviderCapabilityId.ANDROID_SYSTEM_TTS
            } else {
                VoiceProviderCapabilityId.MICROSOFT_EDGE_TTS
            }
        ]
        val onlineAsr = config.asrProvider == VoiceAssistantSettings.ASR_PROVIDER_ONLINE_REALTIME
        val asrChannel = if (onlineAsr) {
            VoiceRuntimeChannel.ONLINE_REALTIME_ASR
        } else {
            VoiceRuntimeChannel.LOCAL_WHISPER_ASR
        }
        val asrCapability = capabilities[
            if (onlineAsr) VoiceProviderCapabilityId.CLOUD_ASR else VoiceProviderCapabilityId.WHISPER_CPP
        ]
        return VoiceRealtimeHealthPolicy.evaluate(
            listOf(
                VoiceHealthProbe(
                    component = VoiceHealthComponent.WAKE_WORD,
                    enabled = config.enabled,
                    provider = if (wakeChannel == VoiceRuntimeChannel.OPEN_WAKE_WORD) {
                        "openWakeWord"
                    } else {
                        "Android SpeechRecognizer"
                    },
                    dependency = wakeDependency,
                    runtime = VoiceRuntimeHealthRegistry.record(wakeChannel)
                ),
                VoiceHealthProbe(
                    component = VoiceHealthComponent.ASR,
                    enabled = true,
                    provider = if (onlineAsr) {
                        "GalaxySSI Realtime ASR"
                    } else {
                        "whisper.cpp / ${WhisperModelManager.model(config.asrModel).displayName}"
                    },
                    dependency = dependency(asrCapability),
                    runtime = VoiceRuntimeHealthRegistry.record(asrChannel)
                ),
                VoiceHealthProbe(
                    component = VoiceHealthComponent.TTS,
                    enabled = true,
                    provider = if (ttsChannel == VoiceRuntimeChannel.ANDROID_SYSTEM_TTS) {
                        "Android TTS"
                    } else {
                        "Microsoft Edge TTS"
                    },
                    dependency = dependency(ttsCapability),
                    runtime = VoiceRuntimeHealthRegistry.record(ttsChannel)
                )
            )
        )
    }

    private fun openWakeWordDependency(
        context: Context,
        config: VoiceAssistantConfig
    ): VoiceHealthDependency {
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_MICROPHONE)) {
            return VoiceHealthDependency(false, issue = VoiceHealthIssue.MICROPHONE_MISSING)
        }
        if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return VoiceHealthDependency(false, issue = VoiceHealthIssue.PERMISSION_REQUIRED)
        }
        val runtimeAvailable = runCatching {
            Class.forName("com.rementia.openwakeword.lib.WakeWordEngine")
        }.isSuccess
        if (!runtimeAvailable) {
            return VoiceHealthDependency(false, issue = VoiceHealthIssue.RUNTIME_MISSING)
        }
        val modelAvailable = runCatching {
            context.assets.open(config.wakeModel).use { input -> input.read() }
        }.isSuccess
        return if (modelAvailable) {
            VoiceHealthDependency(true)
        } else {
            VoiceHealthDependency(false, issue = VoiceHealthIssue.MODEL_MISSING)
        }
    }

    private fun dependency(
        capability: VoiceProviderCapability
    ): VoiceHealthDependency = when (capability.state) {
        VoiceProviderCapabilityState.READY -> VoiceHealthDependency(true)
        VoiceProviderCapabilityState.CHECKING ->
            VoiceHealthDependency(false, checking = true, issue = VoiceHealthIssue.CHECKING)
        else -> VoiceHealthDependency(
            ready = false,
            issue = when (capability.reason) {
                VoiceProviderCapabilityReason.MICROPHONE_MISSING ->
                    VoiceHealthIssue.MICROPHONE_MISSING
                VoiceProviderCapabilityReason.MICROPHONE_PERMISSION_REQUIRED ->
                    VoiceHealthIssue.PERMISSION_REQUIRED
                VoiceProviderCapabilityReason.WHISPER_RUNTIME_MISSING ->
                    VoiceHealthIssue.RUNTIME_MISSING
                VoiceProviderCapabilityReason.WHISPER_MODEL_MISSING ->
                    VoiceHealthIssue.MODEL_MISSING
                VoiceProviderCapabilityReason.NETWORK_REQUIRED ->
                    VoiceHealthIssue.NETWORK_REQUIRED
                VoiceProviderCapabilityReason.TTS_LANGUAGE_UNSUPPORTED ->
                    VoiceHealthIssue.LANGUAGE_UNSUPPORTED
                VoiceProviderCapabilityReason.CHECKING ->
                    VoiceHealthIssue.CHECKING
                else -> VoiceHealthIssue.PROVIDER_UNAVAILABLE
            }
        )
    }
}
