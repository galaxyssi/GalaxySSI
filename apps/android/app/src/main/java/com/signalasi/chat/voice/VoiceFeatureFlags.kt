package com.signalasi.chat.voice

import android.content.Context
import android.content.pm.ApplicationInfo

const val VOICE_COORDINATOR_FLAG = "voice.coordinator_v1"

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
}
