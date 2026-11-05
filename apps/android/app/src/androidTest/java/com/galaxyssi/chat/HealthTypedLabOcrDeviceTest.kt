package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthTypedLabOcrDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val measured = Instant.parse("2025-11-03T00:15:00Z").toEpochMilli()

    @Test fun verifiedReportBoundsRangesAndLabelsStayVisibleButOnlyExactValuesEnterTrends() {
        assumeFalse("Typed OCR review requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            val (job, drafts) = report(names)
            val ready = drafts.filter { it.unit.isNotBlank() || it.metric == HealthMetric.URINE_PROTEIN }
            val missingUnit = drafts.single { it.metric == HealthMetric.ALT }
            assertEquals(4, ready.size)
            HealthRecordStore(context, names.records).use { records ->
                ready.forEach { draft -> records.saveDraft(draft.copy(measuredAt = measured,
                    evidence = requireNotNull(draft.evidence).copy(confirmed = true))) }
            }
            val keys = ready.map(::pick)
            ActivityScenario.launch<HealthCaptureActivity>(Intent(context, HealthCaptureActivity::class.java)
                .putHealthNavigationFixture(names).putExtra("health_job", job)).use { review ->
                await("verified report rows") {
                    var ready = false
                    review.onActivity { activity -> ready = keys.all { activity.window.decorView.findViewWithTag<View>(it) != null } }
                    ready
                }
                HealthRecordStore(context, names.records).use { assertEquals(0L, it.count()) }
                review.onActivity { activity ->
                    val root = activity.window.decorView
                    val text = labels(root)
                    assertTrue("< 5.60" in text)
                    assertTrue("4.0\uff5e6.0" in text)
                    assertTrue("1+" in text)
                    assertTrue(text.any { it.startsWith(activity.getString(R.string.health_report_reference)) && it.endsWith("3.9-6.1") })
                    assertNull(root.findViewWithTag<View>(pick(missingUnit)))
                    keys.forEach { assertTrue(root.findViewWithTag<CheckBox>(it).performClick()) }
                    val save = root.findViewWithTag<View>("health-review-batch-save")
                    assertFalse(save.isEnabled)
                    root.findViewWithTag<CheckBox>("health-review-batch-consent").isChecked = true
                    assertTrue(save.performClick())
                }
                await("confirmed typed batch") { HealthRecordStore(context, names.records).use { it.count() == 4L } }
            }
            val saved = HealthRecordStore(context, names.records).use { records ->
                assertNotNull(records.draft(HealthRecordStore.draftKey(missingUnit)))
                val day = LocalDate.of(2025, 11, 3)
                val spec = HealthTrendSpec(HealthMetric.GLUCOSE, day, day, ZoneOffset.UTC, "mmol/L")
                assertEquals(3, records.trendRecords(spec).records.size)
                val exact = records.trendRecords(spec, numericOnly = true).records.single()
                assertEquals("5.7", exact.draft.values["glucose"])
                records.page().records
            }
            val expected = mapOf(
                "< 5.60" to HealthResultKind.COMPARISON,
                "4.0\uff5e6.0" to HealthResultKind.RANGE,
                "1+" to HealthResultKind.QUALITATIVE,
                "5.7" to HealthResultKind.NUMBER,
            )
            saved.forEach {
                val raw = it.draft.values.values.single()
                assertEquals(expected.getValue(raw), HealthResult.parse(raw, it.draft.metric.form)?.kind)
                assertTrue(it.draft.evidence?.confirmed == true)
            }
            val bounded = saved.single { it.draft.values["glucose"] == "< 5.60" }
            assertEquals("3.9-6.1", bounded.draft.reference)
            assertTrue(bounded.draft.evidence!!.rawText.contains("Reference range: 3.9-6.1"))
            ActivityScenario.launch<HealthCatalogActivity>(Intent(context, HealthCatalogActivity::class.java)
                .putHealthNavigationFixture(names)).use { catalog ->
                catalog.onActivity { assertTrue(it.window.decorView.findViewWithTag<View>("health-catalog-mode-2").performClick()) }
                await("typed results in native catalog") {
                    var ready = false
                    catalog.onActivity { activity ->
                        val root = activity.window.decorView
                        ready = saved.all { record -> root.findViewWithTag<View>("health-catalog-record-${record.id}")?.let {
                            labels(it).any { label -> label.substringBefore('\n') == healthDisplayValue(record.draft) }
                        } == true }
                    }
                    ready
                }
            }
        } finally { clearHealthOverviewFixture(context, names) }
    }

    private fun report(names: HealthOverviewDatabases): Pair<String, List<HealthDraft>> {
        val id = UUID.randomUUID().toString()
        return HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            originals.createJob(HealthImportJob(id, "content://fixture/typed-lab", System.currentTimeMillis()))
            val original = originals.importOriginal(id, "synthetic report".byteInputStream(), "typed.pdf", "application/pdf", "file")
            val text = listOf("Glucose: < 5.60 mmol/L; Reference range: 3.9-6.1", "Glucose: 4.0\uff5e6.0 mmol/L",
                "Glucose: 5.7 mmol/L", "Urine protein: 1+", "ALT: <40")
            val page = HealthOcrPage(1, 100, 100,
                text.mapIndexed { index, line -> HealthOcrLine(line, listOf(0, index * 14, 95, index * 14 + 12)) },
                recognition = HealthRecognition.PDF_TEXT)
            originals.savePage(id, page)
            val job = requireNotNull(originals.updateJob(id) { it.copy(state = HealthImportState.REVIEW, originalId = original.id) })
            id to HealthOcrCandidates.suggest(job, original, page)
        }
    }
    private fun pick(draft: HealthDraft) = "health-review-pick-${requireNotNull(draft.evidence).candidateId}"
    private fun labels(view: View): List<String> = when (view) {
        is TextView -> listOf(view.text.toString())
        is ViewGroup -> (0 until view.childCount).flatMap { labels(view.getChildAt(it)) }
        else -> emptyList()
    }
    private fun await(label: String, condition: () -> Boolean) {
        val until = SystemClock.elapsedRealtime() + 12_000
        do { if (condition()) return; SystemClock.sleep(50) } while (SystemClock.elapsedRealtime() < until)
        fail("Missing $label")
    }
}
