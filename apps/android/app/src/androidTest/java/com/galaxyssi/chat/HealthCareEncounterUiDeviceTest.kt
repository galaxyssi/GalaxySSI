package com.galaxyssi.chat

import android.app.Activity
import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.KeyguardManager
import android.app.TimePickerDialog
import android.content.Intent
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.RadioButton
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthCareEncounterUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun find(activity: Activity, tag: String) = views(activity.window.decorView).firstOrNull { it.tag == tag }
    private fun field(value: Any, name: String) = value.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(value)
    private fun editor(activity: Activity) = field(activity, "editor\$delegate").let { (it as Lazy<*>).value!! }
    private fun dialog(activity: Activity) = field(editor(activity), "dialog") as? AlertDialog
    private fun input(activity: Activity, tag: String) = views(dialog(activity)!!.window!!.decorView).first { it.tag == tag }
    private fun await(scenario: ActivityScenario<HealthCareEncountersActivity>, ready: (HealthCareEncountersActivity) -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 15000
        do { var done = false; scenario.onActivity { done = ready(it) }; if (done) return; SystemClock.sleep(50) }
        while (SystemClock.elapsedRealtime() < end)
        fail("Visit record UI did not reach the expected state")
    }
    private fun fixture(seed: Int = 0, test: (HealthOverviewDatabases, HealthCareConcern, ActivityScenario<HealthCareEncountersActivity>) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        val workers = mutableListOf<ExecutorService>()
        try {
            val issue = HealthCareFollowUpTestFixture.confirmed(context, names)
            HealthCareStore(context, names.care).use { store -> repeat(seed) { index ->
                store.saveEncounter(issue.id, store.concern(issue.id)!!.revision, UUID.randomUUID().toString(), null,
                    HealthCareEncounterDraft("Synthetic visit $index"), UUID.randomUUID().toString(), System.currentTimeMillis())
            } }
            ActivityScenario.launch<HealthCareEncountersActivity>(Intent(context, HealthCareEncountersActivity::class.java)
                .putHealthNavigationFixture(names).putExtra("health_care_id", issue.id)).use { scenario ->
                scenario.onActivity { workers += field(it, "worker") as ExecutorService }
                await(scenario) { find(it, "encounter-add") != null }
                try { test(names, issue, scenario) } finally {
                    scenario.onActivity { (field(it, "worker") as ExecutorService).let { worker -> if (worker !in workers) workers += worker } }
                }
            }
        } finally {
            workers.forEach { assertTrue(it.awaitTermination(15, TimeUnit.SECONDS)) }
            listOf(names.care, names.records, names.privacy, names.profile, names.reminders).forEach(context::deleteDatabase)
        }
    }
    private fun entries(names: HealthOverviewDatabases, id: String) = HealthCareStore(context, names.care).use { it.encounters(id).items }
    private fun open(scenario: ActivityScenario<HealthCareEncountersActivity>, id: String) {
        scenario.onActivity { find(it, "encounter-row-$id")!!.performClick() }
        await(scenario) { find(it, "encounter-edit") != null }
    }
    private fun save(scenario: ActivityScenario<HealthCareEncountersActivity>) {
        scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
        await(scenario) { dialog(it) == null && find(it, "encounter-add") != null }
    }

    @Test fun createEditHistoryAndConfirmedDeletionPreserveThePlan(): Unit = fixture { names, issue, scenario ->
        scenario.onActivity {
            find(it, "encounter-add")!!.performClick()
            (input(it, "encounter-purpose") as EditText).setText("合成测试：就诊准备")
            (input(it, "encounter-facility") as EditText).setText("合成测试诊所")
            (input(it, "encounter-note") as EditText).setText("合成备注：带上检查记录")
        }
        save(scenario)
        val first = entries(names, issue.id).single()
        open(scenario, first.id)
        scenario.onActivity {
            find(it, "encounter-edit")!!.performClick()
            (input(it, "encounter-note") as EditText).setText("合成备注：已更新")
        }
        save(scenario); open(scenario, first.id)
        scenario.onActivity { find(it, "encounter-history")!!.performClick() }
        await(scenario) { find(it, "encounter-history-${first.revision}") != null }
        HealthCareStore(context, names.care).use { assertEquals(2, it.encounterHistory(issue.id, first.id).items.size) }
        scenario.onActivity { it.onBackPressed() }
        await(scenario) { find(it, "encounter-delete") != null }
        if (InstrumentationRegistry.getArguments().getString("health_encounter_screenshot") == "true") {
            instrumentation.waitForIdleSync()
            SystemClock.sleep(250)
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap -> try {
                File(context.getExternalFilesDir(null), "health-encounter-fixture.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            } finally { bitmap.recycle() } }
        }
        scenario.onActivity {
            find(it, "encounter-delete")!!.performClick()
            (field(it, "dialog") as AlertDialog).getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
        }
        assertEquals(1, entries(names, issue.id).size)
        scenario.onActivity {
            find(it, "encounter-delete")!!.performClick()
            (field(it, "dialog") as AlertDialog).getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        }
        await(scenario) { find(it, "encounter-add") != null }
        HealthCareStore(context, names.care).use {
            assertTrue(it.encounters(issue.id).items.isEmpty()); assertTrue(it.encounterHistory(issue.id, first.id).items.isEmpty())
            assertEquals(issue.actions, it.concern(issue.id)!!.actions); assertEquals(issue.stage, it.concern(issue.id)!!.stage)
        }
    }
    @Test fun cancellingTheEditorDiscardsTextWithoutWriting(): Unit = fixture { names, issue, scenario ->
        lateinit var typed: EditText
        scenario.onActivity {
            find(it, "encounter-add")!!.performClick(); typed = input(it, "encounter-purpose") as EditText
            typed.setText("合成未保存备注"); dialog(it)!!.getButton(AlertDialog.BUTTON_NEGATIVE).performClick()
        }
        await(scenario) { dialog(it) == null }
        scenario.onActivity { assertTrue(typed.text.isEmpty()) }
        assertTrue(entries(names, issue.id).isEmpty())
    }
    @Test fun bookingRequiresAnExplicitTimeAndNativePickersPersistIt(): Unit = fixture { names, issue, scenario ->
        scenario.onActivity {
            find(it, "encounter-add")!!.performClick()
            dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
            assertTrue(dialog(it)!!.isShowing)
            (input(it, "encounter-purpose") as EditText).setText("合成预约记录")
            (input(it, "encounter-state-BOOKING_RECORDED") as RadioButton).isChecked = true
            dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
            assertTrue(dialog(it)!!.isShowing)
            input(it, "encounter-planned").performClick()
            (field(editor(it), "picker") as DatePickerDialog).getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        }
        await(scenario) { field(editor(it), "picker") is TimePickerDialog }
        scenario.onActivity {
            (field(editor(it), "picker") as TimePickerDialog).getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        }
        await(scenario) { (field(editor(it), "picker") as? android.app.Dialog)?.isShowing != true }
        save(scenario)
        val recorded = entries(names, issue.id).single()
        assertEquals(HealthCareEncounterState.BOOKING_RECORDED, recorded.details.state)
        assertNotNull(recorded.details.plannedAt); assertNull(recorded.details.attendedAt)
        HealthCareStore(context, names.care).use { assertTrue(it.reminders(issue.id).isEmpty()) }
    }
    @Test fun backgroundRecreationAndLowMemoryClearUnsavedPlaintext(): Unit = fixture { names, issue, scenario ->
        lateinit var typed: EditText
        scenario.onActivity {
            find(it, "encounter-add")!!.performClick(); typed = input(it, "encounter-note") as EditText
            typed.setText("合成后台清理内容")
        }
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(field(it, "snapshot")); assertNull(dialog(it)); assertTrue(typed.text.isEmpty()) }
        scenario.moveToState(Lifecycle.State.RESUMED)
        await(scenario) { find(it, "encounter-add") != null }
        scenario.onActivity {
            find(it, "encounter-add")!!.performClick(); (input(it, "encounter-note") as EditText).setText("合成内存清理")
            it.onTrimMemory(android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW)
            assertNull(dialog(it)); assertNull(field(it, "snapshot"))
        }
        await(scenario) { find(it, "encounter-add") != null }
        scenario.recreate()
        await(scenario) { find(it, "encounter-add") != null }
        assertTrue(entries(names, issue.id).isEmpty())
    }
    @Test fun revocationDismissesTheEditorAndPreventsSave(): Unit = fixture { names, issue, scenario ->
        lateinit var typed: EditText
        scenario.onActivity {
            find(it, "encounter-add")!!.performClick(); typed = input(it, "encounter-purpose") as EditText
            typed.setText("合成撤权内容")
        }
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        await(scenario) { dialog(it) == null && field(it, "snapshot") == null && find(it, "encounter-add") == null }
        scenario.onActivity { assertTrue(typed.text.isEmpty()) }
        assertTrue(entries(names, issue.id).isEmpty())
    }
    @Test fun listPagesContainAtMostThirtyVisitsAndReturnToTheSamePage(): Unit = fixture(35) { _, _, scenario ->
        scenario.onActivity {
            assertEquals(30, views(it.window.decorView).count { view -> view.tag?.toString()?.startsWith("encounter-row-") == true })
            find(it, "encounter-next")!!.performClick()
        }
        await(scenario) { find(it, "encounter-previous") != null }
        var id = ""
        scenario.onActivity {
            val rows = views(it.window.decorView).filter { view -> view.tag?.toString()?.startsWith("encounter-row-") == true }
            assertEquals(5, rows.size); id = rows.first().tag.toString().removePrefix("encounter-row-")
        }
        open(scenario, id)
        scenario.onActivity { it.onBackPressed() }
        await(scenario) { find(it, "encounter-previous") != null }
        scenario.onActivity {
            assertNotNull(find(it, "encounter-row-$id")); assertNull(find(it, "encounter-next"))
            find(it, "encounter-previous")!!.performClick()
        }
        await(scenario) { find(it, "encounter-next") != null }
    }
    @Test fun failedInvalidatedLoadShowsRetryInsteadOfRemainingBlank(): Unit = fixture { names, issue, scenario ->
        val entered = CountDownLatch(1); val release = CountDownLatch(1)
        try {
            scenario.onActivity {
                (field(it, "worker") as ExecutorService).execute { entered.countDown(); check(release.await(10, TimeUnit.SECONDS)) }
            }
            assertTrue(entered.await(10, TimeUnit.SECONDS))
            scenario.onActivity { it.onTrimMemory(android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW) }
            HealthCareStore(context, names.care).use { it.delete(issue.id, it.concern(issue.id)!!.revision) }
            instrumentation.waitForIdleSync(); release.countDown()
            await(scenario) { find(it, "encounter-retry") != null }
            SystemClock.sleep(200)
            scenario.onActivity { assertFalse(field(it, "busy") as Boolean); assertNotNull(find(it, "encounter-retry")) }
        } finally { release.countDown() }
    }
}
