package com.signalasi.chat

import android.app.ActivityManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import kotlin.math.roundToInt

enum class AgentDeviceProfileKind {
    PHONE,
    TABLET,
    AUTOMOTIVE,
    LEGACY_SAMSUNG_PHONE,
    LEGACY_SAMSUNG_TABLET
}

data class AgentDeviceProfileSignals(
    val manufacturer: String,
    val sdkInt: Int,
    val smallestScreenWidthDp: Int,
    val automotive: Boolean,
    val lowRamDevice: Boolean,
    val totalRamBytes: Long
)

data class AgentDeviceProfile(
    val kind: AgentDeviceProfileKind,
    val id: String,
    val maxReadReasoningTasks: Int,
    val maxTeamConcurrency: Int,
    val maxQemuCpuCount: Int,
    val maxQemuMemoryMegabytes: Int,
    val maxScreenCaptureLongEdgePx: Int,
    val minimumTouchTargetDp: Int,
    val voiceFirst: Boolean,
    val reduceMotion: Boolean,
    val conservativeMedia: Boolean
) {
    fun constrainCaptureSize(width: Int, height: Int): Pair<Int, Int> {
        val safeWidth = width.coerceAtLeast(MIN_CAPTURE_EDGE_PX)
        val safeHeight = height.coerceAtLeast(MIN_CAPTURE_EDGE_PX)
        val longEdge = maxOf(safeWidth, safeHeight)
        if (longEdge <= maxScreenCaptureLongEdgePx) return safeWidth to safeHeight
        val scale = maxScreenCaptureLongEdgePx.toDouble() / longEdge.toDouble()
        return (safeWidth * scale).roundToInt().coerceAtLeast(MIN_CAPTURE_EDGE_PX) to
            (safeHeight * scale).roundToInt().coerceAtLeast(MIN_CAPTURE_EDGE_PX)
    }

    fun adaptMedia(profile: AgentMediaDeliveryProfile): AgentMediaDeliveryProfile {
        if (!conservativeMedia) return profile
        return profile.copy(
            imageTargetBytes = minOf(profile.imageTargetBytes, CONSERVATIVE_IMAGE_BYTES),
            audioSampleRateHz = minOf(profile.audioSampleRateHz, CONSERVATIVE_AUDIO_SAMPLE_RATE_HZ),
            audioBitRateBps = minOf(profile.audioBitRateBps, CONSERVATIVE_AUDIO_BIT_RATE_BPS)
        )
    }

    private companion object {
        const val MIN_CAPTURE_EDGE_PX = 320
        const val CONSERVATIVE_IMAGE_BYTES = 64 * 1024
        const val CONSERVATIVE_AUDIO_SAMPLE_RATE_HZ = 16_000
        const val CONSERVATIVE_AUDIO_BIT_RATE_BPS = 32_000
    }
}

