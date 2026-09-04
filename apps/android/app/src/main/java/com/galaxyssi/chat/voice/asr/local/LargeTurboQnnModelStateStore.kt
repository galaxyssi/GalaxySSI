package com.galaxyssi.chat.voice.asr.local

import android.content.Context
import org.json.JSONObject

internal data class PersistedLargeTurboQnnModelState(
    val state: LargeTurboQnnModelState,
    val updatedAtMillis: Long
)

internal object LargeTurboQnnModelStateCodec {
    fun encode(value: PersistedLargeTurboQnnModelState): String = JSONObject()
        .put("status", value.state.status.name)
        .put("progress", value.state.progress)
        .put("detail", value.state.detail)
        .put("resumed", value.state.resumed)
        .put("updated_at_ms", value.updatedAtMillis)
        .toString()

    fun decode(value: String): PersistedLargeTurboQnnModelState? = runCatching {
        val json = JSONObject(value)
        PersistedLargeTurboQnnModelState(
            state = LargeTurboQnnModelState(
                status = LargeTurboQnnModelStatus.valueOf(json.getString("status")),
                progress = json.optInt("progress").coerceIn(0, 100),
                detail = json.optString("detail").take(MAX_DETAIL_CHARS),
                resumed = json.optBoolean("resumed")
            ),
            updatedAtMillis = json.getLong("updated_at_ms").coerceAtLeast(0L)
        )
    }.getOrNull()

    private const val MAX_DETAIL_CHARS = 1_024
}

internal class LargeTurboQnnModelStateStore(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)

    fun read(): PersistedLargeTurboQnnModelState? =
        preferences.getString(KEY_STATE, null)?.let(LargeTurboQnnModelStateCodec::decode)

    fun write(state: LargeTurboQnnModelState, updatedAtMillis: Long = System.currentTimeMillis()) {
        preferences.edit()
            .putString(
                KEY_STATE,
                LargeTurboQnnModelStateCodec.encode(PersistedLargeTurboQnnModelState(state, updatedAtMillis))
            )
            .apply()
    }

    fun clear() {
        preferences.edit().remove(KEY_STATE).apply()
    }

    private companion object {
        const val PREFERENCES = "galaxyssi_qnn_large_turbo_download_v1"
        const val KEY_STATE = "state"
    }
}
