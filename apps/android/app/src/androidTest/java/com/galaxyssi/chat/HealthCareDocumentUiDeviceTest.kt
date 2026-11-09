package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthCareDocumentUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun field(value: Any, name: String) = value.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(value)
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun dialog(activity: HealthCareDocumentsActivity) = field(activity, "dialog") as? AlertDialog
    private fun find(activity: HealthCareDocumentsActivity, tag: String) =
        (views(activity.window.decorView) + dialog(activity)?.window?.decorView?.let(::views).orEmpty()).firstOrNull { it.tag == tag }
    private fun await(scenario: ActivityScenario<HealthCareDocumentsActivity>, ready: (HealthCareDocumentsActivity) -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 15000
        do { var done = false; scenario.onActivity { done = ready(it) }; if (done) return; SystemClock.sleep(50) }
        while (SystemClock.elapsedRealtime() < end)
        fail("Visit source UI did not reach the expected state")
    }
    private fun fixture(test: (HealthCareDocumentFixture, HealthOriginal, ActivityScenario<HealthCareDocumentsActivity>) -> Unit) {
        assumeFalse("Native source review needs an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        HealthCareDocumentFixture(context).use { f ->
            val original = f.pdf(); var worker: ExecutorService? = null
            try {
                ActivityScenario.launch<HealthCareDocumentsActivity>(Intent(context, HealthCareDocumentsActivity::class.java)
                    .putHealthNavigationFixture(f.names).putExtra("health_care_id", f.issue.id).putExtra("health_encounter_id", f.visit.id)).use { scenario ->
                    scenario.onActivity { worker = field(it, "worker") as ExecutorService }
                    await(scenario) { find(it, "document-add") != null }
                    test(f, original, scenario)
                }
            } finally { worker?.let { assertTrue(it.awaitTermination(15, TimeUnit.SECONDS)) } }
        }
    }
    private fun choose(scenario: ActivityScenario<HealthCareDocumentsActivity>, original: HealthOriginal) {
        scenario.onActivity { find(it, "document-add")!!.performClick() }
        await(scenario) { find(it, "document-original-${original.id}") != null }
        scenario.onActivity { find(it, "document-original-${original.id}")!!.performClick() }
    }
    private fun confirmation(scenario: ActivityScenario<HealthCareDocumentsActivity>) {
        await(scenario) { dialog(it)?.findViewById<TextView>(android.R.id.message)?.text?.contains("synthetic-visit.pdf") == true }
    }
    @Test fun chooseSecondPageConfirmReopenAndRemoveLink(): Unit = fixture { f, original, scenario ->
        choose(scenario, original)
        scenario.onActivity { find(it, "document-preview")!!.performClick() }
        await(scenario) { find(it, "document-page-next") != null }
        scenario.onActivity { find(it, "document-page-next")!!.performClick() }
        await(scenario) { find(it, "document-page-previous") != null && find(it, "document-page-next") == null }
        scenario.onActivity { find(it, "document-link-page")!!.performClick() }
        confirmation(scenario)
        scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
        await(scenario) { find(it, "document-add") != null && dialog(it) == null && !(field(it, "busy") as Boolean) }
        val saved = f.snapshot().items.single().link
        assertEquals(2, saved.source.page)
        await(scenario) { find(it, "document-row-${saved.id}") != null }
        if (InstrumentationRegistry.getArguments().getString("health_document_screenshot") == "true") {
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                try { File(context.getExternalFilesDir(null), "health-document-fixture.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) } }
                finally { bitmap.recycle() }
            }
        }
        scenario.onActivity { find(it, "document-row-${saved.id}")!!.performClick(); find(it, "document-remove")!!.performClick() }
        scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
        await(scenario) { find(it, "document-add") != null && find(it, "document-row-${saved.id}") == null && !(field(it, "busy") as Boolean) }
        assertTrue(f.snapshot().items.isEmpty()); f.originals().use { assertTrue(it.present(original)) }
    }
    @Test fun cancelledConfirmationDoesNotCreateAnAssociation(): Unit = fixture { f, original, scenario ->
        choose(scenario, original)
        scenario.onActivity { find(it, "document-whole")!!.performClick() }
        confirmation(scenario)
        scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_NEGATIVE).performClick() }
        assertTrue(f.snapshot().items.isEmpty())
    }
    @Test fun backgroundClearsPreviewBitmapAndPlaintextThenReloadsFromStorage(): Unit = fixture { f, original, scenario ->
        choose(scenario, original)
        scenario.onActivity { find(it, "document-preview")!!.performClick() }
        await(scenario) { find(it, "document-raster") != null }
        var rendered: Bitmap? = null
        scenario.onActivity { rendered = field(it, "bitmap") as Bitmap }
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(dialog(it)); assertNull(field(it, "snapshot")); assertNull(field(it, "bitmap")) }
        assertTrue(rendered!!.isRecycled)
        scenario.moveToState(Lifecycle.State.RESUMED)
        await(scenario) { find(it, "document-add") != null }
        assertTrue(f.snapshot().items.isEmpty())
    }
    @Test fun revokedPermissionDismissesPendingConfirmationWithoutWriting(): Unit = fixture { f, original, scenario ->
        choose(scenario, original)
        scenario.onActivity { find(it, "document-whole")!!.performClick() }
        confirmation(scenario)
        HealthPrivacyStore(context, f.names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        await(scenario) { dialog(it) == null && find(it, "document-add") == null && !(field(it, "busy") as Boolean) }
        HealthCareStore(context, f.names.care).use { assertTrue(it.encounterDocuments(f.issue.id, f.visit.id).items.isEmpty()) }
    }
    @Test fun deletedSourceReloadsAsUnavailableButCanStillBeUnlinked(): Unit = fixture { f, original, scenario ->
        choose(scenario, original)
        scenario.onActivity { find(it, "document-whole")!!.performClick() }
        confirmation(scenario)
        scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
        await(scenario) { find(it, "document-add") != null && !(field(it, "busy") as Boolean) }
        val saved = f.snapshot().items.single().link
        f.originals().use { it.removeOriginalBytes(original) }
        await(scenario) { find(it, "document-row-${saved.id}")?.let(::views)?.filterIsInstance<TextView>()
            ?.any { text -> text.text.contains(it.getString(R.string.health_document_missing)) } == true }
        scenario.onActivity {
            find(it, "document-row-${saved.id}")!!.performClick()
            assertNull(find(it, "document-preview")); assertNotNull(find(it, "document-remove"))
        }
    }
}
