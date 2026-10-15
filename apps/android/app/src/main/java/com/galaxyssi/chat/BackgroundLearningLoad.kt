package com.galaxyssi.chat

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager

internal data class BackgroundLearningLoad(val deferMillis: Long = 0L, val spacingMillis: Long = 1_000L)

internal object BackgroundLearningLoadPolicy {
    fun evaluate(thermalStatus: Int, batteryTenthsC: Int, batteryPercent: Int, powered: Boolean,
        powerSave: Boolean): BackgroundLearningLoad = when {
        thermalStatus >= 3 || batteryTenthsC >= 430 -> BackgroundLearningLoad(5 * 60_000L, 60_000L)
        thermalStatus >= 2 || batteryTenthsC >= 400 -> BackgroundLearningLoad(2 * 60_000L, 30_000L)
        batteryPercent in 0..5 || (!powered && batteryPercent in 0..10) || powerSave ->
            BackgroundLearningLoad(5 * 60_000L, 30_000L)
        thermalStatus >= 1 || batteryTenthsC >= 380 -> BackgroundLearningLoad(spacingMillis = 30_000L)
        else -> BackgroundLearningLoad()
    }
}

/** Only discretionary learning/translation uses this gate, never chat, message transport or receipts. */
internal object BackgroundLearningLoadSampler {
    fun read(context: Context): BackgroundLearningLoad {
        val battery = runCatching { context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) }.getOrNull()
        val power = context.getSystemService(PowerManager::class.java)
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val percent = if (level >= 0 && scale > 0) (level * 100L / scale).toInt() else -1
        val thermal = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            runCatching { power?.currentThermalStatus ?: 0 }.getOrDefault(0) else 0
        return BackgroundLearningLoadPolicy.evaluate(thermal,
            battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, 0) ?: 0, percent,
            (battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0) != 0, power?.isPowerSaveMode == true)
    }
}
