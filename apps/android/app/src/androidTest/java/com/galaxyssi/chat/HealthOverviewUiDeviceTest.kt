package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Context
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

class HealthOverviewUiDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val zone get() = ZoneId.systemDefault()
    private fun screen(seed: (HealthOverviewDatabases, Long) -> Unit = { _, _ -> },
        test: (ActivityScenario<HealthCenterActivity>, HealthOverviewDatabases) -> Unit) {
        assumeFalse("Health overview UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        var worker: ExecutorService? = null
        try {
            seed(names, System.currentTimeMillis())
            val intent = Intent(context, HealthCenterActivity::class.java).putExtra("health_overview_test_id", names.fixture)
            ActivityScenario.launch<HealthCenterActivity>(intent).use { scenario -> try { test(scenario, names) } finally {
                scenario.onActivity {
                    worker = HealthCenterActivity::class.java.getDeclaredField("worker").apply { isAccessible = true }.get(it) as ExecutorService
                }
            } }
        } finally { worker?.awaitTermination(10, TimeUnit.SECONDS); clearHealthOverviewFixture(context, names) }
    }
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun find(activity: HealthCenterActivity, tag: String) = views(activity.body).firstOrNull { it.tag == tag }
    private fun await(scenario: ActivityScenario<HealthCenterActivity>, tag: String) {
        val until = SystemClock.elapsedRealtime() + 15_000
        do {
            var ready = false
            scenario.onActivity { ready = find(it, tag) != null }
            if (ready) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Missing native view: $tag")
    }
    private fun seedSleep(names: HealthOverviewDatabases, now: Long) {
        HealthRecordStore(context, names.records).use { seedHealthSleep(it, now, zone) }
        HealthReminderStore(context, names.reminders).use {
            it.save(it.settings().copy(sleepChanges = true), now)
            assertTrue(HealthSleepAlertEngine.evaluate(context, it, now, zone, names.records, names.privacy))
        }
    }

    @Test fun populatedDashboardSeparatesRecentOlderAndMissingRecords() = screen(seed = { names, now ->
        HealthRecordStore(context, names.records).use {
            it.save(HealthDraft(values = mapOf("systolic" to "120", "diastolic" to "80"), measuredAt = now - 1000))
            it.save(HealthDraft(HealthMetric.STEPS, mapOf("steps" to "1000"), "steps", now - 2 * HealthReminderPolicy.DAY))
        }
    }) { scenario, _ ->
        await(scenario, "health-overview-BLOOD_PRESSURE-RECENT")
        scenario.onActivity {
            assertNotNull(find(it, "health-overview-STEPS-STALE"))
            assertNotNull(find(it, "health-overview-RESTING_HEART_RATE-MISSING"))
            assertNotNull(find(it, "health-overview-missing"))
            assertNull(find(it, "health-overview-first"))
        }
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertEquals(0, it.body.childCount) }
        scenario.moveToState(Lifecycle.State.RESUMED)
        await(scenario, "health-overview-BLOOD_PRESSURE-RECENT")
    }
    @Test fun firstUseCanShowPendingRecognitionWithoutInventingAReading() = screen(seed = { names, now ->
        overviewOcrJob(context, names, now - 1000)
    }) { scenario, _ ->
        await(scenario, "health-overview-review-OCR")
        scenario.onActivity {
            assertNotNull(find(it, "health-overview-first"))
            assertNotNull(find(it, "health-first-no-analysis"))
            assertNull(find(it, "health-overview-BLOOD_PRESSURE-MISSING"))
            assertNull(find(it, "health-overview-BLOOD_PRESSURE-RECENT"))
        }
    }
    @Test fun firstUseOffersOptionalSourcesAndReturnsFromTheImportCenterAfterRecreation() = screen { scenario, _ ->
        await(scenario, "health-first-existing")
        scenario.onActivity {
            listOf("health-overview-photo", "health-overview-manual", "health-overview-import", "health-overview-sources",
                "health-first-add", "health-first-existing").forEach { key -> assertTrue(requireNotNull(find(it, key)).isClickable) }
            assertEquals(View.GONE, views(it.window.decorView).single { view -> view.tag == "health-reminders" }.visibility)
            assertTrue(requireNotNull(find(it, "health-first-existing")).performClick())
            assertNotNull(find(it, "health-import-center"))
            listOf("health-import-camera", "health-import-report", "health-import-table", "health-import-restore")
                .forEach { key -> assertTrue(requireNotNull(find(it, key)).isClickable) }
            val retention = find(it, "health-import-keep-original") as android.widget.Switch
            assertTrue(retention.isChecked)
            assertTrue(retention.performClick())
            assertFalse(retention.isChecked)
        }
        scenario.recreate()
        await(scenario, "health-import-restore")
        scenario.onActivity { assertFalse((find(it, "health-import-keep-original") as android.widget.Switch).isChecked) }
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        if (InstrumentationRegistry.getArguments().getString("health_retention_screenshot") == "true") {
            instrumentation.waitForIdleSync()
            instrumentation.uiAutomation.takeScreenshot()?.let { image ->
                try {
                    java.io.File(context.getExternalFilesDir(null), "health-original-retention.png").outputStream().use {
                        image.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                    }
                } finally { image.recycle() }
            }
        }
        scenario.onActivity { it.onBackPressed() }
        await(scenario, "health-overview-first")
        scenario.onActivity {
            assertNotNull(find(it, "health-first-no-analysis"))
            assertNull(find(it, "health-import-center"))
        }
    }
    @Test fun firstConfirmedRecordReplacesOnboardingWithoutReopeningThePage() = screen { scenario, names ->
        await(scenario, "health-overview-first")
        HealthRecordStore(context, names.records).use {
            it.save(HealthDraft(values = mapOf("systolic" to "120", "diastolic" to "80"), measuredAt = System.currentTimeMillis() - 1000))
        }
        await(scenario, "health-overview-BLOOD_PRESSURE-RECENT")
        scenario.onActivity {
            assertNull(find(it, "health-overview-first"))
            assertEquals(View.VISIBLE, views(it.window.decorView).single { view -> view.tag == "health-reminders" }.visibility)
            assertTrue(requireNotNull(find(it, "health-overview-import")).performClick())
            assertNotNull(find(it, "health-import-restore"))
        }
    }
    @Test fun revocationClearsVisibleDerivedAlertButKeepsRawRecordCard() = screen(seed = ::seedSleep) { scenario, names ->
        await(scenario, "health-overview-change")
        HealthPrivacyStore(context, names.privacy).use {
            it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version)
        }
        await(scenario, "health-overview-privacy-blocked")
        scenario.onActivity {
            assertNull(find(it, "health-overview-change"))
            assertNotNull(find(it, "health-overview-SLEEP_DURATION-RECENT"))
        }
    }
    @Test fun attentionOrderPreferencePersistsAcrossRecreation() = screen(seed = { names, now ->
        seedSleep(names, now); overviewOcrJob(context, names, now - 2000)
    }) { scenario, names ->
        await(scenario, "health-overview-change")
        fun index(activity: HealthCenterActivity, tag: String) = views(activity.body).indexOfFirst { it.tag == tag }
        scenario.onActivity {
            assertTrue(index(it, "health-overview-change") < index(it, "health-overview-review-OCR"))
            it.getSharedPreferences(names.prefs, Context.MODE_PRIVATE).edit().putString("order", HealthOverviewOrder.REVIEW_FIRST.name).commit()
        }
        scenario.recreate()
        await(scenario, "health-overview-review-OCR")
        scenario.onActivity { assertTrue(index(it, "health-overview-review-OCR") < index(it, "health-overview-change")) }
    }
}
