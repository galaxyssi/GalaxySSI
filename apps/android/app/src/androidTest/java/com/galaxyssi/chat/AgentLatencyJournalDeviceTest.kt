package com.galaxyssi.chat

import android.os.SystemClock
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.galaxyssi.chat.metrics.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class AgentLatencyJournalDeviceTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test fun metricRowShowsAllThreePercentilesWithoutChangingOtherRows() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val values = activity.getString(R.string.agent_latency_values,
                    agentLatencyDisplayValue(50.0), agentLatencyDisplayValue(95000.0),
                    agentLatencyDisplayValue(2592000000.0))
                val title = activity.getString(R.string.agent_latency_first)
                val counts = activity.getString(R.string.agent_latency_counts, 100, 2, 1)
                val row = activity.featureValueRow(title, counts, R.drawable.ic_settings_diagnostics,
                    values, valueMaxLines = 3) as LinearLayout
                val width = (360 * activity.resources.displayMetrics.density).toInt()
                row.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED))
                row.layout(0, 0, width, row.measuredHeight)
                val value = row.getChildAt(row.childCount - 1) as TextView
                assertEquals(3, value.maxLines)
                assertEquals(3, value.layout.lineCount)
                for (line in 0..2) {
                    assertEquals(0, value.layout.getEllipsisCount(line))
                    assertTrue(value.layout.getLineWidth(line) <= value.width)
                }
                assertTrue(value.bottom <= row.height)
                val ordinary = activity.featureValueRow(title, counts, R.drawable.ic_settings_diagnostics, "1") as LinearLayout
                assertEquals(1, (ordinary.getChildAt(ordinary.childCount - 1) as TextView).maxLines)
            }
        }
    }

    @Test fun diskBackpressureDoesNotBlockTimingProducer() {
        val directory = File(context.cacheDir, "agent-latency-test-${UUID.randomUUID()}").apply { mkdirs() }
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        try {
            AgentTimingJournal(File(directory, "timings.jsonl"), queueLimit = 4, batchWriter = {
                entered.countDown(); release.await(10, TimeUnit.SECONDS)
            }).use { journal ->
                val tracer = AgentLatencyTracer(journal, SystemClock::elapsedRealtimeNanos)
                tracer.record("start", "phone_publish_started")
                assertTrue(entered.await(5, TimeUnit.SECONDS))
                val samples = (1..1000).map { index ->
                    val started = SystemClock.elapsedRealtimeNanos()
                    tracer.record("request-$index", "phone_publish_started")
                    (SystemClock.elapsedRealtimeNanos() - started) / 1_000_000.0
                }.sorted()
                assertTrue("timing append blocked behind disk", samples[949] < 100)
                assertTrue((journal.health()["dropped_events"] as Long) >= 996)
                val report = JSONObject()
                    .put("scope", "diagnostic_producer_under_blocked_writer")
                    .put("synthetic_workload", true).put("samples", samples.size)
                    .put("p50_ms", samples[499]).put("p95_ms", samples[949]).put("p99_ms", samples[989])
                    .put("dropped_events", journal.health()["dropped_events"])
                File(context.getExternalFilesDir(null), "agent-latency-device-report.json").writeText(report.toString(2))
                release.countDown()
            }
        } finally { release.countDown(); directory.deleteRecursively() }
    }

    @Test fun savedDiagnosticPointsDoNotJoinAcrossProcessClockDomains() {
        val directory = File(context.cacheDir, "agent-latency-reopen-${UUID.randomUUID()}").apply { mkdirs() }
        try {
            val file = File(directory, "timings.jsonl")
            AgentTimingJournal(file).use { journal ->
                AgentLatencyTracer(journal, monotonicNs = { 100_000 }, clockId = "a".repeat(32))
                    .record("same-request", "phone_publish_started")
            }
            AgentTimingJournal(file).use { journal ->
                AgentLatencyTracer(journal, monotonicNs = { 200_000 }, clockId = "b".repeat(32))
                    .record("same-request", "phone_first_output_visible")
                journal.close()
                assertEquals(2, journal.snapshot().size)
                val metric = AgentLatencyContract.summarize(journal.snapshot())
                    .getValue("phone_connector_first_visible_ms")
                assertEquals(0, metric.count)
                assertEquals(1, metric.incomplete)
                assertNull(metric.p95Ms)
                assertFalse(file.readText().contains("same-request"))
            }
        } finally { directory.deleteRecursively() }
    }
}
