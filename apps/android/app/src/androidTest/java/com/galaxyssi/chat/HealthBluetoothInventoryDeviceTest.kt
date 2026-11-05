package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthBluetoothInventoryDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val zone = ZoneId.systemDefault()
    private val now = System.currentTimeMillis()

    @Test fun keysetPagesExcludeDeletedAndManualRowsAndUseLatestRecordPerDevice() = fixture { names ->
        HealthRecordStore(context, names.records).use { store ->
            repeat(34) { index -> save(store, "test-monitor-$index", now - 120_000L - index * 1000L) }
            val deleted = save(store, "deleted-monitor", now - 100_000)
            assertTrue(store.delete(deleted.id, deleted.revision))
            val latest = save(store, "test-monitor-0", now - 20_000)
            assertTrue(store.save(HealthDraft(values = mapOf("systolic" to "118", "diastolic" to "76"),
                measuredAt = now - 1000)) is HealthSaveResult.Saved)
            val first = HealthBluetoothInventory.page(context, names, now, zone)
            val second = HealthBluetoothInventory.page(context, names, now, zone, requireNotNull(first.next))
            assertEquals(30, first.devices.size)
            assertEquals(4, second.devices.size)
            assertNull(second.next)
            val all = first.devices + second.devices
            assertEquals(34, all.map { it.group }.toSet().size)
            assertEquals(1, all.count { it.group == latest.bluetoothGroup && it.measuredAt == latest.draft.measuredAt })
            assertFalse(all.any { it.group == deleted.bluetoothGroup })
        }
        HealthPrivacyStore(context, names.privacy).use { access ->
            val events = access.page().entries
            assertEquals(2, events.size)
            assertTrue(events.all { it.scope.source == HealthAccessSource.BLUETOOTH &&
                it.scope.metrics == setOf(HealthMetric.BLOOD_PRESSURE) && it.outcome == HealthAccessOutcome.COMPLETE })
        }
    }

    @Test fun nativeInventorySeparatesIdenticalNamesAndOnlyOpensTheSelectedDeviceHistory() = fixture { names ->
        assumeFalse("Device inventory UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val (first, second) = HealthRecordStore(context, names.records).use { store ->
            val clock = LocalDateTime.ofInstant(Instant.ofEpochMilli(now - 3_600_000L), zone).withNano(0)
            val receipt = healthTrendPressure("first-monitor", now - 60_000).let { it.copy(packet = it.packet.copy(deviceClock = clock)) }
            (store.saveBluetooth(receipt, "unspecified") {} as HealthSaveResult.Saved).record to
                save(store, "second-monitor", now - 120_000)
        }
        assertNotEquals(first.draft.measuredAt, first.deviceReceivedAt)
        val intent = Intent(context, HealthSourcesActivity::class.java).putExtra("health_sources_test_id", names.fixture)
        ActivityScenario.launch<HealthSourcesActivity>(intent).use { scenario ->
            await(scenario, "health-sources-inventory-toggle")
            scenario.onActivity {
                assertNull(it.window.decorView.findViewWithTag<View>(tag(first)))
                assertTrue(it.window.decorView.findViewWithTag<View>("health-sources-inventory-toggle").performClick())
            }
            await(scenario, tag(first))
            scenario.onActivity { activity ->
                val root = activity.window.decorView
                val a = root.findViewWithTag<View>(tag(first))
                val b = root.findViewWithTag<View>(tag(second))
                val aText = texts(a)
                val bText = texts(b)
                assertTrue(activity.healthBluetoothTrendLabel(first.bluetoothGroup, first.platformOrigin) in aText)
                assertTrue(activity.healthBluetoothTrendLabel(second.bluetoothGroup, second.platformOrigin) in bText)
                val format = java.text.DateFormat.getDateTimeInstance(java.text.DateFormat.MEDIUM, java.text.DateFormat.SHORT)
                val measurement = activity.getString(R.string.health_sources_device_measurement, format.format(java.util.Date(first.draft.measuredAt)))
                val receipt = activity.getString(R.string.health_sources_device_receipt, format.format(java.util.Date(requireNotNull(first.deviceReceivedAt))))
                assertTrue(aText.any { measurement in it && receipt in it })
            }
            val monitor = instrumentation.addMonitor(HealthTrendRecordsActivity::class.java.name, null, false)
            try {
                scenario.onActivity { assertTrue(it.window.decorView.findViewWithTag<View>(tag(first)).performClick()) }
                val child = requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 10_000) as? HealthTrendRecordsActivity)
                try {
                    assertEquals(first.bluetoothGroup, child.intent.healthTrendSpec()?.source?.bluetoothGroup)
                    waitFor("filtered history") {
                        var ready = false
                        instrumentation.runOnMainSync {
                            val root = child.window.decorView
                            ready = root.findViewWithTag<View>("health-trend-record-${first.id}") != null
                            if (ready) assertNull(root.findViewWithTag<View>("health-trend-record-${second.id}"))
                        }
                        ready
                    }
                } finally {
                    instrumentation.runOnMainSync { child.finish() }
                    instrumentation.waitForIdleSync()
                }
            } finally { instrumentation.removeMonitor(monitor) }
            await(scenario, tag(first))
            scenario.recreate()
            await(scenario, tag(second))
            HealthPrivacyStore(context, names.privacy).use { privacy ->
                privacy.change(HealthPrivacyOption.CONFIRMED_METRICS, false, privacy.policy().version)
            }
            await(scenario, "health-sources-inventory-status")
            scenario.onActivity {
                val root = it.window.decorView
                assertNull(root.findViewWithTag<View>(tag(first)))
                assertNull(root.findViewWithTag<View>(tag(second)))
                assertEquals(it.getString(R.string.health_privacy_trend_blocked),
                    root.findViewWithTag<TextView>("health-sources-inventory-status").text.toString())
            }
        }
    }

    private fun tag(record: HealthObservation) = "health-sources-device-${record.bluetoothGroup}"
    private fun save(store: HealthRecordStore, token: String, time: Long) =
        (store.saveBluetooth(healthTrendPressure(token, time), "unspecified") {} as HealthSaveResult.Saved).record

    private fun texts(view: View): List<String> = when (view) {
        is TextView -> listOf(view.text.toString())
        is android.view.ViewGroup -> (0 until view.childCount).flatMap { texts(view.getChildAt(it)) }
        else -> emptyList()
    }

    private fun await(scenario: ActivityScenario<HealthSourcesActivity>, tag: String) = waitFor(tag) {
        var ready = false
        scenario.onActivity { ready = it.window.decorView.findViewWithTag<View>(tag) != null }
        ready
    }

    private fun waitFor(label: String, condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 12_000
        do {
            if (condition()) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Missing $label")
    }

    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
}
