package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.ContentValues
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthOverviewSourceDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private val now = System.currentTimeMillis()
    private val scope = HealthConnectScope.STEPS

    @Test fun sourceIssuesAreSeparateFromMeasurementsAndCorruptionRemainsVisible() = fixture { names ->
        HealthRecordStore(context, names.records).use { records ->
            records.saveHealthSyncCheckpoint(failed())
            fun snapshot() = HealthOverviewRepository.load(context, records, names, now, ZoneId.systemDefault())
            val initial = snapshot()
            assertFalse(initial.hasRecords)
            assertTrue(initial.metrics.all { it.record == null })
            val incident = (initial.attention.single() as HealthOverviewAttention.Connection).incident
            assertEquals(failed().lastSuccess, incident.lastSuccess)
            assertEquals(HealthSyncOutcome.NETWORK, incident.outcome)
            records.startHealthSyncAttempt(failed().copy(lastAttempt = now + 1, outcome = HealthSyncOutcome.RUNNING))
            assertEquals(incident, (snapshot().attention.single() as HealthOverviewAttention.Connection).incident)
            records.acknowledgeHealthSyncIncident(incident, now + 2)
            assertTrue(snapshot().attention.isEmpty())
            val checkpoint = records.healthSyncCheckpoint(scope)
            assertEquals(HealthSyncOutcome.RUNNING, checkpoint.outcome)
            records.saveHealthSyncCheckpoint(checkpoint.copy(lastAttempt = now + 3, lastSuccess = now + 3, outcome = HealthSyncOutcome.NO_NEW))
            assertTrue(snapshot().attention.isEmpty())
            records.saveHealthSyncCheckpoint(failed().copy(lastAttempt = now + 4))
            assertEquals(1, snapshot().attention.size)
            records.tableDatabase.update("health_sync_checkpoints", ContentValues().apply { put("payload", byteArrayOf(1, 2, 3)) },
                "source=?", arrayOf("connect-incident:${scope.name}"))
            val partial = snapshot()
            assertTrue(partial.connectionsUnavailable)
            assertTrue(partial.attention.isEmpty())
            assertFalse(partial.hasRecords)
        }
    }

    @Test fun nativeOverviewOpensExactCoverageAndRemovesRecoveredOrAcknowledgedIssues() = fixture { names ->
        assumeFalse("Overview source UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        HealthRecordStore(context, names.records).use { it.saveHealthSyncCheckpoint(failed()) }
        val tag = "health-overview-sync-${scope.name}"
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java)
            .putHealthNavigationFixture(names)).use { scenario ->
            awaitTag(scenario, tag)
            scenario.onActivity { activity ->
                assertNotNull(activity.body.findViewWithTag<View>("health-overview-first"))
                val labels = descendants(requireNotNull(activity.body.findViewWithTag<View>(tag)))
                    .filterIsInstance<TextView>().map { it.text.toString() }
                assertTrue(activity.getString(R.string.health_sync_network) in labels)
                assertTrue(activity.getString(R.string.health_sync_reminder_retention) in labels)
                assertTrue(labels.any { it.contains(activity.getString(scope.metric.titleResource())) })
            }
            val monitor = instrumentation.addMonitor(HealthSyncActivity::class.java.name, null, false)
            try {
                scenario.onActivity { assertTrue(it.body.findViewWithTag<View>("health-overview-sync-open-${scope.name}").performClick()) }
                val detail = requireNotNull(instrumentation.waitForMonitorWithTimeout(monitor, 10_000))
                assertEquals(scope.name, detail.intent.getStringExtra("health_sync_scope"))
                assertEquals(names.fixture, detail.intent.getStringExtra("health_sync_test_id"))
                instrumentation.runOnMainSync { detail.finish() }
            } finally { instrumentation.removeMonitor(monitor) }
            awaitTag(scenario, tag)
            HealthRecordStore(context, names.records).use {
                it.saveHealthSyncCheckpoint(failed().copy(lastAttempt = now + 1, lastSuccess = now + 1, outcome = HealthSyncOutcome.NO_NEW))
            }
            awaitTag(scenario, tag, present = false)
            HealthRecordStore(context, names.records).use { it.saveHealthSyncCheckpoint(failed().copy(lastAttempt = now + 2)) }
            awaitTag(scenario, tag)
            HealthRecordStore(context, names.records).use {
                it.acknowledgeHealthSyncIncident(requireNotNull(it.healthSyncIncident(scope)), now + 3)
            }
            awaitTag(scenario, tag, present = false)
            HealthRecordStore(context, names.records).use { assertEquals(0L, it.count()) }
        }
    }

    private fun failed() = HealthSyncCheckpoint(scope, lastAttempt = now - 1000, lastSuccess = now - 60_000,
        outcome = HealthSyncOutcome.NETWORK)
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup)
        (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) } else emptyList()
    private fun awaitTag(scenario: ActivityScenario<HealthCenterActivity>, tag: String, present: Boolean = true) {
        val until = SystemClock.elapsedRealtime() + 12_000
        do {
            var matches = false
            scenario.onActivity {
                matches = it.body.childCount > 0 && (it.body.findViewWithTag<View>(tag) != null) == present &&
                    (present || it.body.findViewWithTag<View>("health-overview-first") != null)
            }
            if (matches) return
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Unexpected visibility for $tag")
    }
}
