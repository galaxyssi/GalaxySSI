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
                assertEquals("health-overview-date-actions", (all.single { it.tag == "health-activity-comparison" }.parent as View).tag)
                assertTrue(all.any { it.tag == "health-overview-step-goal" })
                assertTrue(all.any { it.tag == "health-overview-cycling" })
                val metrics = all.single { it.tag == "health-overview-metrics" }
                val records = all.single { it.tag == "health-overview-all-records" }
                val top = IntArray(2); val bottom = IntArray(2); metrics.getLocationOnScreen(top); records.getLocationOnScreen(bottom)
                assertTrue(bottom[1] >= top[1] + metrics.height)
            }
        }
    }
    @Test fun activityComparisonLoadsAndClearsDecryptedViewsInBackground() = fixture { names ->
        HealthActivityHistoryStore(context, names.activity).use { store ->
            repeat(35) { day ->
                val date = LocalDate.now().minusDays(day.toLong())
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
    @Test fun activityPresetsIncludeTodayAndBothKindsUseTheCompactLayout() = fixture { names ->
        HealthActivityHistoryStore(context, names.activity).use { store ->
            store.save(HealthActivityKind.STEPS, LocalDate.now(), 1234)
            store.save(HealthActivityKind.CYCLING, LocalDate.now(), 5_400_000)
        }
        ActivityScenario.launch<HealthActivityComparisonActivity>(Intent(context, HealthActivityComparisonActivity::class.java)
            .putHealthNavigationFixture(names)).use { screen ->
            listOf(R.string.health_trend_7, R.string.health_trend_30, R.string.health_trend_90).forEach { preset ->
                await(screen, "health-activity-chart")
                screen.onActivity { activity -> views(activity.window.decorView).filterIsInstance<TextView>()
                    .single { it.text.toString() == activity.getString(preset) }.performClick() }
                await(screen, "health-activity-chart")
                screen.onActivity { activity ->
                    val all = views(activity.window.decorView)
                    val total = all.single { it.tag == "health-activity-total" } as TextView
                    assertEquals(java.text.NumberFormat.getIntegerInstance().format(1234) + " " + activity.getString(R.string.health_activity_steps_unit), total.text.toString())
                    assertCompactActivityLayout(activity, all)
                }
            }
            screen.onActivity { activity -> views(activity.window.decorView).filterIsInstance<TextView>()
                .single { it.text.toString() == activity.getString(R.string.health_cycling_today) }.performClick() }
            await(screen, "health-activity-chart")
            screen.onActivity { activity ->
                val all = views(activity.window.decorView)
                val total = all.single { it.tag == "health-activity-total" } as TextView
                assertEquals("90 " + activity.getString(R.string.health_activity_minutes), total.text.toString())
                assertCompactActivityLayout(activity, all)
            }
            screen.recreate(); await(screen, "health-activity-chart")
            screen.onActivity { activity ->
                val total = views(activity.window.decorView).single { it.tag == "health-activity-total" } as TextView
                assertEquals("90 " + activity.getString(R.string.health_activity_minutes), total.text.toString())
            }
        }
    }
    @Test fun emptyActivityHistoryShowsUnknownInsteadOfZeroForBothKinds() = fixture { names ->
        ActivityScenario.launch<HealthActivityComparisonActivity>(Intent(context, HealthActivityComparisonActivity::class.java)
            .putHealthNavigationFixture(names)).use { screen ->
            listOf(R.string.health_overview_today_steps, R.string.health_cycling_today).forEach { label ->
                await(screen, "health-activity-chart")
                screen.onActivity { activity -> views(activity.window.decorView).filterIsInstance<TextView>()
                    .single { it.text.toString() == activity.getString(label) }.performClick() }
                await(screen, "health-activity-chart")
                screen.onActivity { activity -> assertEquals("\u2014", (views(activity.window.decorView)
                    .single { it.tag == "health-activity-total" } as TextView).text.toString()) }
            }
        }
    }
    private fun assertCompactActivityLayout(activity: Activity, all: List<View>) {
        val texts = all.filterIsInstance<TextView>().map { it.text.toString() }
        listOf(R.string.health_activity_current, R.string.health_activity_previous, R.string.health_activity_missing,
            R.string.health_trend_chart_data).forEach { assertFalse(texts.contains(activity.getString(it))) }
        assertFalse(texts.any { Regex(".*\\d{4}-\\d{2}-\\d{2}.*").matches(it) })
        assertTrue(all.single { it.tag == "health-activity-chart" }.isClickable)
    }
    @Test fun emptyPeriodComparisonDoesNotShowInventedMeasurements() = fixture { names ->
        ActivityScenario.launch<HealthMeasurementPeriodsActivity>(Intent(context, HealthMeasurementPeriodsActivity::class.java)
            .putHealthNavigationFixture(names)).use { screen ->
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
    @Test fun twoSamplingPeriodsUseSeparateColumnsOrStackAtNarrowWidths() = fixture { names ->
        val now = System.currentTimeMillis()
        val reports = HealthOriginalStore(context, names.originals, names.originalRoot(context)).use { originals ->
            (0..1).map { index ->
                val job = HealthImportJob(UUID.randomUUID().toString(), "content://health.test/ui-$index", now - 2000 + index,
                    name = "synthetic-$index.pdf")
                originals.createJob(job)
                job to originals.importOriginal(job.id, "synthetic report $index".byteInputStream(), job.name, "application/pdf", "file")
            }
        }
        val period = HealthMeasurementPeriod.of(HealthMeasurementPeriodKind.WEEK, LocalDate.now())
        val sampleTimes = listOf(period.first, period.first.minusDays(1)).map {
            it.atStartOfDay(java.time.ZoneId.systemDefault()).toInstant().toEpochMilli()
        }
        HealthRecordStore(context, names.records).use { records ->
            reports.forEachIndexed { index, (job, original) ->
                assertTrue(records.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to if (index == 0) "5.1" else "6.3"),
                    "mmol/L", sampleTimes[index], "fasting", reference = "4-6",
                    evidence = HealthEvidence(original.id, job.id, "glucose", original.sha256, 1, "synthetic", confirmed = true))) is HealthSaveResult.Saved)
            }
        }
        ActivityScenario.launch<HealthMeasurementPeriodsActivity>(Intent(context, HealthMeasurementPeriodsActivity::class.java)
            .putHealthNavigationFixture(names).putExtra("health_period", period.key)).use { screen ->
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
                File(context.getExternalFilesDir(null), "health-period-comparison-test.png").outputStream().use {
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                }; bitmap.recycle()
            }
        }
    }
    @Test fun recordsExpandInlineAndPaginateWithoutReplacingTheOverview() = fixture { names ->
        val now = System.currentTimeMillis()
        HealthRecordStore(context, names.records).use { store ->
            repeat(65) { index -> store.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "70"), "kg", now - index * 60_000L)) }
            store.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"), "mmol/L", now - 1000, "fasting", reference = "4-6"))
            store.save(HealthDraft(HealthMetric.LDL, mapOf("ldl" to "3.45"), "mmol/L", now - 2000, reference = "<3.37"))
            store.save(HealthDraft(HealthMetric.HDL, mapOf("hdl" to "1.12"), "mmol/L", now - 2000, reference = ">1.03"))
            store.save(HealthDraft(HealthMetric.TRIGLYCERIDES, mapOf("triglycerides" to "1.68"), "mmol/L", now - 2000, reference = "<1.70"))
            store.save(HealthDraft(values = mapOf("systolic" to "119", "diastolic" to "77"), measuredAt = now - 2000))
        }
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java).putHealthNavigationFixture(names)).use { screen ->
            await(screen, "health-overview-all-records")
            instrumentation.waitForIdleSync(); SystemClock.sleep(150)
            instrumentation.uiAutomation.takeScreenshot()?.let { bitmap ->
                File(context.getExternalFilesDir(null), "health-period-overview-test.png").outputStream().use {
                    bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
                }; bitmap.recycle()
            }
            screen.onActivity { activity -> views(activity.window.decorView).single { it.tag == "health-overview-all-records" }.performClick() }
            await(screen, "health-expanded-next-page")
            var firstIds = emptySet<Any>()
            screen.onActivity { activity ->
                val all = views(activity.window.decorView)
                firstIds = all.mapNotNull { it.tag?.takeIf { tag -> tag.toString().startsWith("health-expanded-record-") } }.toSet()
                assertEquals(30, firstIds.size); assertTrue(all.any { it.tag == "health-overview-activity" })
                all.single { it.tag == "health-expanded-next-page" }.performClick()
            }
            await(screen, "health-expanded-next-page")
            var secondIds = emptySet<Any>()
            screen.onActivity { activity ->
                val all = views(activity.window.decorView)
                secondIds = all.mapNotNull { it.tag?.takeIf { tag -> tag.toString().startsWith("health-expanded-record-") } }.toSet()
                assertEquals(30, secondIds.size); assertTrue(firstIds.intersect(secondIds).isEmpty())
                all.first { it.tag in secondIds }.performClick()
                activity.onBackPressed()
            }
            await(screen, "health-expanded-next-page")
            screen.onActivity { activity ->
                val all = views(activity.window.decorView)
                val returned = all.mapNotNull { it.tag?.takeIf { tag -> tag.toString().startsWith("health-expanded-record-") } }.toSet()
                assertEquals(secondIds, returned)
                all.single { it.tag == "health-overview-all-records" }.performClick()
                assertFalse(views(activity.window.decorView).any { it.tag == "health-overview-expanded-records" })
            }
        }
    }
    @Test fun selectedSamplingMonthAndAbnormalFilterRemainOnTheOverview() = fixture { names ->
        val now = System.currentTimeMillis(); val day = LocalDate.now()
        HealthRecordStore(context, names.records).use { store ->
            store.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "6.3"), "mmol/L", now - 1000, "fasting", reference = "4-6"))
            store.save(HealthDraft(HealthMetric.WEIGHT, mapOf("weight" to "70"), "kg", now - 2000))
        }
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java).putHealthNavigationFixture(names)).use { screen ->
            await(screen, "health-overview-all-records")
            screen.onActivity { it.setMeasurementPeriod(HealthMeasurementPeriod.of(HealthMeasurementPeriodKind.MONTH, day)) }
            await(screen, "health-measurement-abnormal-filter")
            screen.onActivity { (views(it.window.decorView).single { v -> v.tag == "health-measurement-abnormal-filter" } as android.widget.CheckBox).isChecked = true }
            await(screen, "health-overview-all-records")
            screen.onActivity { activity ->
                assertEquals(HealthMeasurementPeriodKind.MONTH, activity.measurementPeriod?.kind)
                val metricList = views(activity.window.decorView).single { it.tag == "health-overview-metrics" }
                assertTrue(views(metricList).any { it.tag?.toString()?.startsWith("health-overview-GLUCOSE-") == true })
                assertFalse(views(metricList).any { it.tag?.toString()?.startsWith("health-overview-WEIGHT-") == true })
            }
        }
    }
}
