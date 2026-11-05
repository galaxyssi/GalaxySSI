package com.galaxyssi.chat

import android.app.Activity
import android.app.Instrumentation
import android.app.KeyguardManager
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.text.format.Formatter
import android.view.View
import android.view.inspector.WindowInspector
import android.widget.TextView
import androidx.core.content.FileProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthOriginalSaveDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val payload = "date,systolic,diastolic\n2025-01-01,124,82\n".toByteArray()

    @Test fun destinationWithMatchingLengthButWrongDigestFailsAndRequestsCleanup() = fixture { _, originals ->
        val original = original(originals)
        val sink = ByteArrayOutputStream()
        var cleaned = false
        val changed = payload.copyOf().apply { this[lastIndex] = 0 }
        assertTrue(runCatching {
            HealthOriginalSave.saveVerified(originals, scope(original), { sink }, { changed.inputStream() }, { cleaned = true })
        }.isFailure)
        assertTrue(cleaned)
        assertArrayEquals(payload, sink.toByteArray())
        assertArrayEquals(payload, originals.input(original).use { it.readBytes() })
    }

    @Test fun aRemovedReimportedOrReviewOnlyOriginalDoesNotOpenTheDestination() = fixture { _, originals ->
        val original = original(originals)
        val frozen = scope(original)
        fun rejected(value: HealthOriginalSaveScope) {
            val failure = runCatching {
                HealthOriginalSave.saveVerified(originals, value,
                    { fail("Unexpected destination open"); ByteArrayOutputStream() },
                    { error("Unexpected destination read") }, { error("Unexpected destination cleanup") })
            }.exceptionOrNull()
            assertTrue(failure is HealthOriginalSaveChanged)
        }
        assertTrue(originals.removeOriginalBytes(original))
        rejected(frozen)
        val reimported = original(originals)
        assertEquals(original.id, reimported.id)
        assertNotEquals(original.streamId, reimported.streamId)
        rejected(frozen)
        val review = original(originals, keep = false)
        assertTrue(review.reviewOnly)
        rejected(scope(review))
        assertTrue(originals.present(reimported))
    }

    @Test fun detailAndPreviewRequireConfirmationAndOnlyVerifiedPickerSaveIsAudited() = fixture { names, originals ->
        assumeFalse("Original save UI requires an unlocked Android 10+ display",
            Build.VERSION.SDK_INT < 29 || context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val original = original(originals)
        val output = File(context.cacheDir, "health-backups/original-${original.id}.csv")
        val target = FileProvider.getUriForFile(context, "${context.packageName}.files", output.apply {
            parentFile!!.mkdirs(); check(createNewFile())
        })
        val picker = AtomicReference<Intent>()
        val pickerResult = AtomicReference(Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null))
        val monitor = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.action != Intent.ACTION_CREATE_DOCUMENT) return null
                picker.set(Intent(intent))
                return pickerResult.get()
            }
        }
        instrumentation.addMonitor(monitor)
        try {
            val intent = Intent(context, HealthCaptureActivity::class.java).putHealthNavigationFixture(names)
                .putExtra("original", original.id)
            ActivityScenario.launch<HealthCaptureActivity>(intent).use { scenario ->
                click(scenario, "health-original-save")
                val preview = context.getString(R.string.health_original_save_preview, original.name, original.mime,
                    Formatter.formatShortFileSize(context, original.size))
                await("single-original confirmation") { onMain {
                    WindowInspector.getGlobalWindowViews().any {
                        it.findViewById<TextView>(android.R.id.message)?.text?.toString() == preview
                    }
                } }
                assertNull(picker.get())
                clickDialog(android.R.id.button2)
                assertTrue(audit(names).isEmpty())

                click(scenario, "health-open-original")
                await("structured preview save icon") { onMain {
                    WindowInspector.getGlobalWindowViews().mapNotNull { it.findViewWithTag<View>("health-structured-save") }
                        .lastOrNull()?.performClick() == true
                } }
                clickDialog(android.R.id.button1)
                await("cancelled document picker") { picker.get() != null }
                instrumentation.waitForIdleSync()
                assertEquals(0L, output.length())
                assertTrue(audit(names).isEmpty())

                scenario.recreate()
                picker.set(null)
                pickerResult.set(Instrumentation.ActivityResult(Activity.RESULT_OK, Intent().setData(target)))
                click(scenario, "health-original-save")
                clickDialog(android.R.id.button1)
                await("verified save in privacy history") { audit(names).singleOrNull()?.outcome == HealthAccessOutcome.COMPLETE }
                assertEquals(original.mime, picker.get().type)
                assertEquals(original.name, picker.get().getStringExtra(Intent.EXTRA_TITLE))
                assertArrayEquals(payload, output.readBytes())
                val event = audit(names).single()
                assertEquals(HealthAccessScope.originals(1), event.scope)
                val serialized = event.scope.json().toString()
                assertFalse(serialized.contains(original.name))
                assertFalse(serialized.contains(original.id))
                assertFalse(serialized.contains(original.sha256))
                assertTrue(originals.present(original))
            }
        } finally {
            instrumentation.removeMonitor(monitor)
            output.delete()
        }
    }

    private fun original(store: HealthOriginalStore, keep: Boolean = true): HealthOriginal {
        val id = UUID.randomUUID().toString()
        store.createJob(HealthImportJob(id, "content://fixture/report", System.currentTimeMillis(), keepOriginal = keep))
        return store.importOriginal(id, payload.inputStream(), "test-report.csv", "text/csv", "file")
    }
    private fun scope(original: HealthOriginal) = HealthOriginalSaveScope(original.id, original.streamId)
    private fun audit(names: HealthOverviewDatabases) = HealthPrivacyStore(context, names.privacy).use {
        it.page().entries.filter { event -> event.scope.purpose == HealthAccessPurpose.SAVE_ORIGINALS }
    }
    private fun fixture(test: (HealthOverviewDatabases, HealthOriginalStore) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { test(names, it) } }
        finally { clearHealthOverviewFixture(context, names) }
    }
    private fun click(scenario: ActivityScenario<HealthCaptureActivity>, tag: String) = await(tag) {
        var clicked = false
        scenario.onActivity { clicked = it.window.decorView.findViewWithTag<View>(tag)?.performClick() == true }
        clicked
    }
    private fun clickDialog(id: Int) = await("dialog button") { onMain {
        WindowInspector.getGlobalWindowViews().mapNotNull { it.findViewById<View>(id) }.lastOrNull()?.performClick() == true
    } }
    private fun onMain(block: () -> Boolean): Boolean {
        var result = false
        instrumentation.runOnMainSync { result = block() }
        return result
    }
    private fun await(label: String, ready: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 12_000
        do { if (ready()) return; SystemClock.sleep(50) } while (SystemClock.elapsedRealtime() < deadline)
        fail("Missing $label")
    }
}
