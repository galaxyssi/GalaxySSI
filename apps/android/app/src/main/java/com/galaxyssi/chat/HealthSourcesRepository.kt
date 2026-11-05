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
    val scopes: List<HealthSourceScope>,
    val grantVerified: Boolean,
    val syncHistory: HealthSourceSyncHistory?,
    val lastConfirmedImport: Long,
)

internal enum class HealthSourceAccess { NOT_SELECTED, GRANTED, MISSING_GRANT, UNVERIFIED, PLATFORM_UNAVAILABLE }

internal data class HealthSourceScope(val scope: HealthConnectScope, val access: HealthSourceAccess)

internal data class HealthSourceSyncHistory(
    val checkpoints: Map<HealthConnectScope, HealthSourceSyncTime>,
    val bluetoothReceipt: Long,
)

internal data class HealthSourceSyncTime(val lastAttempt: Long, val lastSuccess: Long)

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

    fun scopes(platform: HealthPlatformAvailability, selected: Set<HealthConnectScope>, granted: Set<String>?) =
        HealthConnectScope.entries.map { scope ->
            val access = when {
                scope !in selected -> HealthSourceAccess.NOT_SELECTED
                platform == HealthPlatformAvailability.CHECK_FAILED -> HealthSourceAccess.UNVERIFIED
                platform != HealthPlatformAvailability.AVAILABLE -> HealthSourceAccess.PLATFORM_UNAVAILABLE
                granted == null -> HealthSourceAccess.UNVERIFIED
                scope.permission in granted -> HealthSourceAccess.GRANTED
                else -> HealthSourceAccess.MISSING_GRANT
            }
            HealthSourceScope(scope, access)
        }

    fun load(context: Context, names: HealthOverviewDatabases, now: Long): HealthSourcesSnapshot {
        val (records, sync) = if (!context.getDatabasePath(names.records).isFile) {
            (null to 0L) to HealthSourceSyncHistory(emptyMap(), 0)
        } else runCatching {
            HealthRecordStore(context, names.records).use { store ->
                val stats = runCatching { store.latestManualMeasurement(now) to store.confirmedImportCount() }.getOrNull()
                val history = runCatching {
                    val checkpoints = HealthConnectScope.entries.associateWith { scope ->
                        val mark = store.healthSyncCheckpoint(scope)
                        HealthSourceSyncTime(mark.lastAttempt, mark.lastSuccess)
                    }
                    HealthSourceSyncHistory(checkpoints, store.lastBluetoothReceipt())
                }.getOrNull()
                stats to history
            }
        }.getOrElse { null to null }
        val local = records?.let { (manual, imports) ->
            runCatching {
                val originals = if (context.getDatabasePath(names.originals).isFile) {
                    HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { it.originalCount() }
                } else 0L
                HealthLocalSources(manual, imports, originals)
            }.getOrNull()
        }
        val status = platform(context)
        val selected = if (names.fixture == null) HealthConnectSettings.selection(context) else emptySet()
        val grants = if (names.fixture == null && status == HealthPlatformAvailability.AVAILABLE) runCatching {
            runBlocking {
                withTimeout(5_000) { AndroidHealthConnectReader(context).granted() }
            }
        }.getOrNull() else null
        val lastImport = if (names.fixture == null) HealthConnectSettings.lastImport(context) else 0
        return HealthSourcesSnapshot(status, context.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE), local,
            scopes(status, selected, grants), grants != null, sync, lastImport)
    }
}
