package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.ContentValues
import android.content.Intent
import android.os.SystemClock
import android.view.View
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

    @Test fun nativeOverviewDoesNotShowOrDismissSourceIncidents() = fixture { names ->
        assumeFalse("Overview source UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        HealthRecordStore(context, names.records).use { it.saveHealthSyncCheckpoint(failed()) }
        ActivityScenario.launch<HealthCenterActivity>(Intent(context, HealthCenterActivity::class.java)
            .putHealthNavigationFixture(names)).use { scenario ->
            awaitTag(scenario, "health-overview-first")
            scenario.onActivity { activity ->
                assertNull(activity.body.findViewWithTag<View>("health-overview-attention"))
                assertNull(activity.body.findViewWithTag<View>("health-overview-sync-${scope.name}"))
            }
            HealthRecordStore(context, names.records).use {
                assertEquals(HealthSyncOutcome.NETWORK, it.healthSyncIncident(scope)?.outcome)
                assertEquals(0L, it.count())
            }
        }
    }

    private fun failed() = HealthSyncCheckpoint(scope, lastAttempt = now - 1000, lastSuccess = now - 60_000,
        outcome = HealthSyncOutcome.NETWORK)
    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun awaitTag(scenario: ActivityScenario<HealthCenterActivity>, tag: String) {
        val until = SystemClock.elapsedRealtime() + 12_000
        do {
            var ready = false
            scenario.onActivity { ready = it.body.findViewWithTag<View>(tag) != null }
            if (ready) return
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Missing native view: $tag")
    }
}
