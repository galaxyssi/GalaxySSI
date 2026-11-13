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
    private val model = HealthAnalysisTarget("fixture", "Synthetic model", "fixture-vision", "https://example.invalid/read",
        "openai", "example.invalid", "example.invalid")
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
        it.change(HealthPrivacyOption.ORIGINAL_IMAGES, true, it.policy().version)
    }

    private fun gateway(respond: suspend (ByteArray, () -> Unit) -> String) = object : HealthReportVisionGateway {
        override fun targets(context: Context) = listOf(model)
        override suspend fun read(context: Context, target: HealthAnalysisTarget, jpeg: ByteArray, validate: () -> Unit): String {
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

    @Test fun disabledImageSharingAndRevocationDoNotStoreModelResults() = isolated { names, store, job ->
        var calls = 0
        val reader = HealthReportVisionReader(context, names, gateway { _, _ ->
            calls++
            HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.ORIGINAL_IMAGES, false, it.policy().version) }
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

    @Test fun configuredCloudModelReadsOnlySyntheticReport() {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue(args.getString("health_vision_live") == "true")
        val configured = HealthReportVisionProvider.targets(context)
        val chosen = args.getString("health_vision_target")
        if (chosen.isNullOrBlank()) {
            configured.forEachIndexed { index, target -> println("HEALTH_VISION_TARGET index=$index destination=${target.destination}") }
            println("HEALTH_VISION_TARGET count=${configured.size} probe_only=true")
            return
        }
        val target = configured.getOrNull(chosen.toInt()) ?: error("Requested synthetic test model is not configured")
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
            HealthRecordStore(context, names.records).use { assertEquals(0L, it.count()) }
            println("HEALTH_VISION_LIVE destination=${target.destination} two_drafts=true confirmed_records=0")
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

    @Test fun consentPrecedesSendingAndModelDraftsAppearWithoutSaving() = isolated { names, store, job ->
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
                    await(scenario) { dialog(it)?.listView != null }
                    scenario.onActivity {
                        val list = dialog(it)!!.listView
                        list.performItemClick(list.getChildAt(0), 0, list.adapter.getItemId(0))
                    }
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
                assertEquals(parsed, store.page(job.id, 1)!!.vision)
                assertEquals(listOf(HealthOcrLine("Glucose: 5.4 mmol/L")), store.page(job.id, 1)!!.lines)
                HealthRecordStore(context, names.records).use { assertEquals(0L, it.count()) }
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
}
