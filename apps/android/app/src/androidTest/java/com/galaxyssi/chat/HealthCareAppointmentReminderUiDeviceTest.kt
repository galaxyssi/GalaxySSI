package com.galaxyssi.chat

import android.app.AlertDialog
import android.app.DatePickerDialog
import android.app.KeyguardManager
import android.app.TimePickerDialog
import android.graphics.Bitmap
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthCareAppointmentReminderUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun field(value: Any, name: String) = value.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(value)
    private fun dialog(activity: HealthCareEncountersActivity): AlertDialog? =
        field((field(activity, "reminderEditor\$delegate") as Lazy<*>).value!!, "dialog") as? AlertDialog
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun find(activity: HealthCareEncountersActivity, tag: String) = views(activity.window.decorView).firstOrNull { it.tag == tag }
    private fun await(scenario: ActivityScenario<HealthCareEncountersActivity>, ready: (HealthCareEncountersActivity) -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 20_000L
        do { var done = false; scenario.onActivity { done = ready(it) }; if (done) return; SystemClock.sleep(50) }
        while (SystemClock.elapsedRealtime() < deadline)
        fail("Appointment UI did not reach the expected state")
    }
    private fun confirmScreen(scenario: ActivityScenario<HealthCareEncountersActivity>) {
        scenario.onActivity {
            find(it, "encounter-reminder-schedule")!!.performClick()
            assertTrue(dialog(it) is DatePickerDialog); dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick()
        }
        await(scenario) { dialog(it) is TimePickerDialog }
        scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
        await(scenario) { dialog(it)?.let { d -> d.isShowing && d !is DatePickerDialog && d !is TimePickerDialog } == true }
    }
    @Test fun notificationOpensVisitAndOnlyExplicitConfirmationChangesReminder() {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        HealthCareAppointmentFixture(context).use { f ->
            val initial = f.schedule()
            val intent = HealthCareReminderRuntime.openIntent(context, initial, f.names)
            var worker: ExecutorService? = null
            try {
                ActivityScenario.launch<HealthCareEncountersActivity>(intent).use { scenario ->
                    scenario.onActivity { worker = field(it, "worker") as ExecutorService }
                    await(scenario) { find(it, "encounter-reminder-cancel") != null }
                    scenario.onActivity { assertNotNull(find(it, "encounter-preparation")); assertNull(find(it, "encounter-add")) }
                    confirmScreen(scenario)
                    scenario.moveToState(Lifecycle.State.CREATED)
                    scenario.onActivity { assertNull(dialog(it)); assertNull(field(it, "snapshot")) }
                    assertEquals(initial, f.snapshot().reminder)
                    scenario.moveToState(Lifecycle.State.RESUMED)
                    await(scenario) { find(it, "encounter-reminder-cancel") != null }
                    confirmScreen(scenario)
                    scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_NEGATIVE).performClick() }
                    assertEquals(initial, f.snapshot().reminder)
                    confirmScreen(scenario)
                    scenario.onActivity { dialog(it)!!.getButton(AlertDialog.BUTTON_POSITIVE).performClick() }
                    await(scenario) { find(it, "encounter-reminder-cancel") != null && !(field(it, "busy") as Boolean) }
                    assertNotEquals(initial.token, f.snapshot().reminder!!.token)
                    if (InstrumentationRegistry.getArguments().getString("health_appointment_screenshot") == "true") {
                        scenario.onActivity {
                            val row = find(it, "encounter-reminder-status")!!
                            row.requestRectangleOnScreen(android.graphics.Rect(0, -220, row.width, row.height + 200), true)
                        }
                        instrumentation.waitForIdleSync(); SystemClock.sleep(300)
                        instrumentation.uiAutomation.takeScreenshot()?.let { image -> try {
                            File(context.getExternalFilesDir(null), "health-appointment-reminder-fixture.png").outputStream().use {
                                image.compress(Bitmap.CompressFormat.PNG, 100, it)
                            }
                        } finally { image.recycle() } }
                    }
                    scenario.onActivity { find(it, "encounter-reminder-cancel")!!.performClick() }
                    await(scenario) { find(it, "encounter-reminder-status") != null && find(it, "encounter-reminder-cancel") == null }
                    assertEquals(HealthCareReminderState.CANCELLED, f.snapshot().reminder!!.state)
                    assertEquals(f.visit, f.snapshot().selected)
                }
            } finally {
                worker?.let { assertTrue(it.awaitTermination(20, TimeUnit.SECONDS)) }
            }
        }
    }
}
