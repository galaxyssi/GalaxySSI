package com.galaxyssi.chat

import android.app.Activity
import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.time.LocalDate
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthComparisonUiDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun views(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { views(view.getChildAt(it)) } else emptyList()
    private fun <T : Activity> await(scenario: ActivityScenario<T>, tag: String) {
        val deadline = SystemClock.elapsedRealtime() + 15_000
        do {
            var ready = false
            scenario.onActivity { ready = views(it.window.decorView).any { it.tag == tag } }
            if (ready) return
            SystemClock.sleep(40)
        } while (SystemClock.elapsedRealtime() < deadline)
        fail("Missing comparison view: $tag")
    }
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        assumeFalse(context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { context.deleteDatabase(names.activity); clearHealthOverviewFixture(context, names) }
    }
    @Test fun existingTodayTilesKeepTheirOriginalControlsWithSeparateComparisonEntry() = fixture { names ->
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java).putHealthNavigationFixture(names)).use { screen ->
            await(screen, "health-activity-comparison")
            screen.onActivity { activity ->
                val all = views(activity.window.decorView)
                val tiles = all.single { it.tag == "health-overview-activity" }
                assertFalse(views(tiles).any { it.tag == "health-activity-comparison" })
                assertTrue(all.any { it.tag == "health-overview-step-goal" })
                assertTrue(all.any { it.tag == "health-overview-cycling" })
            }
        }
    }
    @Test fun activityComparisonLoadsAndClearsDecryptedViewsInBackground() = fixture { names ->
        HealthActivityHistoryStore(context, names.activity).use { store ->
            repeat(35) { day ->
                val date = LocalDate.now().minusDays(day.toLong() + 1)
                if (day != 5) store.save(HealthActivityKind.STEPS, date, 2500L + (day % 6) * 700L)
                store.save(HealthActivityKind.CYCLING, date, 600_000L + (day % 4) * 300_000L)
            }
        }
        ActivityScenario.launch<HealthActivityComparisonActivity>(Intent(context, HealthActivityComparisonActivity::class.java).putHealthNavigationFixture(names)).use { screen ->
            await(screen, "health-activity-chart")
            instrumentation.waitForIdleSync()
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                File(context.getExternalFilesDir(null), "health-activity-comparison-test.png").outputStream().use {
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                }; bitmap.recycle()
            }
            screen.moveToState(Lifecycle.State.CREATED)
            screen.onActivity { activity -> assertFalse(views(activity.window.decorView).any { it.tag == "health-activity-chart" }) }
            screen.moveToState(Lifecycle.State.RESUMED); await(screen, "health-activity-chart")
        }
    }
    @Test fun emptyBatchPickerDoesNotShowInventedMeasurements() = fixture { names ->
        ActivityScenario.launch<HealthMeasurementBatchesActivity>(Intent(context, HealthMeasurementBatchesActivity::class.java)
            .putHealthNavigationFixture(names).putExtra("health_select_batch", true)).use { screen ->
            val deadline = SystemClock.elapsedRealtime() + 15_000
            var found = false
            do {
                screen.onActivity { activity -> found = views(activity.window.decorView).filterIsInstance<TextView>().any {
                    it.text.toString() == activity.getString(R.string.health_no_records)
                } }
                if (!found) SystemClock.sleep(40)
            } while (!found && SystemClock.elapsedRealtime() < deadline)
            assertTrue(found)
        }
    }
    @Test fun twoBatchResultsUseSeparateColumnsOrStackAtNarrowWidths() = fixture { names ->
        val now = System.currentTimeMillis()
        val reports = HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            (0..1).map { index ->
                val job = HealthImportJob(UUID.randomUUID().toString(), "content://health.test/ui-$index", now - 2000 + index,
                    name = "synthetic-$index.pdf")
                originals.createJob(job)
                job to originals.importOriginal(job.id, "synthetic report $index".byteInputStream(), job.name, "application/pdf", "file")
            }
        }
        HealthRecordStore(context, names.records).use { records ->
            reports.forEachIndexed { index, (job, original) ->
                assertTrue(records.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to if (index == 0) "5.1" else "6.3"),
                    "mmol/L", now - (index + 1) * 86_400_000L, "fasting", reference = "4-6",
                    evidence = HealthEvidence(original.id, job.id, "glucose", original.sha256, 1, "synthetic", confirmed = true))) is HealthSaveResult.Saved)
            }
        }
        ActivityScenario.launch<HealthMeasurementBatchesActivity>(Intent(context, HealthMeasurementBatchesActivity::class.java)
            .putHealthNavigationFixture(names).putExtra("health_batch", HealthMeasurementBatches.keyFor(reports[0].first))).use { screen ->
            screen.onActivity { activity ->
                HealthMeasurementBatchesActivity::class.java.getDeclaredField("b").apply { isAccessible = true }
                    .set(activity, HealthMeasurementBatches.keyFor(reports[1].first))
                HealthMeasurementBatchesActivity::class.java.getDeclaredMethod("refresh").apply { isAccessible = true }.invoke(activity)
            }
            val deadline = SystemClock.elapsedRealtime() + 15_000
            var ready = false
            do {
                screen.onActivity { activity -> ready = views(activity.window.decorView).filterIsInstance<TextView>().any { it.text.toString() == "B" } }
                if (!ready) SystemClock.sleep(40)
            } while (!ready && SystemClock.elapsedRealtime() < deadline)
            assertTrue(ready); instrumentation.waitForIdleSync()
            screen.onActivity { activity ->
                val all = views(activity.window.decorView).filterIsInstance<TextView>()
                val a = all.single { it.text.toString() == "A" }; val b = all.single { it.text.toString() == "B" }
                val ap = IntArray(2); val bp = IntArray(2); a.getLocationOnScreen(ap); b.getLocationOnScreen(bp)
                val stack = activity.resources.configuration.fontScale >= 1.3f || activity.resources.configuration.screenWidthDp < 344
                if (stack) assertTrue(ap[1] < bp[1]) else { assertTrue(ap[0] < bp[0]); assertEquals(ap[1], bp[1]) }
            }
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                File(context.getExternalFilesDir(null), "health-batch-comparison-test.png").outputStream().use {
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                }; bitmap.recycle()
            }
        }
    }
}
