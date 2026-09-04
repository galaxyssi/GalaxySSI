package com.galaxyssi.chat.voice

import android.content.Context
import android.content.pm.ApplicationInfo

const val VOICE_COORDINATOR_FLAG = "voice.coordinator_v1"
const val VOICE_PCM_CAPTURE_FLAG = "voice.audio_record_pcm_v1"
const val VOICE_LOCAL_WHISPER_RUNTIME_V2_FLAG = "voice.local_whisper_runtime_v2"
const val VOICE_WHISPER_ADAPTIVE_PARTIAL_V1_FLAG = "voice.whisper_adaptive_partial_v1"
const val VOICE_WHISPER_AUTO_BENCHMARK_V1_FLAG = "voice.whisper_auto_benchmark_v1"
const val VOICE_WHISPER_POLICY_ENGINE_V1_FLAG = "voice.whisper_policy_engine_v1"
const val VOICE_WHISPER_SECOND_PASS_V1_FLAG = "voice.whisper_second_pass_v1"
const val VOICE_CLOUD_MODEL_STREAM_V1_FLAG = "voice.cloud_model_stream_v1"
const val VOICE_SENTENCE_COMMITTER_V1_FLAG = "voice.sentence_committer_v1"
const val VOICE_PROGRESSIVE_TTS_V1_FLAG = "voice.progressive_tts_v1"
const val VOICE_BARGE_IN_V1_FLAG = "voice.barge_in_v1"
const val VOICE_AGENT_RUN_BRIDGE_V1_FLAG = "agent.voice_run_bridge_v1"
const val VOICE_ONLINE_REALTIME_ASR_V1_FLAG = "voice.online_realtime_asr_v1"
const val VOICE_RELIABILITY_GOVERNOR_V1_FLAG = "voice.reliability_governor_v1"
const val VOICE_REMOTE_WHISPER_NODE_V1_FLAG = "voice.remote_whisper_node_v1"

object VoiceFeatureFlags {
    private const val PREFERENCES = "galaxyssi_voice_feature_flags"

    fun isCoordinatorEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(
                VOICE_COORDINATOR_FLAG,
                (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            )

    fun setCoordinatorEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(VOICE_COORDINATOR_FLAG, enabled)
            .apply()
    }

    fun isPcmCaptureEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(
                VOICE_PCM_CAPTURE_FLAG,
                (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            )

    fun setPcmCaptureEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(VOICE_PCM_CAPTURE_FLAG, enabled)
            .apply()
    }

    fun isLocalWhisperRuntimeV2Enabled(context: Context): Boolean =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(
                VOICE_LOCAL_WHISPER_RUNTIME_V2_FLAG,
                (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            )

    fun setLocalWhisperRuntimeV2Enabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(VOICE_LOCAL_WHISPER_RUNTIME_V2_FLAG, enabled)
            .apply()
    }

    fun isWhisperAdaptivePartialEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(
                VOICE_WHISPER_ADAPTIVE_PARTIAL_V1_FLAG,
                (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            )

    fun setWhisperAdaptivePartialEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(VOICE_WHISPER_ADAPTIVE_PARTIAL_V1_FLAG, enabled)
            .apply()
    }

    fun isWhisperAutoBenchmarkEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(
                VOICE_WHISPER_AUTO_BENCHMARK_V1_FLAG,
                (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            )

    fun setWhisperAutoBenchmarkEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(VOICE_WHISPER_AUTO_BENCHMARK_V1_FLAG, enabled)
            .apply()
    }

    fun isWhisperPolicyEngineEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(
                VOICE_WHISPER_POLICY_ENGINE_V1_FLAG,
                (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            )

    fun setWhisperPolicyEngineEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(VOICE_WHISPER_POLICY_ENGINE_V1_FLAG, enabled)
            .apply()
    }

    fun isWhisperSecondPassEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(
                VOICE_WHISPER_SECOND_PASS_V1_FLAG,
                (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            )

    fun setWhisperSecondPassEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(VOICE_WHISPER_SECOND_PASS_V1_FLAG, enabled)
            .apply()
    }

    fun isCloudModelStreamingEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(
                VOICE_CLOUD_MODEL_STREAM_V1_FLAG,
                (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            )

    fun setCloudModelStreamingEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(VOICE_CLOUD_MODEL_STREAM_V1_FLAG, enabled)
            .apply()
    }

    fun isSentenceCommitterEnabled(context: Context): Boolean =
        isDebugOptInEnabled(context, VOICE_SENTENCE_COMMITTER_V1_FLAG)

    fun setSentenceCommitterEnabled(context: Context, enabled: Boolean) {
        setFlag(context, VOICE_SENTENCE_COMMITTER_V1_FLAG, enabled)
    }

    fun isProgressiveTtsEnabled(context: Context): Boolean =
        isDebugOptInEnabled(context, VOICE_PROGRESSIVE_TTS_V1_FLAG)

    fun setProgressiveTtsEnabled(context: Context, enabled: Boolean) {
        setFlag(context, VOICE_PROGRESSIVE_TTS_V1_FLAG, enabled)
    }

    fun isBargeInEnabled(context: Context): Boolean =
        isDebugOptInEnabled(context, VOICE_BARGE_IN_V1_FLAG)

    fun setBargeInEnabled(context: Context, enabled: Boolean) {
        setFlag(context, VOICE_BARGE_IN_V1_FLAG, enabled)
    }

    fun isAgentVoiceRunBridgeEnabled(context: Context): Boolean =
        isDebugOptInEnabled(context, VOICE_AGENT_RUN_BRIDGE_V1_FLAG)

    fun setAgentVoiceRunBridgeEnabled(context: Context, enabled: Boolean) {
        setFlag(context, VOICE_AGENT_RUN_BRIDGE_V1_FLAG, enabled)
    }

    fun isOnlineRealtimeAsrEnabled(context: Context): Boolean =
        isDebugOptInEnabled(context, VOICE_ONLINE_REALTIME_ASR_V1_FLAG)

    fun setOnlineRealtimeAsrEnabled(context: Context, enabled: Boolean) {
        setFlag(context, VOICE_ONLINE_REALTIME_ASR_V1_FLAG, enabled)
    }

    fun isReliabilityGovernorEnabled(context: Context): Boolean =
        isDebugOptInEnabled(context, VOICE_RELIABILITY_GOVERNOR_V1_FLAG)

    fun setReliabilityGovernorEnabled(context: Context, enabled: Boolean) {
        setFlag(context, VOICE_RELIABILITY_GOVERNOR_V1_FLAG, enabled)
    }

    fun isRemoteWhisperNodeEnabled(context: Context): Boolean =
        isDebugOptInEnabled(context, VOICE_REMOTE_WHISPER_NODE_V1_FLAG)

    fun setRemoteWhisperNodeEnabled(context: Context, enabled: Boolean) {
        setFlag(context, VOICE_REMOTE_WHISPER_NODE_V1_FLAG, enabled)
    }

    private fun isDebugOptInEnabled(context: Context, key: String): Boolean =
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(
                key,
                (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            )

    private fun setFlag(context: Context, key: String, enabled: Boolean) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(key, enabled)
            .apply()
    }
}
