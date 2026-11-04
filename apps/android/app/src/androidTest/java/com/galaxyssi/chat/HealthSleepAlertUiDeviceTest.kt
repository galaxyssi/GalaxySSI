package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthSleepAlertUiDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun screen(test: (ActivityScenario<HealthReminderActivity>, HealthPrivacyStore) -> Unit) {
        assumeFalse("Sleep reminder UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val id = UUID.randomUUID()
        val names = listOf("health-reminder-test-$id.db", "health-weekly-test-$id.db", "health-privacy-test-$id.db")
        val now = System.currentTimeMillis()
        var worker: ExecutorService? = null
        try {
            HealthReminderStore(context, names[0]).use { store -> store.save(store.settings().copy(sleepChanges = true), now) }
            HealthRecordStore(context, names[1]).use { seedHealthSleep(it, now, ZoneId.systemDefault()) }
            HealthPrivacyStore(context, names[2]).use { privacy ->
                val intent = Intent(context, HealthReminderActivity::class.java).putExtra("health_reminder_test_db", names[0])
                    .putExtra("health_sleep_test_records", names[1]).putExtra("health_privacy_test_db", names[2])
                ActivityScenario.launch<HealthReminderActivity>(intent).use { scenario -> try { test(scenario, privacy) } finally {
                    scenario.onActivity { worker = HealthReminderActivity::class.java.getDeclaredField("io").apply { isAccessible = true }.get(it) as ExecutorService }
                } }
            }
        } finally { worker?.awaitTermination(10, TimeUnit.SECONDS); names.forEach(context::deleteDatabase) }
    }
    private fun find(view: View, tag: String): View? {
        if (view.tag == tag) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) find(view.getChildAt(i), tag)?.let { return it }
        return null
    }
    private fun await(scenario: ActivityScenario<HealthReminderActivity>, tag: String) {
        val until = SystemClock.elapsedRealtime() + 15_000
        do {
            var ready = false
            scenario.onActivity { ready = find(it.window.decorView, tag) != null }
            if (ready) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Missing native view: $tag")
    }
    private fun click(scenario: ActivityScenario<HealthReminderActivity>, tag: String) {
        await(scenario, tag)
        scenario.onActivity { requireNotNull(find(it.window.decorView, tag)).performClick() }
    }
    @Test fun calculatedAlertOpensRealChartAndKeepsSnoozeAndCompletion() = screen { scenario, _ ->
        click(scenario, "health-sleep-alert")
        await(scenario, "health-sleep-chart")
        click(scenario, "health-sleep-snooze")
        await(scenario, "health-sleep-state-SNOOZED")
        click(scenario, "health-sleep-complete")
        await(scenario, "health-sleep-state-COMPLETE")
        scenario.recreate()
        await(scenario, "health-sleep-state-COMPLETE")
    }
    @Test fun backgroundClearsChartAndForegroundRestoresTheSameAlert() = screen { scenario, _ ->
        click(scenario, "health-sleep-alert"); await(scenario, "health-sleep-chart")
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(find(it.window.decorView, "health-sleep-chart")) }
        scenario.moveToState(Lifecycle.State.RESUMED)
        await(scenario, "health-sleep-chart")
    }
    @Test fun revocationRemovesAlreadyDisplayedSleepEvidence() = screen { scenario, privacy ->
        click(scenario, "health-sleep-alert"); await(scenario, "health-sleep-chart")
        privacy.change(HealthPrivacyOption.CONFIRMED_METRICS, false, privacy.policy().version)
        await(scenario, "health-sleep-blocked")
        scenario.onActivity { assertNull(find(it.window.decorView, "health-sleep-chart")) }
    }
}
