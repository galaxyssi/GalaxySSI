package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.DatePicker
import android.widget.EditText
import android.widget.TimePicker
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.util.Calendar
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthMeasurementUndoDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val draft = HealthDraft(values = mapOf("systolic" to "124", "diastolic" to "82"),
        measuredAt = System.currentTimeMillis() - 172_800_000L)

    @Test fun staleDuplicateAndPermanentlyErasedMeasurementsCannotBeRestored() = fixture { names ->
        HealthRecordStore(context, names.records).use { store ->
            val record = (store.save(draft) as HealthSaveResult.Saved).record
            assertTrue(store.delete(record.id, record.revision))
            assertTrue(store.canUndoDelete(record.id, 2))
            assertFalse(store.undoDelete(record.id, 1))
            val duplicate = (store.save(draft) as HealthSaveResult.Saved).record
            assertFalse(store.undoDelete(record.id, 2))
            assertNull(store.record(record.id))
            assertEquals(duplicate, store.record(duplicate.id))
            val scope = HealthMeasurementHistoryScope(draft.metric, healthConnectOnly = false)
            assertEquals(2L, store.eraseMeasurementHistory(store.measurementHistoryPreview(scope)))
            assertFalse(store.canUndoDelete(record.id, 2))
            assertFalse(store.undoDelete(record.id, 2))
            assertTrue(store.history(record.id).isEmpty())
        }
    }

    @Test fun undoPreservesSecondaryEvidenceAndInvalidatesVersionPinnedResults() = fixture { names ->
        val evidence = HealthEvidence(id(), id(), "row-1", "a".repeat(64), 1, "124/82",
            confirmed = true, kind = "table", tableRow = 1)
        val record = HealthRecordStore(context, names.records).use { store ->
            val saved = (store.save(draft.copy(evidence = evidence.copy(originalId = id(), jobId = id()))) as HealthSaveResult.Saved).record
            val db = store.tableDatabase
            db.beginTransaction()
            try {
                assertTrue(store.linkDuplicateTableSource(draft.copy(evidence = evidence), saved.id))
                db.setTransactionSuccessful()
            } finally { db.endTransaction(); store.publishCommittedChanges() }
            assertTrue(store.delete(saved.id, saved.revision))
            assertTrue(store.originalPage(evidence.originalId).records.isEmpty())
            saved
        }
        HealthRecordStore(context, names.records).use { reopened ->
            val version = reopened.metricVersion(draft.metric)
            assertTrue(reopened.undoDelete(record.id, 2))
            assertNotEquals(version, reopened.metricVersion(draft.metric))
            val restored = requireNotNull(reopened.record(record.id))
            assertEquals(3, restored.revision)
            assertEquals(record.draft, restored.draft)
            assertEquals(record, reopened.revision(record.id, 1))
            assertNull(reopened.revision(record.id, 2))
            val link = reopened.originalPage(evidence.originalId).records.single()
            assertEquals(restored.id, link.id)
            assertEquals(restored.revision, link.revision)
            assertEquals(evidence, link.draft.evidence)
            assertFalse(reopened.undoDelete(record.id, 2))
            assertEquals(1L, reopened.count())
        }
    }

    @Test fun anOcrSourceClaimedByAnotherRecordRollsBackTheEntireUndo() = fixture { names ->
        val evidence = HealthEvidence(id(), id(), "candidate", "b".repeat(64), 1, "124/82", confirmed = true)
        HealthRecordStore(context, names.records).use { store ->
            val saved = (store.save(draft.copy(evidence = evidence.copy(originalId = id(), jobId = id()))) as HealthSaveResult.Saved).record
            val db = store.tableDatabase
            db.beginTransaction()
            try {
                store.insertRestoredSource(HealthRestoreSourceLink(saved.id, saved.revision, draft.metric, evidence))
                db.setTransactionSuccessful()
            } finally { db.endTransaction(); store.publishCommittedChanges() }
            assertTrue(store.delete(saved.id, saved.revision))
            val newRecord = (store.save(draft.copy(measuredAt = draft.measuredAt + 60_000, evidence = evidence)) as HealthSaveResult.Saved).record
            val version = store.metricVersion(draft.metric)
            assertFalse(store.undoDelete(saved.id, 2))
            assertEquals(version, store.metricVersion(draft.metric))
            assertTrue(store.canUndoDelete(saved.id, 2))
            assertNull(store.record(saved.id))
            assertEquals(listOf(2, 1), store.history(saved.id).map { it.revision })
            assertEquals(newRecord.id, store.originalPage(evidence.originalId).records.single().id)
        }
    }

    @Test fun nativeLateEntryEditDeleteCancelAndUndoSurviveRecreation() = fixture { names ->
        assumeFalse("Measurement undo UI requires an unlocked Android 10+ display",
            Build.VERSION.SDK_INT < 29 || context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val measured = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_MONTH, -2); set(Calendar.HOUR_OF_DAY, 9); set(Calendar.MINUTE, 15)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
        }
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java)
            .putHealthNavigationFixture(names)).use { scenario ->
            scenario.onActivity { it.open("manual") }
            awaitView(scenario, "health-save")
            scenario.onActivity {
                it.body.findViewWithTag<EditText>("health-field-systolic").setText("124")
                it.body.findViewWithTag<EditText>("health-field-diastolic").setText("82")
            }
            click(scenario, "health-measured-at")
            await("date picker") { onMain {
                globalViews().filterIsInstance<DatePicker>().lastOrNull()?.let {
                    it.updateDate(measured.get(Calendar.YEAR), measured.get(Calendar.MONTH), measured.get(Calendar.DAY_OF_MONTH))
                    true
                } ?: false
            } }
            clickDialog(android.R.id.button1)
            await("time picker") { onMain {
                globalViews().filterIsInstance<TimePicker>().lastOrNull()?.let {
                    it.hour = measured.get(Calendar.HOUR_OF_DAY); it.minute = measured.get(Calendar.MINUTE)
                    true
                } ?: false
            } }
            clickDialog(android.R.id.button1)
            click(scenario, "health-save")
            await("new measurement") { HealthRecordStore(context, names.records).use { it.count() == 1L } }
            val record = HealthRecordStore(context, names.records).use { it.page().records.single() }
            assertEquals(measured.timeInMillis, record.draft.measuredAt)
            await("editor closes after saving") {
                var closed = false
                scenario.onActivity { closed = it.editor == null }
                closed
            }
            scenario.onActivity { it.open("detail", record.draft.metric, record.id) }
            click(scenario, "health-edit-record")
            awaitView(scenario, "health-note")
            scenario.onActivity { it.body.findViewWithTag<EditText>("health-note").setText("Checked against the test monitor") }
            click(scenario, "health-save")
            click(scenario, "health-delete-record")
            clickDialog(android.R.id.button2)
            HealthRecordStore(context, names.records).use { assertEquals(2, it.record(record.id)?.revision) }
            click(scenario, "health-delete-record")
            clickDialog(android.R.id.button1)
            awaitView(scenario, "health-undo-record-delete")
            HealthRecordStore(context, names.records).use { assertNull(it.record(record.id)) }
            scenario.recreate()
            click(scenario, "health-undo-record-delete")
            awaitView(scenario, "health-edit-record")
            HealthRecordStore(context, names.records).use { store ->
                val restored = requireNotNull(store.record(record.id))
                assertEquals(4, restored.revision)
                assertEquals(record.draft.measuredAt, restored.draft.measuredAt)
                assertEquals(record.draft.values, restored.draft.values)
                assertEquals("Checked against the test monitor", restored.draft.note)
                assertEquals(listOf(4, 3, 2, 1), store.history(record.id).map { it.revision })
            }
        }
    }

    private fun id() = UUID.randomUUID().toString()
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(id())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun awaitView(scenario: ActivityScenario<HealthCenterActivity>, tag: String) = withView(scenario, tag) { true }
    private fun click(scenario: ActivityScenario<HealthCenterActivity>, tag: String) = withView(scenario, tag, View::performClick)
    private fun withView(scenario: ActivityScenario<HealthCenterActivity>, tag: String, action: (View) -> Boolean) = await(tag) {
        var ready = false
        scenario.onActivity { ready = it.body.findViewWithTag<View>(tag)?.let(action) == true }
        ready
    }
    private fun clickDialog(id: Int) = await("dialog button") { onMain {
        WindowInspector.getGlobalWindowViews().mapNotNull { it.findViewById<View>(id) }.lastOrNull()?.performClick() == true
    } }
    private fun globalViews() = WindowInspector.getGlobalWindowViews().asSequence().flatMap(::descendants)
    private fun descendants(view: View): Sequence<View> = sequence {
        yield(view)
        if (view is ViewGroup) for (index in 0 until view.childCount) yieldAll(descendants(view.getChildAt(index)))
    }
    private fun onMain(block: () -> Boolean): Boolean {
        var result = false
        instrumentation.runOnMainSync { result = block() }
        return result
    }
    private fun await(label: String, ready: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 12_000
        do {
            if (ready()) return
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Missing $label")
    }
}
