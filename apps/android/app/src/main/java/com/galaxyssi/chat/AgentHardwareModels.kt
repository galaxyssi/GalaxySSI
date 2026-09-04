package com.galaxyssi.chat

enum class AgentHardwareCapability {
    BATTERY,
    POWER,
    MEMORY,
    STORAGE,
    NETWORK,
    FOREGROUND_LOCATION,
    SENSOR_LIST,
    SENSOR_SAMPLE,
    FLASHLIGHT,
    BLUETOOTH_STATUS,
    BLUETOOTH_DISCOVERY,
    BLUETOOTH_PAIRING_HANDOFF,
    NFC_STATUS,
    INSTALLED_APPS,
    PACKAGE_DETAIL
}

data class AgentBatterySnapshot(
    val percent: Int?,
    val charging: Boolean,
    val plugged: String,
    val status: String,
    val health: String,
    val temperatureCelsius: Double?,
    val voltageMillivolts: Int?,
    val chargeCounterMicroampHours: Long?,
    val observedAtEpochMillis: Long
)

data class AgentPowerSnapshot(
    val interactive: Boolean,
    val powerSaveMode: Boolean,
    val deviceIdleMode: Boolean,
    val ignoringBatteryOptimizations: Boolean,
    val observedAtEpochMillis: Long
)

data class AgentDeviceMemorySnapshot(
    val totalBytes: Long,
    val availableBytes: Long,
    val lowMemory: Boolean,
    val lowMemoryThresholdBytes: Long,
    val observedAtEpochMillis: Long
)

data class AgentStorageSnapshot(
    val scope: String,
    val totalBytes: Long,
    val availableBytes: Long,
    val lowStorage: Boolean,
    val observedAtEpochMillis: Long
)

data class AgentNetworkSnapshot(
    val connected: Boolean,
    val validated: Boolean,
    val metered: Boolean,
    val roaming: Boolean,
    val transports: List<String>,
    val downstreamKbps: Int,
    val upstreamKbps: Int,
    val observedAtEpochMillis: Long
)

data class AgentForegroundLocationSnapshot(
    val latitude: Double,
    val longitude: Double,
    val accuracyMeters: Double,
    val altitudeMeters: Double?,
    val bearingDegrees: Double?,
    val speedMetersPerSecond: Double?,
    val provider: String,
    val fixAtEpochMillis: Long,
    val observedAtEpochMillis: Long,
    val source: String
)

data class AgentSensorDescriptor(
    val type: String,
    val androidType: Int,
    val name: String,
    val vendor: String,
    val version: Int,
    val maximumRange: Double,
    val resolution: Double,
    val powerMilliamps: Double,
    val reportingMode: String,
    val wakeUp: Boolean,
    val runtimePermission: String? = null
)

data class AgentSensorSample(
    val type: String,
    val androidType: Int,
    val values: List<Double>,
    val accuracy: Int,
    val observedAtEpochMillis: Long
)

data class AgentFlashlightRequestResult(
    val requestedEnabled: Boolean,
    val requestAccepted: Boolean,
    val stateVerified: Boolean = false
)

data class AgentBluetoothStatusSnapshot(
    val supported: Boolean,
    val enabled: Boolean,
    val discovering: Boolean,
    val bondedDeviceCount: Int?,
    val observedAtEpochMillis: Long
)

data class AgentBluetoothDeviceObservation(
    val address: String,
    val name: String?,
    val bondState: String,
    val deviceType: String
)

data class AgentBluetoothDiscoveryResult(
    val devices: List<AgentBluetoothDeviceObservation>,
    val completed: Boolean,
    val timedOut: Boolean,
    val observedAtEpochMillis: Long
)

data class AgentSystemHandoffResult(
    val launched: Boolean,
    val action: String,
    val completed: Boolean = false
)

data class AgentNfcStatusSnapshot(
    val supported: Boolean,
    val enabled: Boolean,
    val secureNfcSupported: Boolean,
    val secureNfcEnabled: Boolean,
    val observedAtEpochMillis: Long
)

data class AgentInstalledAppSummary(
    val packageName: String,
    val label: String,
    val versionName: String?,
    val versionCode: Long,
    val enabled: Boolean,
    val systemApp: Boolean,
    val launchable: Boolean
)

data class AgentPackageDetail(
    val packageName: String,
    val visible: Boolean,
    val label: String? = null,
    val versionName: String? = null,
    val versionCode: Long? = null,
    val enabled: Boolean? = null,
    val systemApp: Boolean? = null,
    val launchable: Boolean? = null,
    val firstInstallTimeEpochMillis: Long? = null,
    val lastUpdateTimeEpochMillis: Long? = null,
    val targetSdk: Int? = null,
    val minSdk: Int? = null,
    val requestedPermissions: List<String> = emptyList()
)

class AgentHardwareNativeException(
    val code: String,
    override val message: String,
    val retryable: Boolean = false,
    val details: AgentNativeJsonObject = emptyMap(),
    cause: Throwable? = null
) : RuntimeException(message, cause)

interface AgentHardwarePlatformFacade {
    val implementationId: String

    fun availability(capability: AgentHardwareCapability): AgentNativeToolAvailability
    fun battery(): AgentBatterySnapshot
    fun power(): AgentPowerSnapshot
    fun memory(): AgentDeviceMemorySnapshot
    fun storage(): AgentStorageSnapshot
    fun network(): AgentNetworkSnapshot

    fun foregroundLocation(
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE
    ): AgentForegroundLocationSnapshot

    fun sensors(limit: Int): List<AgentSensorDescriptor>

    fun sampleSensor(
        type: String,
        timeoutMillis: Long,
        cancellationToken: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE
    ): AgentSensorSample

    fun setFlashlight(enabled: Boolean): AgentFlashlightRequestResult
    fun bluetoothStatus(): AgentBluetoothStatusSnapshot

    fun discoverBluetooth(
        timeoutMillis: Long,
        limit: Int,
        cancellationToken: AgentNativeToolCancellationToken = AgentNativeToolCancellationToken.NONE
    ): AgentBluetoothDiscoveryResult

    fun handoffBluetoothPairing(): AgentSystemHandoffResult
    fun nfcStatus(): AgentNfcStatusSnapshot
    fun installedApps(query: String, limit: Int): List<AgentInstalledAppSummary>
    fun packageDetail(packageName: String): AgentPackageDetail
}
