package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.KeyguardManager
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import android.widget.EditText
import android.widget.RadioButton
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

class HealthCareInstructionUiDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun field(value: Any, name: String) = value.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(value)
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun editor(activity: HealthCareInstructionsActivity) = field(activity, "editor\$delegate").let { (it as Lazy<*>).value!! }
    private fun dialog(activity: HealthCareInstructionsActivity) = field(editor(activity), "dialog") as? AlertDialog
    private fun find(activity: HealthCareInstructionsActivity, tag: String) =
        (views(activity.window.decorView) + dialog(activity)?.window?.decorView?.let(::views).orEmpty() +
            (field(activity, "dialog") as? AlertDialog)?.window?.decorView?.let(::views).orEmpty()).firstOrNull { it.tag == tag }
    private fun await(scenario: ActivityScenario<HealthCareInstructionsActivity>, ready: (HealthCareInstructionsActivity) -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 20000
        do { var done = false; scenario.onActivity { done = ready(it) }; if (done) return; SystemClock.sleep(50) }
        while (SystemClock.elapsedRealtime() < end)
        fail("Instruction review UI did not reach the expected state")
    }
    private fun fixture(read: Boolean = false, test: (HealthCareInstructionFixture, ActivityScenario<HealthCareInstructionsActivity>) -> Unit) {
        assumeFalse("Native instruction review needs an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        HealthCareInstructionFixture(context).use { f ->
            val workers = mutableListOf<ExecutorService>()
            val intent = Intent(context, HealthCareInstructionsActivity::class.java).putHealthNavigationFixture(f.documents.names)
                .putExtra("health_care_id", f.documents.issue.id).putExtra("health_encounter_id", f.documents.visit.id)
            if (read) intent.putExtra("health_document_id", f.link.id).putExtra("health_document_page", 2)
            try {
                ActivityScenario.launch<HealthCareInstructionsActivity>(intent).use { scenario ->
                    scenario.onActivity { workers += field(it, "worker") as ExecutorService }
                    await(scenario) { find(it, if (read) "instruction-create" else "instruction-sources") != null }
                    try { test(f, scenario) } finally {
                        scenario.onActivity { (field(it, "worker") as ExecutorService).let { worker -> if (worker !in workers) workers += worker } }
                    }
                }
            } finally { workers.forEach { assertTrue(it.awaitTermination(20, TimeUnit.SECONDS)) } }
        }
    }
    private fun open(f: HealthCareInstructionFixture, scenario: ActivityScenario<HealthCareInstructionsActivity>): HealthCareInstruction {
        val value = f.create()
        await(scenario) { find(it, "instruction-row-${value.id}") != null }
        scenario.onActivity { find(it, "instruction-row-${value.id}")!!.performClick() }
        await(scenario) { find(it, "instruction-edit") != null }
        return value
    }
    @Test fun selectingActualSourceLinesCreatesOnlyAnUnreviewedDraft(): Unit = fixture(read = true) { f, scenario ->
        scenario.onActivity {
            (find(it, "instruction-line-0") as CheckBox).performClick()
            (find(it, "instruction-line-1") as CheckBox).performClick()
            find(it, "instruction-create")!!.performClick()
            find(it, "instruction-create")!!.performClick()
        }
        await(scenario) { find(it, "instruction-edit") != null && !(field(it, "busy") as Boolean) }
        val value = f.snapshot().page.items.single()
        assertEquals(2, value.source.original.page); assertFalse(value.draft.reviewed)
        assertEquals("Synthetic follow-up\nReview the recorded visit", value.source.quote)
        if (InstrumentationRegistry.getArguments().getString("health_instruction_screenshot") == "true") {
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            instrumentation.waitForIdleSync()
            SystemClock.sleep(250)
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                try { File(context.getExternalFilesDir(null), "health-instruction-fixture.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) } }
                finally { bitmap.recycle() }
            }
        }
    }
    @Test fun editingCheckedTextRequiresReviewAgainBeforeSaving(): Unit = fixture { f, scenario ->
        val value = open(f, scenario)
        scenario.onActivity {
            find(it, "instruction-edit")!!.performClick()
            val input = find(it, "instruction-field-NAME") as EditText
            val checked = find(it, "instruction-checked-NAME") as RadioButton
            input.setText("Synthetic review"); checked.performClick(); assertTrue(checked.isChecked)
            input.setText("Changed synthetic review"); assertFalse(checked.isChecked)
            dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        }
        await(scenario) { dialog(it) == null && find(it, "instruction-edit") != null && !(field(it, "busy") as Boolean) }
        val saved = f.snapshot(value.id).selected!!
        assertEquals(HealthCareFieldReview.UNREVIEWED, saved.draft.fields[HealthCareInstructionField.NAME]!!.review)
        assertFalse(saved.draft.reviewed); assertEquals(value.source, saved.source)
    }
    @Test fun markingUnstatedClearsTextAndNeverCreatesAnExecutablePlan(): Unit = fixture { f, scenario ->
        val value = open(f, scenario)
        scenario.onActivity {
            find(it, "instruction-edit")!!.performClick()
            (find(it, "instruction-field-NAME") as EditText).setText("Discard this synthetic draft")
            value.draft.required.forEach { field -> (find(it, "instruction-missing-${field.name}") as RadioButton).performClick() }
            assertEquals("", (find(it, "instruction-field-NAME") as EditText).text.toString())
            dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        }
        await(scenario) { dialog(it) == null && find(it, "instruction-edit") != null && !(field(it, "busy") as Boolean) }
        val saved = f.snapshot(value.id).selected!!
        assertTrue(saved.draft.reviewed); assertEquals(saved.draft.required, saved.draft.missing)
        HealthCareStore(context, f.documents.names.care).use { assertTrue(it.reminders(value.concernId).isEmpty()) }
    }
    @Test fun backgroundDiscardsUnsavedReviewAndReloadsPersistedList(): Unit = fixture { f, scenario ->
        val value = open(f, scenario)
        scenario.onActivity {
            find(it, "instruction-edit")!!.performClick()
            (find(it, "instruction-field-NAME") as EditText).setText("Unsaved synthetic instruction")
        }
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity {
            assertNull(dialog(it)); assertNull(field(it, "snapshot")); assertNull(field(it, "reading"))
            assertNull(field(editor(it), "root"))
        }
        scenario.moveToState(Lifecycle.State.RESUMED)
        await(scenario) { find(it, "instruction-row-${value.id}") != null }
        assertEquals(value, f.snapshot(value.id).selected)
    }
    @Test fun revocationClosesTheEditorWithoutSaving(): Unit = fixture { f, scenario ->
        val value = open(f, scenario)
        scenario.onActivity { find(it, "instruction-edit")!!.performClick() }
        HealthPrivacyStore(context, f.documents.names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        await(scenario) { dialog(it) == null && find(it, "instruction-edit") == null && !(field(it, "busy") as Boolean) }
        HealthCareStore(context, f.documents.names.care).use { assertEquals(value, it.instruction(value.id)) }
    }
    @Test fun deletionRemovesReviewButKeepsOriginalFile(): Unit = fixture { f, scenario ->
        val value = open(f, scenario)
        scenario.onActivity {
            find(it, "instruction-delete")!!.performClick()
            (field(it, "dialog") as AlertDialog).getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        }
        await(scenario) { find(it, "instruction-sources") != null && !(field(it, "busy") as Boolean) }
        assertTrue(f.snapshot().page.items.isEmpty())
        f.documents.originals().use { assertTrue(it.present(f.original)) }
        HealthCareStore(context, f.documents.names.care).use { assertTrue(it.instructionHistory(value.concernId, value.id).items.isEmpty()) }
    }
    @Test fun backgroundRecyclesOriginalPreviewWithoutLosingSavedReview(): Unit = fixture { f, scenario ->
        val value = open(f, scenario)
        scenario.onActivity { find(it, "instruction-preview")!!.performClick() }
        await(scenario) { field(it, "sourceDialog") != null }
        lateinit var raster: Bitmap
        scenario.onActivity { raster = field(field(it, "sourceDialog")!!, "raster") as Bitmap; assertFalse(raster.isRecycled) }
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(field(it, "sourceDialog")); assertNull(field(it, "snapshot")); assertTrue(raster.isRecycled) }
        assertEquals(value, f.snapshot(value.id).selected)
    }
    @Test fun landscapeAndNarrowWindowKeepSavedDraftAndWrapVisibleText(): Unit = fixture { f, scenario ->
        scenario.onActivity { it.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT }
        await(scenario) { it.resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT && find(it, "instruction-sources") != null }
        val value = open(f, scenario)
        scenario.onActivity {
            find(it, "instruction-edit")!!.performClick()
            (find(it, "instruction-field-NAME") as EditText).setText("合成旋转测试：未保存")
            it.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        }
        await(scenario) { it.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE && find(it, "instruction-row-${value.id}") != null }
        scenario.onActivity { assertNull(dialog(it)); find(it, "instruction-row-${value.id}")!!.performClick() }
        await(scenario) { find(it, "instruction-edit") != null }
        scenario.onActivity { it.window.setLayout((320 * it.resources.displayMetrics.density).toInt(), (480 * it.resources.displayMetrics.density).toInt()) }
        SystemClock.sleep(250)
        scenario.onActivity { activity ->
            views(activity.window.decorView).filterIsInstance<TextView>().filter { it.isShown }.forEach { view ->
                val layout = view.layout ?: return@forEach
                val width = view.width - view.totalPaddingLeft - view.totalPaddingRight
                assertTrue("Visible text needs a positive width", width > 0)
                for (line in 0 until layout.lineCount) assertTrue("Text must wrap inside its window", layout.getLineWidth(line) <= width + 2)
            }
        }
        assertEquals(value, f.snapshot(value.id).selected)
    }
    @Test fun uncheckedDraftCannotOfferAnExecutableAction(): Unit = fixture { f, scenario ->
        open(f, scenario)
        scenario.onActivity { assertNull(find(it, "instruction-action-add")); assertNull(find(it, "instruction-action-open")) }
    }
    @Test fun confirmationRequiresReviewAndCancelDoesNotAddAnAction(): Unit = fixture { f, scenario ->
        val value = reviewedHealthInstruction(f)
        await(scenario) { find(it, "instruction-row-${value.id}") != null }
        scenario.onActivity { find(it, "instruction-row-${value.id}")!!.performClick() }
        await(scenario) { find(it, "instruction-action-add") != null }
        scenario.onActivity {
            find(it, "instruction-action-add")!!.performClick()
            val d = field(it, "dialog") as AlertDialog
            val button = d.getButton(AlertDialog.BUTTON_POSITIVE)
            val checked = find(it, "instruction-action-checked") as CheckBox
            assertFalse(checked.isChecked); assertFalse(button.isEnabled)
            button.performClick()
            assertTrue(d.isShowing)
            checked.performClick(); assertTrue(button.isEnabled)
            checked.performClick(); assertFalse(button.isEnabled)
            button.performClick()
            assertTrue(d.isShowing)
            d.getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
        }
        await(scenario) { (field(it, "dialog") as? AlertDialog)?.isShowing != true }
        assertTrue(f.snapshot(value.id).visit.issue.actions.none { it.instruction != null })
        scenario.onActivity {
            find(it, "instruction-action-add")!!.performClick()
            (find(it, "instruction-action-checked") as CheckBox).performClick()
            val button = (field(it, "dialog") as AlertDialog).getButton(AlertDialog.BUTTON_POSITIVE)
            assertTrue(button.isEnabled); button.performClick(); button.performClick()
        }
        await(scenario) { find(it, "instruction-action-open") != null && !(field(it, "busy") as Boolean) }
        assertEquals(1, f.snapshot(value.id).visit.issue.actions.count { it.instruction != null })
        HealthCareStore(context, f.documents.names.care).use { assertNull(it.reminder(HealthCareInstructionActionPolicy.actionId(value))) }
    }
    @Test fun backgroundClearsPendingActionConfirmationWithoutWriting(): Unit = fixture { f, scenario ->
        val value = reviewedHealthInstruction(f)
        await(scenario) { find(it, "instruction-row-${value.id}") != null }
        scenario.onActivity { find(it, "instruction-row-${value.id}")!!.performClick() }
        await(scenario) { find(it, "instruction-action-add") != null }
        scenario.onActivity { find(it, "instruction-action-add")!!.performClick(); (find(it, "instruction-action-checked") as CheckBox).performClick() }
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(field(it, "dialog")); assertNull(field(it, "snapshot")) }
        assertTrue(f.snapshot(value.id).visit.issue.actions.none { it.instruction != null })
    }
    @Test fun confirmedActionOpensExistingReminderWithFullTranscription(): Unit = fixture { f, scenario ->
        val value = reviewedHealthInstruction(f, HealthCareInstructionKind.MEDICATION)
        f.repository.confirmAction(f.snapshot(value.id), android.os.CancellationSignal())
        await(scenario) { find(it, "instruction-row-${value.id}") != null }
        scenario.onActivity { find(it, "instruction-row-${value.id}")!!.performClick() }
        await(scenario) { find(it, "instruction-action-open") != null }
        scenario.onActivity { find(it, "instruction-action-open")!!.performClick() }
        fun actionDialog(activity: HealthCareInstructionsActivity) =
            field((field(activity, "actions\$delegate") as Lazy<*>).value!!, "dialog") as? AlertDialog
        await(scenario) { actionDialog(it)?.isShowing == true }
        scenario.onActivity { activity ->
            val all = views(actionDialog(activity)!!.window!!.decorView)
            val text = all.filterIsInstance<TextView>().joinToString("\n") { it.text.toString() }
            value.draft.required.forEach { assertTrue(text.contains(value.draft.fields.getValue(it).text)) }
            assertNotNull(all.firstOrNull { it.tag == "health-care-followup-schedule" })
        }
        if (InstrumentationRegistry.getArguments().getString("health_instruction_screenshot") == "true") {
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            SystemClock.sleep(250)
            InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()?.let { bitmap ->
                try { File(context.getExternalFilesDir(null), "health-instruction-action-fixture.png").outputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                } } finally { bitmap.recycle() }
            }
        }
    }
}
