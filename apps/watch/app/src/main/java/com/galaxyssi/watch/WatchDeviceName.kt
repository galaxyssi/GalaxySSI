package com.galaxyssi.watch

import android.content.Context
import android.Manifest
import android.bluetooth.BluetoothManager
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale

/** One display label for Wi-Fi discovery and the Desktop pairing registry. */
internal object WatchDeviceName {
    private val trailingSuffix = Regex("\\s*(?:\\(([A-Za-z0-9]{4})\\)|\\u00b7\\s*([A-Za-z0-9]{4}))$")

    fun current(context: Context): String {
        val resolver = context.contentResolver
        return resolve(
            globalName = runCatching { Settings.Global.getString(resolver, "device_name") }.getOrNull(),
            bluetoothName = runCatching {
                if (context.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED)
                    context.getSystemService(BluetoothManager::class.java)?.adapter?.name
                else null
            }.getOrNull(),
            secureName = runCatching { Settings.Secure.getString(resolver, "device_name") }.getOrNull(),
            model = Build.MODEL.orEmpty(),
            stableId = runCatching { Settings.Secure.getString(resolver, Settings.Secure.ANDROID_ID) }.getOrNull().orEmpty()
        )
    }

    fun resolve(globalName: String?, bluetoothName: String?, secureName: String?, model: String, stableId: String): String {
        val modelName = clean(model)
        val candidates = listOf(globalName, bluetoothName, secureName).map { clean(it.orEmpty()) }
            .filter { it.isNotEmpty() && !it.equals("GalaxySSI Watch", ignoreCase = true) }
        // Samsung's global name may only contain SM-Rxxx; prefer its friendly Bluetooth name in that case.
        val name = candidates.firstOrNull { !it.equals(modelName, ignoreCase = true) }
            ?: candidates.firstOrNull() ?: modelName.ifBlank { "Watch" }
        val existing = trailingSuffix.find(name)
        val suffix = existing?.let { it.groupValues[1].ifBlank { it.groupValues[2] }.uppercase(Locale.ROOT) }
            ?: stableId.takeIf { it.isNotBlank() }?.let {
                MessageDigest.getInstance("SHA-256").digest(it.toByteArray(Charsets.UTF_8))
                    .take(2).joinToString("") { byte -> "%02X".format(Locale.ROOT, byte.toInt() and 255) }
            }.orEmpty()
        val base = (if (existing == null) name else name.substring(0, existing.range.first)).trim().ifBlank { "Watch" }
        val tail = if (suffix.isEmpty()) "" else " \u00b7 $suffix"
        // DNS-SD service labels are limited to 63 UTF-8 bytes; keep the device discriminator intact.
        val budget = 63 - tail.toByteArray(Charsets.UTF_8).size
        var bytes = 0
        val shortened = StringBuilder()
        for (point in base.codePoints().toArray()) {
            val next = String(Character.toChars(point))
            val size = next.toByteArray(Charsets.UTF_8).size
            if (bytes + size > budget) break
            shortened.append(next)
            bytes += size
        }
        return shortened.toString().trimEnd() + tail
    }

    fun addPairingFields(payload: JSONObject, displayName: String): JSONObject = payload
        .put("client_name", displayName)
        .put("device_name", displayName)

    private fun clean(value: String): String = value
        .replace(Regex("[\\p{Cc}\\p{Cf}]"), " ")
        .replace(Regex("\\s+"), " ").trim()
}