object AgentDeviceProfilePolicy {
    fun resolve(signals: AgentDeviceProfileSignals): AgentDeviceProfile {
        val tablet = signals.smallestScreenWidthDp >= TABLET_MIN_WIDTH_DP
        val legacySamsung = signals.manufacturer.equals("samsung", ignoreCase = true) &&
            (
                signals.sdkInt <= LEGACY_SAMSUNG_MAX_SDK ||
                    signals.lowRamDevice ||
                    signals.totalRamBytes in 1..LEGACY_SAMSUNG_MAX_RAM_BYTES
                )
        return when {
            signals.automotive -> profile(
                kind = AgentDeviceProfileKind.AUTOMOTIVE,
                id = "automotive",
                readTasks = 1,
                teamConcurrency = 1,
                qemuCpu = 1,
                qemuMemoryMb = 512,
                captureLongEdgePx = 1_280,
                touchTargetDp = 64,
                voiceFirst = true,
                reduceMotion = true,
                conservativeMedia = true
            )
            tablet && legacySamsung -> profile(
                kind = AgentDeviceProfileKind.LEGACY_SAMSUNG_TABLET,
                id = "legacy_samsung_tablet",
                readTasks = 1,
                teamConcurrency = 2,
                qemuCpu = 2,
                qemuMemoryMb = 768,
                captureLongEdgePx = 1_400,
                touchTargetDp = 52,
                reduceMotion = true,
                conservativeMedia = true
            )
            tablet -> profile(
                kind = AgentDeviceProfileKind.TABLET,
                id = "tablet",
                readTasks = 3,
                teamConcurrency = AgentConnectorCapacityPolicy.MAX_PARALLEL_RUNS,
                qemuCpu = 6,
                qemuMemoryMb = 1_536,
                captureLongEdgePx = 2_048,
                touchTargetDp = 48
            )
            legacySamsung -> profile(
                kind = AgentDeviceProfileKind.LEGACY_SAMSUNG_PHONE,
                id = "legacy_samsung_phone",
                readTasks = 1,
                teamConcurrency = 1,
                qemuCpu = 2,
                qemuMemoryMb = 640,
                captureLongEdgePx = 1_280,
                touchTargetDp = 48,
                reduceMotion = true,
                conservativeMedia = true
            )
            else -> profile(
                kind = AgentDeviceProfileKind.PHONE,
                id = "phone",
                readTasks = 2,
                teamConcurrency = AgentConnectorCapacityPolicy.MAX_PARALLEL_RUNS,
                qemuCpu = 6,
                qemuMemoryMb = 1_536,
                captureLongEdgePx = 1_920,
                touchTargetDp = 48
            )
        }
    }

    private fun profile(
        kind: AgentDeviceProfileKind,
        id: String,
        readTasks: Int,
        teamConcurrency: Int,
        qemuCpu: Int,
        qemuMemoryMb: Int,
        captureLongEdgePx: Int,
        touchTargetDp: Int,
        voiceFirst: Boolean = false,
        reduceMotion: Boolean = false,
        conservativeMedia: Boolean = false
    ) = AgentDeviceProfile(
        kind = kind,
        id = id,
        maxReadReasoningTasks = readTasks,
        maxTeamConcurrency = teamConcurrency,
        maxQemuCpuCount = qemuCpu,
        maxQemuMemoryMegabytes = qemuMemoryMb,
        maxScreenCaptureLongEdgePx = captureLongEdgePx,
        minimumTouchTargetDp = touchTargetDp,
        voiceFirst = voiceFirst,
        reduceMotion = reduceMotion,
        conservativeMedia = conservativeMedia
    )

    private const val TABLET_MIN_WIDTH_DP = 600
    private const val LEGACY_SAMSUNG_MAX_SDK = 30
    private const val LEGACY_SAMSUNG_MAX_RAM_BYTES = 4L * 1024L * 1024L * 1024L
}

object AgentDeviceProfileDetector {
    fun detect(context: Context): AgentDeviceProfile {
        val activityManager = context.getSystemService(ActivityManager::class.java)
        val memory = ActivityManager.MemoryInfo()
        runCatching { activityManager?.getMemoryInfo(memory) }
        val modeType = context.resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK
        val automotive = modeType == Configuration.UI_MODE_TYPE_CAR ||
            context.packageManager.hasSystemFeature(AUTOMOTIVE_FEATURE)
        return AgentDeviceProfilePolicy.resolve(
            AgentDeviceProfileSignals(
                manufacturer = Build.MANUFACTURER.orEmpty(),
                sdkInt = Build.VERSION.SDK_INT,
                smallestScreenWidthDp = context.resources.configuration.smallestScreenWidthDp,
                automotive = automotive,
                lowRamDevice = activityManager?.isLowRamDevice == true,
                totalRamBytes = memory.totalMem
            )
        )
    }

    private const val AUTOMOTIVE_FEATURE = "android.hardware.type.automotive"
}
