package com.galaxyssi.chat

import android.content.Context
import android.os.Build
import android.provider.Settings
import java.util.Locale

internal object GalaxySSIDeviceIdentityName {
    private const val MAX_DEVICE_NAME_LENGTH = 48

    fun current(context: Context): String = format(
        deviceName = resolveDeviceName(context),
        galaxyssiId = GalaxySSICrypto.localGalaxySSIId()
    )

    fun format(deviceName: String, galaxyssiId: String): String {
        val normalizedName = deviceName
            .trim()
            .replace(Regex("\\s+"), " ")
            .take(MAX_DEVICE_NAME_LENGTH)
            .trim()
            .ifBlank { "Android" }
        val identity = galaxyssiId.substringAfter(':', galaxyssiId)
            .filter(Char::isLetterOrDigit)
        val suffix = identity.takeLast(4).uppercase(Locale.ROOT)
        return if (suffix.isBlank()) normalizedName else "$normalizedName · $suffix"
    }

    fun isLegacyDefault(name: String): Boolean {
        val normalized = name.trim()
        return normalized.isBlank() ||
            normalized.equals("Me", ignoreCase = true) ||
            normalized == "我"
    }

    private fun resolveDeviceName(context: Context): String {
        val resolver = context.contentResolver
        val configuredName = sequenceOf(
            runCatching { Settings.Global.getString(resolver, "device_name") }.getOrNull(),
            runCatching { Settings.Secure.getString(resolver, "bluetooth_name") }.getOrNull(),
            runCatching { Settings.Secure.getString(resolver, "device_name") }.getOrNull()
        ).firstOrNull { !it.isNullOrBlank() }
        if (!configuredName.isNullOrBlank()) return configuredName

        val manufacturer = Build.MANUFACTURER.trim()
        val model = Build.MODEL.trim()
        return when {
            model.isBlank() -> manufacturer.ifBlank { "Android" }
            manufacturer.isBlank() || model.contains(manufacturer, ignoreCase = true) -> model
            else -> "$manufacturer $model"
        }
    }
}
