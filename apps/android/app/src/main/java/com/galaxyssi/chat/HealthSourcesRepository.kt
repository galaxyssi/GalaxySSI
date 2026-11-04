package com.galaxyssi.chat

import android.content.Context
import android.content.pm.PackageManager
import androidx.health.connect.client.HealthConnectClient
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout

internal enum class HealthPlatformAvailability { AVAILABLE, INSTALL_OR_UPDATE, UNSUPPORTED, CHECK_FAILED }

internal data class HealthLocalSources(
    val manualMeasuredAt: Long?,
    val confirmedImports: Long,
    val originals: Long,
)

internal data class HealthSourcesSnapshot(
    val platform: HealthPlatformAvailability,
    val bluetoothLe: Boolean,
    val local: HealthLocalSources?,
    val platformScopes: Int?,
    val lastConfirmedImport: Long,
)

internal object HealthSourcesRepository {
    const val PROVIDER_PACKAGE = "com.google.android.apps.healthdata"

    fun platform(context: Context): HealthPlatformAvailability = try {
        when (HealthConnectClient.getSdkStatus(context, PROVIDER_PACKAGE)) {
            HealthConnectClient.SDK_AVAILABLE -> HealthPlatformAvailability.AVAILABLE
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> HealthPlatformAvailability.INSTALL_OR_UPDATE
            HealthConnectClient.SDK_UNAVAILABLE -> HealthPlatformAvailability.UNSUPPORTED
            else -> HealthPlatformAvailability.CHECK_FAILED
        }
    } catch (_: RuntimeException) {
        HealthPlatformAvailability.CHECK_FAILED
    }

    fun load(context: Context, names: HealthOverviewDatabases, now: Long): HealthSourcesSnapshot {
        val local = runCatching {
            val records = if (context.getDatabasePath(names.records).isFile) {
                HealthRecordStore(context, names.records).use { it.latestManualMeasurement(now) to it.confirmedImportCount() }
            } else null to 0L
            val originals = if (context.getDatabasePath(names.originals).isFile) {
                HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { it.originalCount() }
            } else 0L
            HealthLocalSources(records.first, records.second, originals)
        }.getOrNull()
        val status = platform(context)
        val scopes = if (status == HealthPlatformAvailability.AVAILABLE) runCatching {
            runBlocking {
                withTimeout(5_000) { HealthConnectImport.allowed(HealthConnectScope.entries.toSet(), AndroidHealthConnectReader(context).granted()).size }
            }
        }.getOrNull() else null
        val lastImport = if (names.fixture == null) HealthConnectSettings.lastImport(context) else 0
        return HealthSourcesSnapshot(status, context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE), local, scopes, lastImport)
    }
}
