package com.signalasi.chat.voice

import android.content.Context
import android.content.pm.ApplicationInfo

const val VOICE_COORDINATOR_FLAG = "voice.coordinator_v1"
const val VOICE_PCM_CAPTURE_FLAG = "voice.audio_record_pcm_v1"
const val VOICE_LOCAL_WHISPER_RUNTIME_V2_FLAG = "voice.local_whisper_runtime_v2"
const val VOICE_WHISPER_ADAPTIVE_PARTIAL_V1_FLAG = "voice.whisper_adaptive_partial_v1"
const val VOICE_WHISPER_AUTO_BENCHMARK_V1_FLAG = "voice.whisper_auto_benchmark_v1"
const val VOICE_WHISPER_POLICY_ENGINE_V1_FLAG = "voice.whisper_policy_engine_v1"
const val VOICE_WHISPER_SECOND_PASS_V1_FLAG = "voice.whisper_second_pass_v1"

object VoiceFeatureFlags {
    private const val PREFERENCES = "signalasi_voice_feature_flags"

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
}
