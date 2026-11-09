package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.Instrumentation
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthCareVisitUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun find(activity: Activity, tag: String) = views(activity.window.decorView).firstOrNull { it.tag == tag }
    private fun field(activity: HealthCareVisitActivity, name: String) = HealthCareVisitActivity::class.java
        .getDeclaredField(name).apply { isAccessible = true }.get(activity)
    private fun dialog(activity: HealthCareVisitActivity) = field(activity, "dialog") as? AlertDialog
    private fun await(scenario: ActivityScenario<HealthCareVisitActivity>, ready: (HealthCareVisitActivity) -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 15000
        do { var done = false; scenario.onActivity { done = ready(it) }; if (done) return; SystemClock.sleep(50) }
        while (SystemClock.elapsedRealtime() < end)
        fail("Visit summary UI did not reach the expected state")
    }
    private fun fixture(test: (HealthOverviewDatabases, HealthCareConcern, ActivityScenario<HealthCareVisitActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val workers = mutableListOf<ExecutorService>()
        try {
            val issue = HealthCareFollowUpTestFixture.confirmed(context, names)
            ActivityScenario.launch<HealthCareVisitActivity>(Intent(context, HealthCareVisitActivity::class.java)
                .putHealthNavigationFixture(names).putExtra("health_care_id", issue.id)).use { scenario ->
                scenario.onActivity { workers += field(it, "worker") as ExecutorService }
                test(names, issue, scenario)
                scenario.onActivity { (field(it, "worker") as ExecutorService).let { worker -> if (worker !in workers) workers += worker } }
            }
        } finally {
            workers.forEach { assertTrue(it.awaitTermination(10, TimeUnit.SECONDS)) }
            listOf(names.care, names.records, names.privacy, names.profile, names.reminders).forEach(context::deleteDatabase)
        }
    }
    private fun preview(scenario: ActivityScenario<HealthCareVisitActivity>) {
        scenario.onActivity { find(it, "health-visit-preview")!!.performClick() }
        await(scenario) { find(it, "health-visit-document") != null }
    }
    private fun capture(test: (AtomicReference<Intent>) -> Unit) {
        val captured = AtomicReference<Intent>()
        val monitor = object : Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): Instrumentation.ActivityResult? {
                if (intent.action != Intent.ACTION_CHOOSER && intent.component?.className != HealthRecordRevisionActivity::class.java.name) return null
                captured.set(Intent(intent))
                return Instrumentation.ActivityResult(Activity.RESULT_CANCELED, null)
            }
        }
        instrumentation.addMonitor(monitor)
        try { test(captured) } finally { instrumentation.removeMonitor(monitor) }
    }

    @Test fun previewDefaultsExcludeProfileAndNeverShareAutomatically(): Unit = fixture { _, _, scenario -> capture { sent ->
        scenario.onActivity { assertFalse((find(it, "health-visit-scope-PROFILE") as CheckBox).isChecked) }
        preview(scenario)
        assertNull(sent.get())
        scenario.onActivity {
            val value = field(it, "document") as HealthCareVisitSummary
            assertFalse(HealthCareVisitSection.PROFILE in value.sections)
            assertTrue(value.items.any { item -> item.record != null })
            find(it, "health-visit-share")!!.performClick()
            assertTrue(dialog(it)!!.isShowing)
            dialog(it)!!.getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
        }
        assertNull(sent.get())
        if (InstrumentationRegistry.getArguments().getString("health_visit_screenshot") == "true") {
            instrumentation.waitForIdleSync(); SystemClock.sleep(300)
            instrumentation.uiAutomation.takeScreenshot()?.let { image -> try {
                File(context.getExternalFilesDir(null), "health-visit-fixture.png").outputStream().use {
                    image.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
            } finally { image.recycle() } }
        }
    } }
    @Suppress("DEPRECATION")
    @Test fun explicitShareContainsOnlySelectedPreviewItems(): Unit = fixture { _, _, scenario -> capture { sent ->
        preview(scenario)
        var expected = ""
        scenario.onActivity {
            val value = field(it, "document") as HealthCareVisitSummary
            val chosen = value.items.first { item -> item.record != null }.key
            value.items.filter { item -> item.key != chosen }.forEach { item ->
                (find(it, "health-visit-item-${item.key}") as CheckBox).isChecked = false
            }
            expected = value.selectedText(setOf(chosen))
            find(it, "health-visit-share")!!.performClick()
            assertNull(sent.get())
            dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        }
        await(scenario) { sent.get() != null }
        val send = sent.get().getParcelableExtra<Intent>(Intent.EXTRA_INTENT)!!
        assertEquals(Intent.ACTION_SEND, send.action); assertEquals("text/plain", send.type)
        assertEquals(expected, send.getStringExtra(Intent.EXTRA_TEXT))
        assertNull(send.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM))
        assertNull(send.clipData)
    } }
    @Test fun backgroundAndRecreationDiscardPreviewAndConfirmation(): Unit = fixture { _, _, scenario -> capture { sent ->
        preview(scenario)
        scenario.onActivity { find(it, "health-visit-share")!!.performClick() }
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(field(it, "document")); assertNull(dialog(it)); assertNull(find(it, "health-visit-document")) }
        scenario.moveToState(Lifecycle.State.RESUMED)
        await(scenario) { find(it, "health-visit-preview") != null }
        assertNull(sent.get())
        preview(scenario)
        scenario.recreate()
        await(scenario) { find(it, "health-visit-preview") != null }
        scenario.onActivity { assertNull(field(it, "document")); assertNull(find(it, "health-visit-document")) }
    } }
    @Test fun revocationDismissesPreviewAndPendingShare(): Unit = fixture { names, _, scenario -> capture { sent ->
        preview(scenario)
        scenario.onActivity { find(it, "health-visit-share")!!.performClick() }
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        await(scenario) { dialog(it) == null && field(it, "document") == null }
        assertNull(sent.get())
    } }
    @Test fun newSourceInvalidatesPreviewBeforeShare(): Unit = fixture { names, _, scenario -> capture { sent ->
        preview(scenario)
        HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE,
            mapOf("glucose" to "6.3"), "mmol/L", System.currentTimeMillis())) }
        await(scenario) { find(it, "health-visit-preview") != null && field(it, "document") == null }
        assertNull(sent.get())
    } }
    @Test fun originalUsesExactRecordRevisionWithoutSharing(): Unit = fixture { _, _, scenario -> capture { opened ->
        preview(scenario)
        lateinit var source: HealthCareRecordRef
        scenario.onActivity {
            source = (field(it, "document") as HealthCareVisitSummary).items.first { item -> item.record != null }.record!!
            find(it, "health-visit-original-${source.id}")!!.performClick()
        }
        await(scenario) { opened.get() != null }
        assertEquals(HealthRecordRevisionActivity::class.java.name, opened.get().component!!.className)
        assertEquals(source.id, opened.get().getStringExtra("health_record"))
        assertEquals(source.revision, opened.get().getIntExtra("health_revision", -1))
    } }
    @Test fun lowMemoryDiscardsPreview(): Unit = fixture { _, _, scenario ->
        preview(scenario)
        scenario.onActivity {
            it.onTrimMemory(android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW)
            assertNull(field(it, "document")); assertNotNull(find(it, "health-visit-preview"))
        }
    }
}
