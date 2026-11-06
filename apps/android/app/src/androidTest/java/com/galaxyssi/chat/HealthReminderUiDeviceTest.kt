package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.Switch
import android.widget.ScrollView
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthReminderUiDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun screen(seed: Boolean = false, test: (ActivityScenario<HealthReminderActivity>, HealthReminderStore) -> Unit) {
        assumeFalse("Reminder UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val name = "health-reminder-test-${UUID.randomUUID()}.db"
        var worker: ExecutorService? = null
        try { HealthReminderStore(context, name).use { store ->
            if (seed) {
                val now = System.currentTimeMillis()
                val zone = ZoneId.systemDefault()
                val yesterday = HealthReminderPolicy.day(now, zone).minusDays(1)
                val due = HealthReminderPolicy.at(yesterday, 510, zone)
                store.save(store.settings().copy(enabled = true), due - 60_000)
                store.reconcile(due, zone)
            }
            val intent = Intent(context, HealthReminderActivity::class.java).putExtra("health_reminder_test_db", name)
            ActivityScenario.launch<HealthReminderActivity>(intent).use { scenario -> try { test(scenario, store) } finally {
                scenario.onActivity { activity ->
                    worker = HealthReminderActivity::class.java.getDeclaredField("io").apply { isAccessible = true }.get(activity) as ExecutorService
                }
            } }
        } } finally { worker?.awaitTermination(10, TimeUnit.SECONDS); context.deleteDatabase(name) }
    }
    private fun find(view: View, tag: String): View? {
        if (view.tag == tag) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) find(view.getChildAt(i), tag)?.let { return it }
        return null
    }
    private fun wait(scenario: ActivityScenario<HealthReminderActivity>, tag: String) {
        val timeout = SystemClock.elapsedRealtime() + 12_000
        do {
            var found = false
            scenario.onActivity { found = find(it.window.decorView, tag) != null }
            if (found) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < timeout)
        fail("Missing native view: $tag")
    }
    private fun click(scenario: ActivityScenario<HealthReminderActivity>, tag: String) {
        wait(scenario, tag)
        scenario.onActivity { requireNotNull(find(it.window.decorView, tag)).performClick() }
    }
    @Test fun preferencesRequireExplicitSaveAndAreOffByDefault() = screen { scenario, store ->
        click(scenario, "health-reminder-settings")
        wait(scenario, "health-reminder-enabled")
        scenario.onActivity {
            assertFalse((find(it.window.decorView, "health-reminder-enabled") as Switch).isChecked)
            assertFalse((find(it.window.decorView, "health-reminder-notifications") as Switch).isChecked)
            assertTrue((find(it.window.decorView, "health-reminder-hide-lock") as Switch).isChecked)
        }
        click(scenario, "health-reminder-enabled")
        assertFalse(store.settings().enabled)
        click(scenario, "health-reminder-save")
        wait(scenario, "health-reminder-settings")
        assertTrue(store.settings().enabled)
        scenario.recreate()
        click(scenario, "health-reminder-settings")
        wait(scenario, "health-reminder-enabled")
        scenario.onActivity { assertTrue((find(it.window.decorView, "health-reminder-enabled") as Switch).isChecked) }
    }
    @Test fun nativeDetailSnoozesThenCompletesAndRetainsHandledHistory() = screen(seed = true) { scenario, store ->
        click(scenario, "health-reminder-event")
        click(scenario, "health-reminder-snooze")
        wait(scenario, "health-reminder-state-SNOOZED")
        click(scenario, "health-reminder-complete")
        wait(scenario, "health-reminder-state-COMPLETE")
        assertTrue(store.page(HealthReminderFilter.HANDLED, null).rows.any { it.state == HealthReminderState.COMPLETE })
        scenario.recreate()
        wait(scenario, "health-reminder-state-COMPLETE")
    }
    @Test fun detailIsClearedInBackgroundAndReloadsTheSameOccurrence() = screen(seed = true) { scenario, _ ->
        click(scenario, "health-reminder-event")
        wait(scenario, "health-reminder-state-PENDING")
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(find(it.window.decorView, "health-reminder-state-PENDING")) }
        scenario.moveToState(Lifecycle.State.RESUMED)
        wait(scenario, "health-reminder-state-PENDING")
    }
    @Test fun pauseAndResumeAreExplicitAndSaveRemainsVisibleWhileScrolling() = screen { scenario, store ->
        click(scenario, "health-reminder-settings")
        click(scenario, "health-reminder-pause")
        wait(scenario, "health-reminder-paused-until")
        assertEquals(0L, store.settings().pauseUntil)
        scenario.onActivity { activity ->
            val marker = requireNotNull(find(activity.window.decorView, "health-reminder-paused-until"))
            val save = requireNotNull(find(activity.window.decorView, "health-reminder-save"))
            val scroll = generateSequence(marker.parent) { it.parent }.filterIsInstance<ScrollView>().first()
            assertFalse(generateSequence(save.parent) { it.parent }.any { it === scroll })
            assertTrue(save.getGlobalVisibleRect(Rect()))
            scroll.scrollTo(0, scroll.getChildAt(0).height)
            assertTrue(save.getGlobalVisibleRect(Rect()))
        }
        screenshot()
        click(scenario, "health-reminder-save")
        wait(scenario, "health-reminder-settings")
        assertTrue(store.settings().pauseUntil > System.currentTimeMillis())
        click(scenario, "health-reminder-settings")
        wait(scenario, "health-reminder-pause")
        scenario.onActivity { activity ->
            val button = find(activity.window.decorView, "health-reminder-pause") as TextView
            assertEquals(activity.getString(R.string.health_reminder_resume_plan), button.text)
        }
        click(scenario, "health-reminder-pause")
        assertTrue(store.settings().pauseUntil > System.currentTimeMillis())
        click(scenario, "health-reminder-save")
        wait(scenario, "health-reminder-settings")
        assertEquals(0L, store.settings().pauseUntil)
    }

    private fun screenshot() {
        if (InstrumentationRegistry.getArguments().getString("reminderDeliveryScreenshot") != "true") return
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.waitForIdleSync()
        SystemClock.sleep(350)
        val image = requireNotNull(instrumentation.uiAutomation.takeScreenshot())
        try { File(context.cacheDir, "health-reminder-pause.png").outputStream().use {
            check(image.compress(Bitmap.CompressFormat.PNG, 100, it))
        } } finally { image.recycle() }
    }
}
