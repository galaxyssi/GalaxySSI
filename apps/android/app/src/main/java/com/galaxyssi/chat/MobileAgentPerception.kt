package com.galaxyssi.chat

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import android.provider.AlarmClock
import android.provider.CalendarContract
import android.provider.ContactsContract
import android.util.Log
import com.galaxyssi.chat.voice.VoiceFeatureFlags
import com.galaxyssi.chat.voice.agent.VoiceAgentRunBridge
import com.galaxyssi.chat.voice.agent.VoiceAgentRunRequest
import com.galaxyssi.chat.voice.metrics.VoiceLatencyTraceContext
import com.galaxyssi.chat.voice.modelstream.ModelStreamEvent
import com.galaxyssi.chat.voice.modelstream.ModelStreamUiMerger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Locale
import java.util.Date
import java.text.SimpleDateFormat
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.FutureTask
import java.util.concurrent.TimeUnit

interface ScreenPerceptionProvider {
    fun capture(): ScreenContext
    fun capture(foregroundApp: String, pageTitle: String): ScreenContext
}

class AndroidScreenPerceptionProvider(private val context: Context) : ScreenPerceptionProvider {
    override fun capture(): ScreenContext {
        if (AgentScreenCaptureService.isActive()) {
            AgentScreenCaptureService.requestCapture(context.applicationContext)
        }
        val defaultTitle = context.getString(R.string.tab_agent)
        val screen = GalaxySSIAccessibilityService.captureCurrentScreen(
            defaultApp = "GalaxySSI",
            defaultTitle = defaultTitle
        ) ?: ScreenPerceptionState.current(
            defaultApp = "GalaxySSI",
            defaultTitle = defaultTitle
        )
        return screen.withClipboardContext()
    }

    override fun capture(foregroundApp: String, pageTitle: String): ScreenContext {
        if (AgentScreenCaptureService.isActive()) {
            AgentScreenCaptureService.requestCapture(context.applicationContext)
        }
        val screen = GalaxySSIAccessibilityService.captureCurrentScreen(
            defaultApp = foregroundApp,
            defaultTitle = pageTitle
        ) ?: ScreenPerceptionState.current(
            defaultApp = foregroundApp,
            defaultTitle = pageTitle
        )
        return screen.withClipboardContext()
    }

    internal fun ScreenContext.withClipboardContext(): ScreenContext =
        copy(
            clipboard = clipboardContext(),
            notifications = GalaxySSINotificationListenerService.currentContext(),
            installedApps = installedApps(),
            deviceStatus = deviceStatus()
        )

    internal fun clipboardContext(): ClipboardContext {
        val text = runCatching {
            val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return@runCatching ""
            clipboard.primaryClip
                ?.takeIf { it.itemCount > 0 }
                ?.getItemAt(0)
                ?.coerceToText(context)
                ?.toString()
                .orEmpty()
        }.getOrDefault("")
        if (text.isBlank()) return ClipboardContext()
        val normalized = text.replace(Regex("\\s+"), " ").trim()
        return ClipboardContext(
            hasText = true,
            textLength = text.length,
            textHash = text.hashCode().toString(),
            preview = normalized.take(96),
            sensitiveFlags = sensitiveFlagsForText(text)
        )
    }

    internal fun installedApps(): List<InstalledAppInfo> {
        val packageManager = context.packageManager
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        return runCatching {
            packageManager.queryIntentActivities(launcherIntent, 0)
                .mapNotNull { resolveInfo ->
                    val activityInfo = resolveInfo.activityInfo ?: return@mapNotNull null
                    val label = resolveInfo.loadLabel(packageManager)?.toString().orEmpty().trim()
                    val packageName = activityInfo.packageName.orEmpty()
                    if (label.isBlank() || packageName.isBlank()) return@mapNotNull null
                    InstalledAppInfo(label = label.take(80), packageName = packageName)
                }
                .distinctBy { it.packageName }
                .sortedBy { it.label.lowercase(Locale.US) }
                .take(120)
        }.getOrDefault(emptyList())
    }

    internal fun deviceStatus(): AgentDeviceStatusContext {
        val batteryIntent = runCatching {
            context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        }.getOrNull()
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val percent = if (level >= 0 && scale > 0) ((level * 100f) / scale).toInt().coerceIn(0, 100) else -1
        val batteryStatus = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = batteryStatus == BatteryManager.BATTERY_STATUS_CHARGING ||
            batteryStatus == BatteryManager.BATTERY_STATUS_FULL
        val powerSave = runCatching {
            context.getSystemService(PowerManager::class.java)?.isPowerSaveMode == true
        }.getOrDefault(false)
        val network = networkStatus()
        val storage = storageStatus()
        return AgentDeviceStatusContext(
            batteryPercent = percent,
            charging = charging,
            powerSaveMode = powerSave,
            network = network,
            freeStorageMb = storage.first,
            totalStorageMb = storage.second
        )
    }

    internal fun networkStatus(): String = runCatching {
        val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return@runCatching "unknown"
        val network = connectivity.activeNetwork ?: return@runCatching "offline"
        val capabilities = connectivity.getNetworkCapabilities(network) ?: return@runCatching "unknown"
        when {
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) -> "internet"
            else -> "offline"
        }
    }.getOrDefault("unknown")

    internal fun storageStatus(): Pair<Long, Long> = runCatching {
        val statFs = StatFs(Environment.getDataDirectory().absolutePath)
        val freeMb = statFs.availableBytes / (1024L * 1024L)
        val totalMb = statFs.totalBytes / (1024L * 1024L)
        freeMb to totalMb
    }.getOrDefault(0L to 0L)
}
