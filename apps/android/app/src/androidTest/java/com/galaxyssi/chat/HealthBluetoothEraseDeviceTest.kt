package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.view.inspector.WindowInspector
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.CancellationException
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthBluetoothEraseDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val now = System.currentTimeMillis()

    @Test fun transactionRemovesOnlyTheReviewedGroupAndRollsBackAWholeMultiPageErase() = fixture { names ->
        HealthRecordStore(context, names.records).use { store ->
            val group = (0..32).map { save(store, "erase-target", now - 300_000L - it * 1000L) }
            val original = group.first()
            val edited = (store.save(original.editable().copy(note = "revision")) as HealthSaveResult.Saved).record
            store.saveDraft(edited.editable().copy(note = "edit draft"))
            assertTrue(store.delete(group.last().id, group.last().revision))
            val other = save(store, "same-name-other-device", now - 200_000)
            val manual = (store.save(HealthDraft(values = mapOf("systolic" to "122", "diastolic" to "82"),
                measuredAt = now - 100_000)) as HealthSaveResult.Saved).record
            val stale = store.bluetoothHistoryPreview(edited.bluetoothGroup)
            assertEquals(33L, stale.count)
            val inserted = save(store, "erase-target", now - 50_000)
            assertTrue(runCatching { store.eraseBluetoothHistory(stale) }.exceptionOrNull() is HealthBluetoothHistoryChanged)
            val fresh = store.bluetoothHistoryPreview(edited.bluetoothGroup)
            assertEquals(34L, fresh.count)
            assertEquals(inserted.draft.measuredAt, fresh.last)
            var checkpoints = 0
            assertTrue(runCatching {
                store.eraseBluetoothHistory(fresh) { if (++checkpoints == 2) throw CancellationException() }
            }.exceptionOrNull() is CancellationException)
            assertEquals(fresh, store.bluetoothHistoryPreview(edited.bluetoothGroup))
            assertNotNull(store.draft("edit:${edited.id}"))
            assertNotNull(store.revision(original.id, original.revision))

            val lastReceipt = store.lastBluetoothReceipt()
            assertEquals(34L, store.eraseBluetoothHistory(fresh))
            assertEquals(0L, store.bluetoothHistoryPreview(edited.bluetoothGroup).count)
            assertNotEquals(fresh.version, store.metricVersion(HealthMetric.BLOOD_PRESSURE))
            (group + inserted).forEach { record ->
                assertNull(store.record(record.id))
                assertTrue(store.history(record.id).isEmpty())
            }
            assertNull(store.draft("edit:${edited.id}"))
            store.saveDraft(edited.editable().copy(note = "late editor callback"))
            assertNull(store.draft("edit:${edited.id}"))
            assertEquals(HealthSaveResult.Conflict, store.save(edited.editable().copy(note = "late edit")))
            assertEquals(other, store.record(other.id))
            assertEquals(manual, store.record(manual.id))
            assertEquals(lastReceipt, store.lastBluetoothReceipt())
            store.tableDatabase.rawQuery("PRAGMA foreign_key_check", null).use { assertFalse(it.moveToFirst()) }
        }
    }

    @Test fun inventoryDeletionPreviewsScopeHonorsCancelAndRequiresNewConfirmationAfterChanges() = fixture { names ->
        assumeFalse("Deletion dialog verification requires an unlocked Android 10+ display",
            Build.VERSION.SDK_INT < 29 || context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val (selected, other) = HealthRecordStore(context, names.records).use {
            save(it, "delete-ui-target", now - 120_000) to save(it, "delete-ui-other", now - 60_000)
        }
        val tag = "health-sources-device-${selected.bluetoothGroup}"
        val intent = Intent(context, HealthSourcesActivity::class.java).putExtra("health_sources_test_id", names.fixture)
        ActivityScenario.launch<HealthSourcesActivity>(intent).use { scenario ->
            awaitSource(scenario, "health-sources-inventory-toggle")
            scenario.onActivity { assertTrue(it.window.decorView.findViewWithTag<View>("health-sources-inventory-toggle").performClick()) }
            awaitSource(scenario, tag)
            val monitor = instrumentation.addMonitor(HealthTrendRecordsActivity::class.java.name, null, false)
            try {
                scenario.onActivity { assertTrue(it.window.decorView.findViewWithTag<View>(tag).performClick()) }
                val child = requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 12_000) as? HealthTrendRecordsActivity)
                try {
                    openPreview(child)
                    checkPreview(child, selected, 1)
                    button(android.R.id.button2)
                    HealthRecordStore(context, names.records).use { assertNotNull(it.record(selected.id)) }
                    openPreview(child)
                    checkPreview(child, selected, 1)
                    val newRow = HealthRecordStore(context, names.records).use { save(it, "delete-ui-target", now - 30_000) }
                    button(android.R.id.button1)
                    waitFor("new measurement after stale preview") { onMain {
                        child.window.decorView.findViewWithTag<View>("health-trend-record-${newRow.id}") != null
                    } }
                    openPreview(child)
                    checkPreview(child, selected, 2, newRow)
                    button(android.R.id.button1)
                    awaitSource(scenario, "health-sources-device-${other.bluetoothGroup}")
                    scenario.onActivity { assertNull(it.window.decorView.findViewWithTag<View>(tag)) }
                } finally { onMain { if (!child.isFinishing) child.finish() } }
            } finally { instrumentation.removeMonitor(monitor) }
        }
        HealthRecordStore(context, names.records).use {
            assertTrue(it.history(selected.id).isEmpty())
            assertEquals(other, it.record(other.id))
        }
        HealthPrivacyStore(context, names.privacy).use { privacy ->
            val events = privacy.page().entries.filter { it.scope.purpose == HealthAccessPurpose.DELETE_BLUETOOTH_HISTORY }
            assertEquals(setOf(HealthAccessOutcome.COMPLETE, HealthAccessOutcome.FAILED), events.map { it.outcome }.toSet())
            assertEquals(2L, events.single { it.outcome == HealthAccessOutcome.COMPLETE }.scope.count)
        }
    }

    private fun checkPreview(activity: HealthTrendRecordsActivity, first: HealthObservation, count: Int, last: HealthObservation = first) {
        val spec = requireNotNull(activity.intent.healthTrendSpec())
        fun date(record: HealthObservation) = Instant.ofEpochMilli(record.draft.measuredAt).atZone(spec.zone).toLocalDate()
        val name = activity.healthBluetoothTrendLabel(first.bluetoothGroup, first.platformOrigin)
        val expected = activity.getString(R.string.health_sources_delete_preview, name, count, date(first), date(last))
        waitFor("scoped deletion preview") { onMain {
            WindowInspector.getGlobalWindowViews().any { it.findViewById<TextView>(android.R.id.message)?.text?.toString() == expected }
        } }
    }
    private fun openPreview(activity: HealthTrendRecordsActivity) = waitFor("device deletion action") { onMain {
        activity.hasWindowFocus() && activity.window.decorView.findViewWithTag<View>("health-bluetooth-delete-history")?.performClick() == true
    } }
    private fun button(id: Int) = waitFor("confirmation button") { onMain {
        WindowInspector.getGlobalWindowViews().mapNotNull { it.findViewById<View>(id) }.lastOrNull()?.performClick() == true
    } }
    private fun awaitSource(scenario: ActivityScenario<HealthSourcesActivity>, tag: String) = waitFor(tag) {
        var found = false
        scenario.onActivity { found = it.window.decorView.findViewWithTag<View>(tag) != null }
        found
    }
    private fun <T> onMain(block: () -> T): T {
        var value: Result<T>? = null
        instrumentation.runOnMainSync { value = runCatching(block) }
        return requireNotNull(value).getOrThrow()
    }
    private fun waitFor(label: String, ready: () -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 12_000
        do {
            if (ready()) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < end)
        fail("Missing $label")
    }
    private fun save(store: HealthRecordStore, device: String, time: Long) =
        (store.saveBluetooth(healthTrendPressure(device, time), "unspecified") {} as HealthSaveResult.Saved).record
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
}
