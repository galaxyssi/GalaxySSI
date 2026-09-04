package com.galaxyssi.chat.voice.asr.local

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import com.galaxyssi.chat.BuildConfig
import java.io.File

class AndroidLargeTurboQnnDeviceCapabilityDetector(
    context: Context,
    private val modelStore: LargeTurboQnnModelStore = LargeTurboQnnModelStore(context.filesDir),
    private val manifest: LargeTurboQnnModelManifest = LargeTurboQnnModelCatalog.s26Ultra
) {
    private val appContext = context.applicationContext

    fun snapshot(
        activeModelState: QnnContextModelState = modelStore.inspectActive(manifest).state
    ): QnnAsrDeviceSnapshot {
        val memory = ActivityManager.MemoryInfo()
        appContext.getSystemService(ActivityManager::class.java)?.getMemoryInfo(memory)
        val nativeLibraries = File(appContext.applicationInfo.nativeLibraryDir)
            .listFiles()
            .orEmpty()
            .filter(File::isFile)
            .map(File::getName)
            .toSet()
        return QnnAsrDeviceSnapshot(
            androidApiLevel = Build.VERSION.SDK_INT,
            supportedAbis = Build.SUPPORTED_ABIS.orEmpty().toSet(),
            manufacturer = Build.MANUFACTURER.orEmpty(),
            brand = Build.BRAND.orEmpty(),
            hardware = Build.HARDWARE.orEmpty(),
            socManufacturer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                Build.SOC_MANUFACTURER.orEmpty()
            } else "",
            socModel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MODEL.orEmpty() else "",
            nativeLibraries = nativeLibraries,
            qnnRuntimeVersion = BuildConfig.QNN_RUNTIME_VERSION,
            availableMemoryBytes = memory.availMem.coerceAtLeast(0L),
            availableStorageBytes = appContext.filesDir.usableSpace.coerceAtLeast(0L),
            activeModelState = activeModelState
        )
    }

    fun decision(): QnnAsrDeviceDecision = LargeTurboQnnDevicePolicy(manifest).evaluate(snapshot())
}
