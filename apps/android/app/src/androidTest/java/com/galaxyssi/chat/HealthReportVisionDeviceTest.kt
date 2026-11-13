package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Assume.assumeTrue
import org.junit.Test

class HealthReportVisionDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val model = HealthReportVisionTarget("fixture", "Synthetic Desktop", AgentTargetConfiguration("fixture-vision"),
        "fixture-desktop", "fixture-route", "fixture-binding")
    private val parsed = HealthReportVisionResult(listOf(
        HealthVisionRow(HealthMetric.CRP, mapOf("crp" to "<0.50"), "mg/L", "0-5", "CRP <0.50 mg/L 0-5"),
        HealthVisionRow(HealthMetric.HBA1C, mapOf("hba1c" to "5.40"), "%", "", "HbA1c 5.40 %")),
        "2026-01-12 08:30+08:00", true)

    private fun isolated(failed: Boolean = false, block: (HealthOverviewDatabases, HealthOriginalStore, HealthImportJob) -> Unit) {
        val id = UUID.randomUUID().toString()
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { store ->
            store.createJob(HealthImportJob(id, "content://fixture/report", System.currentTimeMillis()))
            val bytes = ByteArrayOutputStream()
            val bitmap = Bitmap.createBitmap(960, 600, Bitmap.Config.ARGB_8888)
            try {
                Canvas(bitmap).apply {
                    drawColor(Color.WHITE)
                    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; textSize = 34f }
                    listOf("SYNTHETIC REPORT", "Collected at: 2026-01-12 08:30+08:00", "CRP <0.50 mg/L 0-5", "HbA1c 5.40 %")
                        .forEachIndexed { i, line -> drawText(line, 40f, 90f + i * 85f, paint) }
                }
                assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes))
            } finally { bitmap.recycle() }
            val original = store.importOriginal(id, bytes.toByteArray().inputStream(), "synthetic.png", "image/png", "file")
            if (!failed) store.savePage(id, HealthOcrPage(1, 960, 600, listOf(HealthOcrLine("Glucose: 5.4 mmol/L"))))
            val job = store.updateJob(id) {
                it.copy(originalId = original.id, mime = original.mime, pageCount = 1,
                    state = if (failed) HealthImportState.FAILED else HealthImportState.REVIEW)
            }!!
            block(names, store, job)
        } } finally { clearHealthOverviewFixture(context, names) }
    }

    private fun allow(names: HealthOverviewDatabases) = HealthPrivacyStore(context, names.privacy).use {
        it.change(HealthPrivacyOption.ONLINE_ANALYSIS, true, it.policy().version)
        assertFalse(it.policy().images)
    }

    private fun gateway(respond: suspend (ByteArray, () -> Unit) -> String) = object : HealthReportVisionGateway {
        override fun target(context: Context) = model
        override suspend fun read(context: Context, target: HealthReportVisionTarget, jpeg: ByteArray, validate: () -> Unit): String {
            assertEquals(model, target)
            validate()
            return respond(jpeg, validate)
        }
    }

    @Test fun failedLocalOcrCanBeRecoveredWithoutInventingConfirmedRecords() = isolated(failed = true) { names, store, job ->
        allow(names)
        lateinit var buffer: ByteArray
        val reader = HealthReportVisionReader(context, names, gateway { bytes, _ ->
            buffer = bytes
            assertEquals(0xff, bytes[0].toInt() and 255); assertEquals(0xd8, bytes[1].toInt() and 255)
            parsed.json().toString()
        })
        runBlocking { reader.read(reader.prepare(job.id), model) }
        assertTrue(buffer.all { it == 0.toByte() })
        val saved = store.job(job.id)!!
        assertTrue(saved.modelRecognized)
        assertEquals(HealthImportState.REVIEW, saved.state)
        val page = store.page(job.id, 1)!!
        assertEquals(parsed, page.vision)
        val drafts = page.vision!!.drafts(saved, store.original(job.originalId)!!, ZoneId.of("UTC"), System.currentTimeMillis())
        HealthRecordStore(context, names.records).use {
            val rows = it.prepareOcrReviewPage(drafts)
            assertEquals(2, rows.size); assertTrue(rows.all { row -> row.selection == null })
            assertEquals(0L, it.count())
        }
        HealthPrivacyStore(context, names.privacy).use {
            assertEquals(HealthAccessOutcome.COMPLETE, it.page().entries.single().outcome)
            assertEquals(HealthAccessPurpose.HEALTH_REPORT_VISION, it.page().entries.single().scope.purpose)
        }
    }

    @Test fun onlineAnalysisRevocationDoesNotStoreModelResults() = isolated { names, store, job ->
        var calls = 0
        val reader = HealthReportVisionReader(context, names, gateway { _, _ ->
            calls++
            HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.ONLINE_ANALYSIS, false, it.policy().version) }
            parsed.json().toString()
        })
        assertThrows(HealthAccessBlocked::class.java) { reader.prepare(job.id) }
        assertEquals(0, calls)
        allow(names)
        assertThrows(HealthAccessBlocked::class.java) { runBlocking { reader.read(reader.prepare(job.id), model) } }
        assertEquals(1, calls)
        assertNull(store.page(job.id, 1)!!.vision); assertEquals(job, store.job(job.id))
        HealthPrivacyStore(context, names.privacy).use { assertEquals(HealthAccessOutcome.BLOCKED, it.page().entries.single().outcome) }
    }

    @Test fun badResponseLeavesLocalOcrAndImageUntouched() = isolated { names, store, job ->
        allow(names)
        val before = store.page(job.id, 1)
        val reader = HealthReportVisionReader(context, names, gateway { _, _ -> """{"rows":[],"collected":"","partial":true}""" })
        assertThrows(HealthAnalysisInvalidReply::class.java) { runBlocking { reader.read(reader.prepare(job.id), model) } }
        assertEquals(before, store.page(job.id, 1))
        assertTrue(store.present(store.original(job.originalId)!!))
    }

    @Test fun sourceRemovalDuringResponseCannotCreateDrafts() = isolated { names, store, job ->
        allow(names)
        val reader = HealthReportVisionReader(context, names, gateway { _, _ ->
            assertTrue(store.removeOriginalBytes(store.original(job.originalId)!!))
            parsed.json().toString()
        })
        assertThrows(HealthReportVisionChanged::class.java) { runBlocking { reader.read(reader.prepare(job.id), model) } }
        assertNull(store.page(job.id, 1)!!.vision)
        HealthRecordStore(context, names.records).use { assertEquals(0L, it.count()) }
    }

    @Test fun pairedCodexReadsOnlySyntheticReport() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("health_vision_live") == "true")
        val target = HealthReportVisionProvider.target(context) ?: error("Paired Codex is unavailable")
        isolated(failed = true) { names, store, job ->
            allow(names)
            val reader = HealthReportVisionReader(context, names)
            runBlocking { reader.read(reader.prepare(job.id), target) }
            val rows = checkNotNull(store.page(job.id, 1)?.vision).rows.associateBy { it.metric }
            assertEquals(setOf(HealthMetric.CRP, HealthMetric.HBA1C), rows.keys)
            val crp = rows.getValue(HealthMetric.CRP)
            assertEquals("<0.5", HealthResult.parse(crp.values.getValue("crp"), crp.metric.form)?.canonical)
            assertEquals("mg/L", crp.unit)
            val hba1c = rows.getValue(HealthMetric.HBA1C)
            assertEquals("5.4", HealthResult.parse(hba1c.values.getValue("hba1c"), hba1c.metric.form)?.canonical)
            assertEquals("%", hba1c.unit)
            val importer = HealthReportQuickImport(context, names)
            val plan = importer.prepare(job.id)
            assertFalse(plan.needsSupplement)
            assertEquals(2, importer.save(job.id, plan, HealthReportSupplement()) {}.saved)
            HealthRecordStore(context, names.records).use { assertEquals(2L, it.count()) }
            println("HEALTH_VISION_LIVE destination=${target.destination} saved=2")
        }
    }

    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun await(scenario: ActivityScenario<HealthCaptureActivity>, ready: (HealthCaptureActivity) -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 20_000L
        do { var done = false; scenario.onActivity { done = ready(it) }; if (done) return; SystemClock.sleep(50) }
        while (SystemClock.elapsedRealtime() < end)
        fail("Report vision review did not reach the expected state")
    }
    private fun field(instance: Any, name: String): Any? = instance.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(instance)
    private fun owner(activity: HealthCaptureActivity) = (field(activity, "visionUi\$delegate") as Lazy<*>).value as HealthReportVisionUi
    private fun dialog(activity: HealthCaptureActivity) = field(owner(activity), "dialog") as? AlertDialog

    @Test fun consentPrecedesSendingAndValidRowsSaveWithoutItemConfirmation() = isolated { names, store, job ->
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        allow(names)
        val sent = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val intent = Intent(context, HealthCaptureActivity::class.java).putExtra("health_job", job.id).putHealthNavigationFixture(names)
        var worker: ExecutorService? = null
        try {
            ActivityScenario.launch<HealthCaptureActivity>(intent).use { scenario ->
                scenario.onActivity {
                    worker = field(it, "worker") as ExecutorService
                    owner(it).useFixtureGateway(gateway { _, _ -> sent.complete(Unit); release.await(); parsed.json().toString() })
                }
                fun selectModel() {
                    await(scenario) { it.window.decorView.findViewWithTag<View>("health-vision-recognize") != null }
                    scenario.onActivity { it.window.decorView.findViewWithTag<View>("health-vision-recognize")!!.performClick() }
                    await(scenario) { dialog(it)?.getButton(AlertDialog.BUTTON_POSITIVE) != null }
                }
                selectModel()
                assertFalse(sent.isCompleted)
                scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_NEGATIVE).performClick() }
                assertFalse(sent.isCompleted); assertNull(store.page(job.id, 1)!!.vision)
                selectModel()
                scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
                await(scenario) { sent.isCompleted }
                release.complete(Unit)
                await(scenario) { activity -> views(activity.window.decorView).filterIsInstance<TextView>()
                    .any { it.text.toString() == "<0.50" } }
                await(scenario) { it.window.decorView.findViewWithTag<View>("health-report-save-all") == null }
                assertEquals(parsed, store.page(job.id, 1)!!.vision)
                assertEquals(listOf(HealthOcrLine("Glucose: 5.4 mmol/L")), store.page(job.id, 1)!!.lines)
                HealthRecordStore(context, names.records).use { assertEquals(2L, it.count()) }
                if (InstrumentationRegistry.getArguments().getString("health_vision_screenshot") == "true") {
                    instrumentation.waitForIdleSync(); SystemClock.sleep(300)
                    instrumentation.uiAutomation.takeScreenshot()?.let { bitmap -> try {
                        File(context.getExternalFilesDir(null), "health-vision-report-fixture.png").outputStream().use {
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                        }
                    } finally { bitmap.recycle() } }
                }
                scenario.moveToState(Lifecycle.State.CREATED)
                scenario.onActivity { assertNull(dialog(it)) }
                scenario.moveToState(Lifecycle.State.RESUMED)
                await(scenario) { activity -> views(activity.window.decorView).filterIsInstance<TextView>()
                    .any { it.text.toString() == "<0.50" } }
            }
        } finally { worker?.let { assertTrue(it.awaitTermination(20, TimeUnit.SECONDS)) } }
    }

    @Test fun sharedSupplementSavesAllValidRowsAndKeepsUncertainRowsAsDrafts() = isolated { names, store, job ->
        val result = parsed.copy(collected = "", partial = true, rows = parsed.rows + listOf(
            HealthVisionRow(HealthMetric.GLUCOSE, mapOf("glucose" to "5.1"), "mmol/L", "", "Glucose 5.1 mmol/L"),
            HealthVisionRow(HealthMetric.ALT, mapOf("alt" to "20"), "", "", "ALT 20")))
        store.saveReportVision(job, store.original(job.originalId)!!, result)
        val importer = HealthReportQuickImport(context, names)
        val plan = importer.prepare(job.id)
        assertTrue(plan.needsDate); assertTrue(plan.needsFasting)
        val time = java.time.Instant.parse("2026-01-12T00:30:00Z").toEpochMilli()
        val supplement = HealthReportSupplement(time, "non_fasting")
        assertThrows(java.util.concurrent.CancellationException::class.java) {
            var checks = 0
            importer.save(job.id, plan, supplement) { if (++checks == 2) throw java.util.concurrent.CancellationException() }
        }
        HealthRecordStore(context, names.records).use { assertEquals(0L, it.count()) }
        val outcome = importer.save(job.id, plan, supplement) {}
        assertEquals(HealthReportImportOutcome(3, 0, 1, true), outcome)
        HealthRecordStore(context, names.records).use { records ->
            val items = plan.fill(supplement)
            val glucose = records.recordForEvidence(items.single { it.metric == HealthMetric.GLUCOSE })!!
            assertEquals("non_fasting", glucose.draft.condition)
            assertEquals(time, glucose.draft.measuredAt)
            assertEquals("unspecified", records.recordForEvidence(items.first())!!.draft.condition)
            assertEquals(3L, records.count())
        }
        assertEquals(0, importer.save(job.id, importer.prepare(job.id), HealthReportSupplement()) {}.saved)
    }

    @Test fun dateOnlyAndPrintedFastingNeedOnlyOneTimeAndDuplicateRowsAreNotOverwritten() = isolated { names, store, job ->
        val glucose = HealthVisionRow(HealthMetric.GLUCOSE, mapOf("glucose" to "5.10"), "mmol/L", "", "Fasting glucose 5.10 mmol/L")
        val result = parsed.copy(collected = "2026-01-12", fasting = "fasting",
            rows = listOf(glucose, glucose.copy(values = mapOf("glucose" to "5.1"), source = "Fasting glucose 5.1 mmol/L")))
        val source = store.original(job.originalId)!!
        store.saveReportVision(job, source, result)
        val importer = HealthReportQuickImport(context, names)
        val plan = importer.prepare(job.id)
        assertEquals("2026-01-12", plan.collectedDate)
        assertTrue(plan.needsDate); assertFalse(plan.needsFasting)
        val time = java.time.Instant.parse("2026-01-12T00:30:00Z").toEpochMilli()
        val outcome = importer.save(job.id, plan, HealthReportSupplement(time)) {}
        assertEquals(1, outcome.saved); assertEquals(1, outcome.duplicates)
        HealthRecordStore(context, names.records).use { records ->
            assertEquals(1L, records.count())
            val saved = records.recordForEvidence(plan.drafts.first())!!
            assertEquals("fasting", saved.draft.condition)
            assertEquals("5.10", saved.draft.reportedValues.getValue("glucose"))
            assertEquals(1, saved.revision)
        }
        assertTrue(importer.prepare(job.id).drafts.isEmpty())
    }

    @Test fun missingFastingShowsOneSharedFormAndDoesNotSaveOnCancel() = isolated { names, store, job ->
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val report = parsed.copy(rows = parsed.rows + HealthVisionRow(HealthMetric.GLUCOSE,
            mapOf("glucose" to "5.10"), "mmol/L", "", "Glucose 5.10 mmol/L"))
        store.saveReportVision(job, store.original(job.originalId)!!, report)
        val intent = Intent(context, HealthCaptureActivity::class.java).putExtra("health_job", job.id).putHealthNavigationFixture(names)
        var worker: ExecutorService? = null
        try {
            ActivityScenario.launch<HealthCaptureActivity>(intent).use { scenario ->
                scenario.onActivity { worker = field(it, "worker") as ExecutorService }
                fun supplement(activity: HealthCaptureActivity) =
                    field(field(owner(activity), "supplementUi")!!, "dialog") as? AlertDialog
                fun openForm() {
                    await(scenario) { it.window.decorView.findViewWithTag<View>("health-report-save-all") != null }
                    scenario.onActivity { it.window.decorView.findViewWithTag<View>("health-report-save-all")!!.performClick() }
                    await(scenario) { supplement(it)?.getButton(AlertDialog.BUTTON_POSITIVE) != null }
                }
                openForm()
                scenario.onActivity {
                    val form = supplement(it)!!
                    assertNull(form.window!!.decorView.findViewWithTag<View>("health-report-pick-time"))
                    assertFalse(form.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled)
                    form.getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
                }
                HealthRecordStore(context, names.records).use { assertEquals(0L, it.count()) }
                openForm()
                scenario.onActivity {
                    val form = supplement(it)!!
                    form.window!!.decorView.findViewWithTag<View>("health-report-unspecified")!!.performClick()
                    assertTrue(form.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled)
                    form.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
                }
                await(scenario) { it.window.decorView.findViewWithTag<View>("health-report-save-all") == null }
                HealthRecordStore(context, names.records).use { assertEquals(3L, it.count()) }
            }
        } finally { worker?.let { assertTrue(it.awaitTermination(20, TimeUnit.SECONDS)) } }
    }
}
