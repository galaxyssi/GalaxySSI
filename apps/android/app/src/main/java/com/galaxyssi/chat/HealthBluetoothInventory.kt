package com.galaxyssi.chat

import android.content.Context
import android.os.CancellationSignal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

internal data class HealthSavedBluetoothDevice(
    val group: String,
    val name: String,
    val measuredAt: Long,
    val receivedAt: Long?,
)

internal data class HealthBluetoothHistoryPreview(
    val group: String,
    val version: String,
    val count: Long,
    val first: Long,
    val last: Long,
)

internal class HealthBluetoothHistoryChanged : IllegalStateException("Bluetooth history changed after preview")

internal data class HealthBluetoothInventoryPage(
    val scope: HealthTrendSpec,
    val devices: List<HealthSavedBluetoothDevice>,
    val next: String?,
) {
    fun history(device: HealthSavedBluetoothDevice): HealthTrendSpec {
        require(device in devices)
        return scope.copy(source = HealthTrendSource(bluetoothGroup = device.group))
    }
}

internal object HealthBluetoothInventory {
    fun page(context: Context, names: HealthOverviewDatabases, now: Long, zone: ZoneId, after: String = "",
        signal: CancellationSignal? = null): HealthBluetoothInventoryPage {
        require(after.isEmpty() || isHealthBluetoothGroup(after))
        val first = LocalDate.of(1970, 1, 1)
        val metric = HealthMetric.BLOOD_PRESSURE
        val scope = HealthTrendSpec(metric, first, maxOf(first, Instant.ofEpochMilli(now).atZone(zone).toLocalDate()),
            zone, metric.units.first())
        if (!context.getDatabasePath(names.records).isFile) return HealthBluetoothInventoryPage(scope, emptyList(), null)
        val access = HealthAccessScope.trend(HealthAccessPurpose.TREND_SOURCES, scope).copy(source = HealthAccessSource.BLUETOOTH)
        return HealthPrivacyStore.track(context, access, names.privacy) {
            HealthRecordStore(context, names.records).use { store ->
                val groups = store.trendBluetoothGroups(scope, after, signal)
                val visible = groups.take(HealthRecordStore.PAGE_SIZE)
                val devices = visible.mapNotNull { group ->
                    signal?.throwIfCanceled()
                    store.latestBluetoothRecord(scope, group, signal)?.let { record ->
                        check(record.profileId == "self")
                        HealthSavedBluetoothDevice(group, record.platformOrigin, record.draft.measuredAt, record.deviceReceivedAt)
                    }
                }
                signal?.throwIfCanceled()
                HealthBluetoothInventoryPage(scope, devices, visible.lastOrNull().takeIf { groups.size > visible.size })
            }
        }
    }
}
