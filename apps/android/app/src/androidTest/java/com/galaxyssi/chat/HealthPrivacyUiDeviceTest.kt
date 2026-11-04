package com.galaxyssi.chat

import android.app.Activity
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.Switch
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.TimeUnit
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthPrivacyUiDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun <A : Activity> screen(type: Class<A>, workerName: String = "io", prepare: (HealthPrivacyStore, Intent) -> Unit = { _, _ -> },
        test: (ActivityScenario<A>, HealthPrivacyStore) -> Unit) {
        assumeFalse("Visible privacy checks require an unlocked device", context.getSystemService(android.app.KeyguardManager::class.java).isKeyguardLocked)
        val name = "health-privacy-test-${UUID.randomUUID()}.db"; var worker: ExecutorService? = null
        try { HealthPrivacyStore(context, name).use { store ->
            val intent = Intent(context, type).putExtra("health_privacy_test_db", name); prepare(store, intent)
            ActivityScenario.launch<A>(intent).use { scenario -> try { test(scenario, store) } finally { scenario.onActivity {
                worker = type.getDeclaredField(workerName).apply { isAccessible = true }.get(it) as ExecutorService
            } } }
        } } finally { worker?.awaitTermination(10, TimeUnit.SECONDS); context.deleteDatabase(name) }
    }
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup) (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun tag(activity: Activity, key: String) = views(activity.window.decorView).firstOrNull { it.tag == key }
    private fun <A : Activity> await(scenario: ActivityScenario<A>, condition: (A) -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        do { var ready = false; scenario.onActivity { ready = condition(it) }; if (ready) return; SystemClock.sleep(40) } while (SystemClock.elapsedRealtime() < deadline)
        fail("Privacy page did not reach the expected state")
    }
    @Test fun nativeSwitchesPersistAndDoNotOpenOnlineAccessByDefault() = screen(HealthPrivacyActivity::class.java) { scenario, store ->
        await(scenario) { tag(it, "health-privacy-CONFIRMED_METRICS") != null }
        scenario.onActivity {
            assertFalse((tag(it, "health-privacy-ONLINE_ANALYSIS") as Switch).isChecked)
            assertFalse(requireNotNull(tag(it, "health-privacy-ORIGINAL_IMAGES")).isEnabled)
            requireNotNull(tag(it, "health-privacy-CONFIRMED_METRICS")).performClick()
        }
        await(scenario) { (tag(it, "health-privacy-CONFIRMED_METRICS") as? Switch)?.let { v -> v.isEnabled && !v.isChecked } == true }
        assertFalse(store.policy().metrics); scenario.recreate()
        await(scenario) { (tag(it, "health-privacy-CONFIRMED_METRICS") as? Switch)?.isChecked == false }
    }
    @Test fun nativeAuditUsesRealPersistedEventsAndDropsViewsInBackground() = screen(HealthPrivacyActivity::class.java, prepare = { store, _ ->
        store.track(HealthAccessScope.originals(4, true)) {}
    }) { scenario, _ ->
        await(scenario) { tag(it, "health-privacy-history") != null }
        scenario.onActivity { tag(it, "health-privacy-history")!!.performClick() }
        await(scenario) { tag(it, "health-privacy-event") != null }
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertNull(tag(it, "health-privacy-event")) }
        scenario.moveToState(Lifecycle.State.RESUMED)
        await(scenario) { tag(it, "health-privacy-event") != null }
    }
    @Test fun revokingPermissionClearsTheAlreadyLoadedNativeTrend() = screen(HealthTrendActivity::class.java, "worker", prepare = { _, intent ->
        intent.putExtra("health_metric", HealthMetric.STEPS.name)
    }) { scenario, store ->
        await(scenario) { activity -> views(activity.window.decorView).filterIsInstance<HealthTrendChart>().singleOrNull()?.let {
            it.isEnabled && it.contentDescription.toString() != activity.getString(R.string.health_loading)
        } == true }
        store.change(HealthPrivacyOption.CONFIRMED_METRICS, false, store.policy().version)
        await(scenario) { tag(it, "health-privacy-blocked") != null }
        assertTrue(store.page().entries.any { it.scope.purpose == HealthAccessPurpose.TREND && it.outcome == HealthAccessOutcome.BLOCKED })
    }
    @Test fun openingDrillDownDirectlyDoesNotBypassTheTrendPermission() = screen(HealthTrendRecordsActivity::class.java, "worker", prepare = { store, intent ->
        val today = LocalDate.now()
        intent.putHealthTrend(HealthTrendSpec(HealthMetric.STEPS, today, today, ZoneId.systemDefault(), HealthMetric.STEPS.units.first()))
        store.change(HealthPrivacyOption.CONFIRMED_METRICS, false, store.policy().version)
    }) { scenario, store ->
        await(scenario) { tag(it, "health-privacy-blocked") != null }
        assertEquals(HealthAccessPurpose.TREND_RECORDS, store.page().entries.single().scope.purpose)
        assertEquals(HealthAccessOutcome.BLOCKED, store.page().entries.single().outcome)
    }
}
