package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.inspector.WindowInspector
import android.widget.CheckBox
import android.widget.ScrollView
import android.widget.TextView
import android.widget.TimePicker
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import androidx.work.WorkInfo
import androidx.work.WorkManager
import java.io.File
import java.time.Instant
import java.util.UUID
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Assume.assumeTrue
import org.junit.Test

class HealthTableDateOnlyDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val firstTime = Instant.parse("2024-02-29T00:15:00Z").toEpochMilli()
    private val fullTime = Instant.parse("2024-02-29T03:30:00Z").toEpochMilli()

    @Test fun csvNativePickerAndValidationSaveOnlyConfirmedRowsAndUndoOnlyTheBatch() = fixture { names ->
        assumeTrue(Build.VERSION.SDK_INT >= 29)
        assumeFalse("Visible table review needs an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val csv = listOf(
            "date,systolic,diastolic,unit",
            "2024-02-29,124,82,mmHg",
            "2024-02-29,124,82,mmHg",
            "2024-02-29T11:30:00+08:00,122,80,mmHg",
            "2024-02-30,126,84,mmHg",
            "2024-02-28,,80,mmHg",
        ).joinToString("\n")
        val batch = stage(names, "Synthetic blood pressure.csv", "text/csv", csv)
        val unrelated = HealthRecordStore(context, names.records).use {
            (it.save(HealthDraft(values = mapOf("systolic" to "126", "diastolic" to "83"), measuredAt = fullTime + 60_000)) as HealthSaveResult.Saved).record
        }
        HealthTableStore(context, names.records).use {
            it.mapping(batch.id, batch.mappingRevision, batch.mapping.copy(zone = "Asia/Shanghai"), false)
        }
        val intent = Intent(context, HealthTableActivity::class.java).putExtra("health_table", batch.id).putHealthNavigationFixture(names)
        ActivityScenario.launch<HealthTableActivity>(intent).use { scenario ->
            click(scenario, "health-table-validate")
            val first = awaitState(names, batch.id, HealthTableState.READY)
            awaitWork(names, first, HealthTableState.VALIDATING)
            assertCounts(scenario, 1, 0, 3, 1)
            assertRowLabel(scenario, 1, R.string.health_table_date_only_pending)
            assertRows(names, batch.id, listOf(HealthTableRowState.MISSING, HealthTableRowState.MISSING,
                HealthTableRowState.VALID, HealthTableRowState.INVALID, HealthTableRowState.MISSING))
            click(scenario, "health-table-row-1")
            awaitDialogText(context.getString(R.string.health_table_date_only_missing))
            dialogButton(android.R.id.button2)
            click(scenario, "health-table-date-only-time")
            withDialog { views ->
                val picker = views.filterIsInstance<TimePicker>().singleOrNull() ?: return@withDialog false
                picker.hour = 8
                picker.minute = 15
                views.singleOrNull { it.id == android.R.id.button1 }?.performClick() == true
            }
            val mapped = awaitState(names, batch.id, HealthTableState.MAPPING)
            assertEquals("08:15", mapped.mapping.dateOnlyTime)
            scenario.recreate()
            awaitTag(scenario, "health-table-date-only-time") { view ->
                views(view).filterIsInstance<TextView>().any { it.text == "08:15" }
            }
            click(scenario, "health-table-validate")
            val validated = awaitState(names, batch.id, HealthTableState.READY)
            awaitWork(names, validated, HealthTableState.VALIDATING)
            assertCounts(scenario, 2, 1, 1, 1)
            assertRowLabel(scenario, 1, R.string.health_table_date_only_preview)
            assertRows(names, batch.id, listOf(HealthTableRowState.VALID, HealthTableRowState.DUPLICATE,
                HealthTableRowState.VALID, HealthTableRowState.INVALID, HealthTableRowState.MISSING))
            click(scenario, "health-table-row-1")
            awaitDialogText(context.getString(R.string.health_table_date_only_applied, "08:15"))
            dialogButton(android.R.id.button2)
            capturePreview(scenario)
            click(scenario, "health-table-save")
            assertEquals(HealthTableState.READY, current(names, batch.id).state)
            HealthRecordStore(context, names.records).use { assertEquals(1L, it.count()) }
            awaitTag(scenario, "health-table-confirm-source") {
                val check = it as CheckBox
                assertFalse(check.isChecked)
                check.performClick()
                check.isChecked
            }
            click(scenario, "health-table-save")
            val saved = awaitState(names, batch.id, HealthTableState.SAVED)
            awaitWork(names, saved, HealthTableState.SAVING)
            HealthRecordStore(context, names.records).use { records ->
                val imported = records.originalPage(batch.originalId).records
                assertEquals(listOf(fullTime, firstTime), imported.map { it.draft.measuredAt })
                assertEquals(listOf(3L, 1L), imported.map { it.draft.evidence!!.tableRow })
                assertTrue(imported.last().draft.evidence!!.rawText.contains("date: 2024-02-29\n"))
                assertTrue(imported.last().draft.evidence!!.rawText.contains("Confirmed date-only time: 08:15"))
                assertFalse(imported.first().draft.evidence!!.rawText.contains("Confirmed date-only time"))
                assertEquals(3L, records.count())
            }
            HealthTableStore(context, names.records).use {
                assertFalse(it.step(batch.id, HealthTableState.SAVING, saved.mappingRevision))
            }
            click(scenario, "health-table-undo")
            dialogButton(android.R.id.button2)
            assertEquals(HealthTableState.SAVED, current(names, batch.id).state)
            click(scenario, "health-table-undo")
            dialogButton(android.R.id.button1)
            val undone = awaitState(names, batch.id, HealthTableState.UNDONE)
            awaitWork(names, undone, HealthTableState.UNDOING)
            HealthRecordStore(context, names.records).use {
                assertTrue(it.originalPage(batch.originalId).records.isEmpty())
                assertEquals(1L, it.count())
                assertEquals(unrelated, it.record(unrelated.id))
            }
        }
    }

    @Test fun jsonKeepsTypedLabResultsAndReferenceWhenDateOnlyTimeIsConfirmed() = fixture { names ->
        val batch = stage(names, "Synthetic lab.json", "application/json", """
            [{"date":"2024-02-29","creatinine":"<1.2","unit":"mg/dL","reference":"0.6-1.2"},
             {"date":"2024-02-29","creatinine":"0.9-1.1","unit":"mg/dL","reference":"0.6-1.2"}]
        """.trimIndent())
        val mapping = HealthTablePolicy.suggest(batch.headers, HealthMetric.CREATININE).copy(zone = "Asia/Shanghai", dateOnlyTime = "08:15")
        HealthTableStore(context, names.records).use {
            it.mapping(batch.id, batch.mappingRevision, mapping, true)
            while (it.step(batch.id)) Unit
            val ready = requireNotNull(it.batch(batch.id))
            assertEquals(2L, it.counts(batch.id)[HealthTableRowState.VALID])
            it.confirmSave(batch.id, ready.mappingRevision)
            while (it.step(batch.id)) Unit
            assertEquals(2L, it.counts(batch.id)[HealthTableRowState.SAVED])
        }
        HealthRecordStore(context, names.records).use { records ->
            val rows = records.originalPage(batch.originalId).records.sortedBy { it.draft.evidence!!.tableRow }
            assertEquals(listOf(firstTime, firstTime), rows.map { it.draft.measuredAt })
            assertEquals(listOf(HealthResultKind.COMPARISON, HealthResultKind.RANGE), rows.map {
                HealthResult.parse(it.draft.values.getValue("creatinine"), it.draft.metric.form)!!.kind
            })
            assertTrue(rows.all { it.draft.reference == "0.6-1.2" && it.draft.evidence!!.rawText.contains("Confirmed date-only time: 08:15") })
        }
    }

    private fun stage(names: HealthOverviewDatabases, name: String, mime: String, contents: String): HealthTableBatch =
        HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            val id = UUID.randomUUID().toString()
            val file = originals.importOriginal(id, contents.byteInputStream(), name, mime, "file")
            HealthTableStore(context, names.records).use { HealthTableImport.stage(originals, file, id, it) }
        }
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun current(names: HealthOverviewDatabases, id: String) =
        HealthTableStore(context, names.records).use { requireNotNull(it.batch(id)) }
    private fun awaitState(names: HealthOverviewDatabases, id: String, state: HealthTableState): HealthTableBatch {
        var last = current(names, id)
        await("batch state $state") { last = current(names, id); last.state == state }
        return last
    }
    private fun awaitWork(names: HealthOverviewDatabases, batch: HealthTableBatch, phase: HealthTableState) {
        val key = HealthTableScheduler.workName(names, batch.id, phase, batch.mappingRevision)
        await("finished $phase worker") {
            WorkManager.getInstance(context).getWorkInfosForUniqueWork(key).get(4, TimeUnit.SECONDS)
                .any { it.state == WorkInfo.State.SUCCEEDED }
        }
    }
    private fun assertRows(names: HealthOverviewDatabases, id: String, states: List<HealthTableRowState>) =
        HealthTableStore(context, names.records).use { assertEquals(states, it.page(id).map { row -> row.state }) }
    private fun assertCounts(scenario: ActivityScenario<HealthTableActivity>, valid: Int, duplicate: Int, missing: Int, invalid: Int) =
        awaitTag(scenario, "health-table-counts") {
            (it as TextView).text == context.getString(R.string.health_table_counts, valid, duplicate, missing, invalid)
        }
    private fun assertRowLabel(scenario: ActivityScenario<HealthTableActivity>, row: Int, label: Int) =
        awaitTag(scenario, "health-table-row-$row") { view ->
            views(view).filterIsInstance<TextView>().any { it.text == context.getString(label) }
        }
    private fun click(scenario: ActivityScenario<HealthTableActivity>, tag: String) = awaitTag(scenario, tag, View::performClick)
    private fun awaitTag(scenario: ActivityScenario<HealthTableActivity>, tag: String, accepts: (View) -> Boolean) = await(tag) {
        var result = false
        scenario.onActivity { result = it.window.decorView.findViewWithTag<View>(tag)?.let(accepts) == true }
        result
    }
    private fun withDialog(test: (List<View>) -> Boolean) = await("native dialog") {
        var found = false
        instrumentation.runOnMainSync { found = test(WindowInspector.getGlobalWindowViews().flatMap(::views)) }
        found
    }
    private fun awaitDialogText(expected: String) = withDialog { list -> list.filterIsInstance<TextView>().any { it.text == expected } }
    private fun dialogButton(id: Int) = withDialog { list -> list.singleOrNull { it.id == id }?.performClick() == true }
    private fun views(root: View): List<View> = listOf(root) + if (root is ViewGroup)
        (0 until root.childCount).flatMap { views(root.getChildAt(it)) } else emptyList()
    private fun capturePreview(scenario: ActivityScenario<HealthTableActivity>) {
        if (InstrumentationRegistry.getArguments().getString("tableDateScreenshot") != "true") return
        scenario.onActivity { activity ->
            val scroll = views(activity.window.decorView).filterIsInstance<ScrollView>().single()
            val title = scroll.findViewWithTag<View>("health-table-preview")
            val rect = Rect().also(title::getDrawingRect)
            scroll.offsetDescendantRectToMyCoords(title, rect)
            scroll.scrollTo(0, rect.top)
        }
        instrumentation.waitForIdleSync()
        SystemClock.sleep(350)
        val image = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try {
            File(context.cacheDir, "health-table-date-only-preview.png").outputStream().use {
                check(image.compress(Bitmap.CompressFormat.PNG, 100, it))
            }
        } finally { image.recycle() }
    }
    private fun await(label: String, predicate: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 20_000
        do { if (predicate()) return; SystemClock.sleep(70) } while (SystemClock.elapsedRealtime() < until)
        fail("Missing $label")
    }
}
