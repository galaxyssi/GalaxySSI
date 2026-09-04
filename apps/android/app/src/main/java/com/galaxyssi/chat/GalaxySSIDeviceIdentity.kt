package com.galaxyssi.chat

import android.content.Context
import android.os.Build
import android.provider.Settings
import org.json.JSONObject
import java.util.Locale

internal data class GalaxySSILocalDeviceProfile(
    val deviceId: String,
    val displayName: String,
    val deviceName: String,
    val manufacturer: String,
    val model: String,
    val platformVersion: String,
    val profileName: String
)

internal object GalaxySSIDeviceIdentity {
    fun current(context: Context, profile: JSONObject, fingerprint: String): GalaxySSILocalDeviceProfile {
        val configuredName = runCatching {
            Settings.Global.getString(context.contentResolver, "device_name")
        }.getOrNull().orEmpty()
        val model = clean(Build.MODEL)
        val manufacturer = clean(Build.MANUFACTURER)
        val deviceName = clean(configuredName).ifBlank { model }.ifBlank { manufacturer }.ifBlank { "Android" }
        val profileName = clean(profile.optString("name"))
        return GalaxySSILocalDeviceProfile(
            deviceId = profile.optString("device_id").ifBlank { "phone_${fingerprint.take(16)}" },
            displayName = composeDisplayName(deviceName, model, profileName, fingerprint),
            deviceName = deviceName,
            manufacturer = manufacturer,
            model = model,
            platformVersion = Build.VERSION.RELEASE.orEmpty(),
            profileName = profileName
        )
    }

    fun composeDisplayName(
        deviceName: String,
        model: String,
        profileName: String,
        fingerprint: String
    ): String {
        val base = clean(deviceName).ifBlank { clean(model) }.ifBlank { "Android" }
        val profile = clean(profileName)
        if (profile.isNotBlank() && !profile.equals("Me", ignoreCase = true) &&
            !profile.equals(base, ignoreCase = true)
        ) {
            return "$base \u00b7 $profile"
        }
        val suffix = fingerprint.filter(Char::isLetterOrDigit).take(4).uppercase(Locale.ROOT)
        return if (suffix.isBlank()) base else "$base \u00b7 $suffix"
    }

    private fun clean(value: String): String = value.trim().replace(Regex("\\s+"), " ").take(120)
}
