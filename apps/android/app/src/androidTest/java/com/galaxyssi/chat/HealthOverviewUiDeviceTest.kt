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

    @Test fun careSectionsShowPersistedItemsAndOpenTheExactFollowUp() = screen(seed = { names, now ->
        seedHealthOverviewCare(context, names, now, zone)
    }) { scenario, names ->
        val (issue, visit) = HealthCareStore(context, names.care).use { care ->
            val issue = care.page().items.single()
            issue to care.encounters(issue.id).items.single()
        }
        val due = issue.actions.single { it.description == "Synthetic overdue" }
        val key = "health-overview-action-${due.id}"
        await(scenario, key)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val monitor = instrumentation.addMonitor(HealthCareVisitFollowUpActivity::class.java.name, null, false)
        try {
            scenario.onActivity {
                assertTrue(requireNotNull(find(it, key)).isClickable)
                assertTrue(requireNotNull(find(it, "health-overview-concern-${issue.id}")).isClickable)
                assertTrue(requireNotNull(find(it, "health-overview-visit-${visit.id}")).performClick())
            }
            val screen = requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 5_000))
            assertEquals(issue.id, screen.intent.getStringExtra("health_care_id"))
            assertEquals(visit.id, screen.intent.getStringExtra("health_encounter_id"))
            assertEquals(names, screen.intent.healthNavigationDatabases())
            instrumentation.runOnMainSync { screen.finish() }
        } finally { instrumentation.removeMonitor(monitor) }
        await(scenario, key)
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        await(scenario, "health-overview-care-status")
        scenario.onActivity {
            assertNull(find(it, key))
            assertNull(find(it, "health-overview-visit-${visit.id}"))
            assertNull(find(it, "health-overview-concern-${issue.id}"))
        }
    }

    @Test fun populatedDashboardSeparatesRecentOlderAndMissingRecords() = screen(seed = { names, now ->
        HealthRecordStore(context, names.records).use {
            it.save(HealthDraft(values = mapOf("systolic" to "120", "diastolic" to "80"), measuredAt = now - 1000))
            it.save(HealthDraft(HealthMetric.STEPS, mapOf("steps" to "1000"), "steps", now - 2 * HealthReminderPolicy.DAY))
            assertTrue(it.save(HealthDraft(HealthMetric.TEMPERATURE, mapOf("temperature" to "36.5"),
                measuredAt = now - 1000)) is HealthSaveResult.Saved)
            assertTrue(it.save(HealthDraft(HealthMetric.OXYGEN_SATURATION, mapOf("spo2" to "98"),
                measuredAt = now - 1000)) is HealthSaveResult.Saved)
        }
    }) { scenario, _ ->
        await(scenario, "health-overview-BLOOD_PRESSURE-RECENT")
        scenario.onActivity {
            val overviewLabels = views(it.body).filterIsInstance<android.widget.TextView>().map { view -> view.text.toString() }
            listOf(R.string.health_overview_title, R.string.health_weekly_title,
                R.string.health_assistant_title, R.string.health_export_data_files,
                R.string.health_metric_temperature, R.string.health_metric_spo2,
                R.string.health_care_title, R.string.health_overview_attention).forEach { resource ->
                val label = it.getString(resource)
                assertFalse("Overview should not show $label", overviewLabels.any { text -> label in text })
            }
            assertNull(find(it, "health-overview-attention"))
            assertNull(find(it, "health-overview-proactive-care"))
            assertTrue(requireNotNull(it.window.decorView.findViewWithTag<View>("health-functions")).isClickable)
            assertNotNull(find(it, "health-overview-STEPS-STALE"))
            assertNotNull(find(it, "health-overview-RESTING_HEART_RATE-MISSING"))
            assertNull(find(it, "health-overview-extra-TEMPERATURE"))
            assertNull(find(it, "health-overview-extra-OXYGEN_SATURATION"))
            assertNull(find(it, "health-overview-first"))
        }
        scenario.moveToState(Lifecycle.State.CREATED)
        scenario.onActivity { assertEquals(0, it.body.childCount) }
        scenario.moveToState(Lifecycle.State.RESUMED)
        await(scenario, "health-overview-BLOOD_PRESSURE-RECENT")
    }
    @Test fun abnormalReportRowsUseInlineValuesAndKeepNativeShortcutsBelowTheScrollArea() = screen(seed = { names, now ->
        HealthRecordStore(context, names.records).use { store ->
            val id = UUID.randomUUID().toString()
            val evidence = HealthEvidence(id, id, "glucose", "a".repeat(64), 1, "synthetic", confirmed = true)
            assertTrue(store.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"), "mmol/L",
                now - 1000, condition = "fasting", reference = "3.9-6.1", evidence = evidence)) is HealthSaveResult.Saved)
            assertTrue(store.save(HealthDraft(HealthMetric.CHOLESTEROL, mapOf("cholesterol" to "6.2"), "mmol/L",
                now - 2000, reference = "3-5")) is HealthSaveResult.Saved)
            assertTrue(store.save(HealthDraft(HealthMetric.CHOLESTEROL, mapOf("cholesterol" to "4.5"), "mmol/L",
                now - 1500, reference = "3-5")) is HealthSaveResult.Saved)
        }
    }) { scenario, names ->
        await(scenario, "health-overview-GLUCOSE-RECENT")
        scenario.onActivity { activity ->
            val list = requireNotNull(find(activity, "health-overview-metrics")) as ViewGroup
            assertNotNull(list.getChildAt(0).findViewWithTag<View>("health-overview-GLUCOSE-RECENT"))
            assertNull(find(activity, "health-overview-CHOLESTEROL-RECENT"))
            val range = requireNotNull(find(activity, "health-overview-range-GLUCOSE")) as android.widget.TextView
            assertTrue(range.text.contains(activity.getString(R.string.health_overview_report_range)))
            assertTrue(range.text.contains("3.9-6.1 mmol/L"))
            val value = (requireNotNull(find(activity, "health-overview-value-GLUCOSE")) as android.widget.TextView).text as android.text.Spanned
            assertEquals(activity.getColor(R.color.health_overview_orange),
                value.getSpans(0, 3, android.text.style.ForegroundColorSpan::class.java).single().foregroundColor)
            val footer = requireNotNull(find(activity, "health-overview-bottom-actions"))
            assertSame(footer, activity.body.getChildAt(activity.body.childCount - 1))
            assertNotNull(activity.body.getChildAt(0) as? android.widget.ScrollView)
            val shortcuts = views(footer).filter { it.isClickable }.map { it.tag }
            assertEquals(listOf("health-overview-photo", "health-overview-manual", "health-overview-import", "health-overview-sources"), shortcuts)
            assertTrue(requireNotNull(find(activity, "health-overview-GLUCOSE-RECENT")).performClick())
            assertEquals(View.VISIBLE, requireNotNull(find(activity, "health-overview-detail-GLUCOSE")).visibility)
        }
        HealthPrivacyStore(context, names.privacy).use {
            it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version)
        }
        await(scenario, "health-overview-BLOOD_PRESSURE-MISSING")
        scenario.onActivity { assertNull(find(it, "health-overview-GLUCOSE-RECENT")) }
    }
    @Test fun firstUseKeepsPendingRecognitionOutOfTheOverview() = screen(seed = { names, now ->
        overviewOcrJob(context, names, now - 1000)
    }) { scenario, names ->
        await(scenario, "health-first-existing")
        scenario.onActivity {
            assertNotNull(find(it, "health-overview-first"))
            assertNotNull(find(it, "health-first-no-analysis"))
            assertNull(find(it, "health-overview-attention"))
            assertNull(find(it, "health-overview-review-OCR"))
            assertNull(find(it, "health-overview-BLOOD_PRESSURE-MISSING"))
            assertNull(find(it, "health-overview-BLOOD_PRESSURE-RECENT"))
        }
        HealthRecordStore(context, names.records).use {
            assertEquals(HealthOverviewReviewKind.OCR, HealthOverviewRepository.pendingReviews(context, it, names, limit = 4).single().kind)
        }
    }
    @Test fun firstUseOffersOptionalSourcesAndAFilePickerWithoutAnImportHub() = screen { scenario, _ ->
        await(scenario, "health-first-existing")
        scenario.onActivity {
            listOf("health-overview-photo", "health-overview-manual", "health-overview-import", "health-overview-sources",
                "health-first-add", "health-first-existing").forEach { key -> assertTrue(requireNotNull(find(it, key)).isClickable) }
            assertEquals(View.GONE, views(it.window.decorView).single { view -> view.tag == "health-reminders" }.visibility)
        }
        cancelPicker(scenario, "health-first-existing")
        scenario.recreate()
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
        }
        cancelPicker(scenario, "health-overview-import")
        await(scenario, "health-overview-BLOOD_PRESSURE-RECENT")
    }
    private fun cancelPicker(scenario: ActivityScenario<HealthCenterActivity>, tag: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val launched = java.util.concurrent.atomic.AtomicReference<Intent>()
        val monitor = object : android.app.Instrumentation.ActivityMonitor() {
            override fun onStartActivity(intent: Intent): android.app.Instrumentation.ActivityResult? {
                if (intent.action != Intent.ACTION_OPEN_DOCUMENT) return null
                launched.set(Intent(intent))
                return android.app.Instrumentation.ActivityResult(android.app.Activity.RESULT_CANCELED, null)
            }
        }
        instrumentation.addMonitor(monitor)
        try {
            scenario.onActivity { assertTrue(requireNotNull(find(it, tag)).performClick()) }
            val until = android.os.SystemClock.elapsedRealtime() + 10_000
            while (launched.get() == null && android.os.SystemClock.elapsedRealtime() < until) android.os.SystemClock.sleep(40)
            val picker = requireNotNull(launched.get())
            assertTrue(picker.getBooleanExtra(Intent.EXTRA_ALLOW_MULTIPLE, false))
            assertTrue("application/pdf" in requireNotNull(picker.getStringArrayExtra(Intent.EXTRA_MIME_TYPES)))
        } finally { instrumentation.removeMonitor(monitor) }
    }
    @Test fun revocationKeepsTheRawSleepRecordCard() = screen(seed = { names, now ->
        seedSleep(names, now)
        HealthCareStore(context, names.care).use { it.settings() }
    }) { scenario, names ->
        await(scenario, "health-overview-SLEEP_DURATION-RECENT")
        HealthPrivacyStore(context, names.privacy).use {
            it.change(HealthPrivacyOption.CONFIRMED_METRICS, false, it.policy().version)
        }
        await(scenario, "health-overview-care-status")
        scenario.onActivity {
            assertNull(find(it, "health-overview-change"))
            assertNotNull(find(it, "health-overview-SLEEP_DURATION-RECENT"))
        }
    }
}
