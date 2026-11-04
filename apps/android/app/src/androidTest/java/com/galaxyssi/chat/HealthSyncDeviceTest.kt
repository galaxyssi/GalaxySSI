package com.galaxyssi.chat

import android.app.KeyguardManager
import android.content.Intent
import android.os.SystemClock
import android.view.View
import android.widget.TextView
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import java.io.IOException
import java.net.UnknownHostException
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Assume.assumeFalse
import org.junit.Test

class HealthSyncDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val now = Instant.parse("2026-10-04T10:05:00Z").toEpochMilli()
    private val zone = ZoneId.of("UTC")
    private val pressure = HealthConnectScope.BLOOD_PRESSURE

    private class Gateway(private val scope: HealthConnectScope) : HealthSyncGateway {
        var permissions = setOf(scope.permission)
        var nextToken = "private-provider-token"
        val fetched = arrayListOf<String>()
        val snapshots = arrayListOf<Triple<Instant, Instant, String>>()
        val stepDays = arrayListOf<Pair<LocalDate, ZoneId>>()
        var tokenCalls = 0
        var snapshotRead: (String) -> HealthSyncSnapshotPage = { HealthSyncSnapshotPage(emptySequence(), "") }
        var changesRead: suspend (String) -> HealthSyncChangePage = { HealthSyncChangePage(emptySequence(), "complete", false) }
        var stepsRead: (LocalDate) -> HealthConnectMeasurement? = { null }
        override suspend fun granted() = permissions
        override suspend fun token(scope: HealthConnectScope): String {
            assertEquals(this.scope, scope)
            tokenCalls++
            return nextToken
        }
        override suspend fun snapshot(scope: HealthConnectScope, from: Instant, until: Instant, cursor: String): HealthSyncSnapshotPage {
            assertEquals(this.scope, scope)
            snapshots += Triple(from, until, cursor)
            return snapshotRead(cursor)
        }
        override suspend fun changes(scope: HealthConnectScope, token: String, until: Instant): HealthSyncChangePage {
            assertEquals(this.scope, scope)
            fetched += token
            return changesRead(token)
        }
        override suspend fun stepDay(day: LocalDate, zone: ZoneId): HealthConnectMeasurement? {
            stepDays += day to zone
            return stepsRead(day)
        }
    }

    private fun fixture(test: (HealthOverviewDatabases) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { test(names) } finally { clearHealthOverviewFixture(context, names) }
    }
    private fun pressure(id: String) = HealthConnectMeasurement(id, "example.watch",
        HealthDraft(values = mapOf("systolic" to "120", "diastolic" to "80"), measuredAt = now - 1000))
    private fun sync(store: HealthRecordStore, gateway: Gateway?, scope: HealthConnectScope = pressure,
                     availability: HealthPlatformAvailability = HealthPlatformAvailability.AVAILABLE, clock: Long = now, zone: ZoneId = this.zone) {
        runBlocking { assertTrue(HealthSyncEngine.run(store, setOf(scope), availability, gateway, { clock }, zone)) }
    }

    @Test fun snapshotFailureResumesItsPageAndExistingRowsAreNotRepeated() = fixture { names ->
        val gateway = Gateway(pressure).apply {
            snapshotRead = { cursor ->
                if (cursor.isEmpty()) HealthSyncSnapshotPage(sequenceOf(pressure("first")), "snapshot-page-two")
                else throw IOException("fixture provider failed")
            }
        }
        HealthRecordStore(context, names.records).use { store ->
            sync(store, gateway)
            val pending = store.healthSyncCheckpoint(pressure)
            assertEquals(HealthSyncOutcome.TRANSPORT, pending.outcome)
            assertEquals("snapshot-page-two", pending.snapshotCursor)
            assertEquals(1, pending.pendingInserts)
            assertEquals(0L, pending.lastSuccess)
            assertEquals(1L, store.count())
            store.tableDatabase.rawQuery("SELECT payload FROM health_sync_checkpoints", null).use {
                assertTrue(it.moveToFirst())
                assertFalse(String(it.getBlob(0), Charsets.ISO_8859_1).contains(gateway.nextToken))
            }
        }
        gateway.snapshotRead = { cursor ->
            assertEquals("snapshot-page-two", cursor)
            HealthSyncSnapshotPage(sequenceOf(pressure("first"), pressure("second")), "")
        }
        HealthRecordStore(context, names.records).use { reopened ->
            sync(reopened, gateway)
            val synced = reopened.healthSyncCheckpoint(pressure)
            assertEquals(HealthSyncOutcome.UPDATED, synced.outcome)
            assertEquals(2, synced.lastInserts)
            assertEquals(1, gateway.tokenCalls)
            assertEquals(2L, reopened.count())
            sync(reopened, gateway, clock = now + 1)
            assertEquals(HealthSyncOutcome.NO_NEW, reopened.healthSyncCheckpoint(pressure).outcome)
            assertEquals(2L, reopened.count())
        }
    }

    @Test fun changesAdvanceOnlyAfterCompletedPagesAndProviderDeletesDoNotEraseCopies() = fixture { names ->
        HealthRecordStore(context, names.records).use { store ->
            store.saveHealthSyncCheckpoint(HealthSyncCheckpoint(pressure, token = "changes-one", lastSuccess = now - 60_000))
            val reader = Gateway(pressure).apply {
                changesRead = { cursor ->
                    if (cursor == "changes-one") HealthSyncChangePage(sequenceOf(pressure("one")), "changes-two", true)
                    else throw UnknownHostException("fixture network offline")
                }
            }
            sync(store, reader)
            val state = store.healthSyncCheckpoint(pressure)
            assertEquals(HealthSyncOutcome.NETWORK, state.outcome)
            assertEquals("changes-two", state.token)
            assertEquals(1, state.pendingInserts)
            assertEquals(now - 60_000, state.lastSuccess)
            reader.fetched.clear()
            reader.changesRead = { HealthSyncChangePage(sequenceOf(pressure("one"), pressure("two")), "complete", false, deletions = 1) }
            sync(store, reader)
            assertEquals(listOf("changes-two"), reader.fetched)
            assertEquals(1, store.healthSyncCheckpoint(pressure).lastDeletes)
            assertEquals(2L, store.count())
        }
    }

    @Test fun expiredCursorRecoversBoundedHistoryAndRecordsTheOlderGap() = fixture { names ->
        HealthRecordStore(context, names.records).use { store ->
            store.saveHealthSyncCheckpoint(HealthSyncCheckpoint(pressure, token = "expired", lastSuccess = now - 40 * HealthSyncEngine.DAY))
            val reader = Gateway(pressure).apply {
                changesRead = {
                    if (it == "expired") HealthSyncChangePage(emptySequence(), "", false, expired = true)
                    else HealthSyncChangePage(emptySequence(), "complete", false)
                }
                snapshotRead = { HealthSyncSnapshotPage(sequenceOf(pressure("recovered")), "") }
            }
            sync(store, reader)
            assertEquals(Instant.ofEpochMilli(now - 29 * HealthSyncEngine.DAY), reader.snapshots.single().first)
            assertTrue(store.healthSyncCheckpoint(pressure).historyGap)
            assertEquals(1L, store.count())
        }
    }

    @Test fun pauseDuringNextPageKeepsCommittedProgressAndRejectsAnOverlappingRun() = fixture { names ->
        val entered = CompletableDeferred<Unit>()
        val reader = Gateway(pressure).apply {
            changesRead = { cursor ->
                if (cursor == "first") HealthSyncChangePage(sequenceOf(pressure("saved")), "next", true)
                else { entered.complete(Unit); awaitCancellation() }
            }
        }
        HealthRecordStore(context, names.records).use { store ->
            store.saveHealthSyncCheckpoint(HealthSyncCheckpoint(pressure, token = "first"))
            runBlocking {
                val job = launch {
                    HealthSyncEngine.run(store, setOf(pressure), HealthPlatformAvailability.AVAILABLE, reader, { now }, zone)
                }
                try {
                    withTimeout(10_000) { entered.await() }
                    assertFalse(HealthSyncEngine.run(store, setOf(pressure), HealthPlatformAvailability.AVAILABLE, reader, { now }, zone))
                } finally { job.cancelAndJoin() }
            }
            val pending = store.healthSyncCheckpoint(pressure)
            assertEquals(HealthSyncOutcome.RUNNING, pending.outcome)
            assertEquals("next", pending.token)
            assertEquals(1, pending.pendingInserts)
            assertEquals(1L, store.count())
        }
        reader.changesRead = { HealthSyncChangePage(sequenceOf(pressure("saved")), "complete", false) }
        HealthRecordStore(context, names.records).use { reopened ->
            sync(reopened, reader)
            assertEquals(HealthSyncOutcome.UPDATED, reopened.healthSyncCheckpoint(pressure).outcome)
            assertEquals(1, reopened.healthSyncCheckpoint(pressure).lastInserts)
            assertEquals(1L, reopened.count())
        }
    }

    @Test fun revocationTimeoutAndUnavailableAreDistinctAndNeverConsumeTheCursor() = fixture { names ->
        HealthRecordStore(context, names.records).use { store ->
            store.saveHealthSyncCheckpoint(HealthSyncCheckpoint(pressure, token = "resume"))
            val reader = Gateway(pressure).apply {
                changesRead = {
                    permissions = emptySet()
                    HealthSyncChangePage(sequenceOf(pressure("blocked")), "unsafe-advance", false)
                }
            }
            sync(store, reader)
            assertEquals(HealthSyncOutcome.PERMISSION, store.healthSyncCheckpoint(pressure).outcome)
            assertEquals("resume", store.healthSyncCheckpoint(pressure).token)
            assertEquals(0L, store.count())
            reader.permissions = setOf(pressure.permission)
            reader.changesRead = { withTimeout(1) { delay(100); HealthSyncChangePage(emptySequence(), "never", false) } }
            sync(store, reader)
            assertEquals(HealthSyncOutcome.TIMEOUT, store.healthSyncCheckpoint(pressure).outcome)
            sync(store, null, availability = HealthPlatformAvailability.INSTALL_OR_UPDATE)
            assertEquals(HealthSyncOutcome.UNAVAILABLE, store.healthSyncCheckpoint(pressure).outcome)
            assertEquals("resume", store.healthSyncCheckpoint(pressure).token)
        }
    }

    @Test fun stepsUseCompletedDaysAndAnEmptyDayIsNotAnError() = fixture { names ->
        val steps = HealthConnectScope.STEPS
        HealthRecordStore(context, names.records).use { store ->
            val reader = Gateway(steps)
            sync(store, reader, steps)
            assertEquals(LocalDate.of(2026, 10, 3) to zone, reader.stepDays.single())
            assertEquals(HealthSyncOutcome.NO_NEW, store.healthSyncCheckpoint(steps).outcome)
            reader.stepDays.clear()
            sync(store, reader, steps, clock = now + HealthSyncEngine.DAY, zone = ZoneId.of("Asia/Shanghai"))
            assertEquals(listOf(LocalDate.of(2026, 10, 3) to zone, LocalDate.of(2026, 10, 4) to zone), reader.stepDays)
            assertEquals("2026-10-04", store.healthSyncCheckpoint(steps).stepDate)
        }
    }

    @Test fun versionFiveUpgradeAndInterruptedTransactionPreserveLegacyRowsAndCheckpoint() = fixture { names ->
        val original = seedLegacyHealthObservation(context, names.records, 5, pressure("unused").draft)
        HealthRecordStore(context, names.records).use { store ->
            val mark = HealthSyncCheckpoint(pressure, token = "before", outcome = HealthSyncOutcome.RUNNING)
            store.saveHealthSyncCheckpoint(mark)
            var checks = 0
            assertTrue(runCatching {
                store.saveHealthSyncChunk(mark, listOf(pressure("external"))) {
                    if (++checks == 2) throw IllegalStateException("fixture process interruption")
                }
            }.isFailure)
            assertEquals(mark, store.healthSyncCheckpoint(pressure))
            assertEquals(listOf(original), store.page().records)
            assertEquals(HealthRecordStore.SCHEMA_VERSION, store.tableDatabase.version)
        }
    }

    @Test fun nativePageKeepsUnavailablePlatformSeparateFromAnInterruptedSync() = fixture { names ->
        assumeFalse("Sync UI requires an unlocked display", context.getSystemService(KeyguardManager::class.java).isKeyguardLocked)
        val status = HealthSourcesRepository.platform(context)
        assumeFalse("Missing-provider test requires unavailable Health Connect", status == HealthPlatformAvailability.AVAILABLE)
        HealthRecordStore(context, names.records).use {
            it.saveHealthSyncCheckpoint(HealthSyncCheckpoint(pressure, token = "resume", lastAttempt = now, outcome = HealthSyncOutcome.RUNNING))
        }
        val intent = Intent(context, HealthSyncActivity::class.java).putExtra("health_sync_test_id", names.fixture)
        ActivityScenario.launch<HealthSyncActivity>(intent).use { scenario ->
            val until = SystemClock.elapsedRealtime() + 10_000
            var ready = false
            while (!ready && SystemClock.elapsedRealtime() < until) {
                scenario.onActivity { ready = it.window.decorView.findViewWithTag<View>("health-sync-scope-BLOOD_PRESSURE") != null }
                if (!ready) SystemClock.sleep(40)
            }
            assertTrue(ready)
            scenario.onActivity {
                val label = it.window.decorView.findViewWithTag<TextView>("health-sync-platform-status")
                assertNotEquals(it.getString(R.string.health_sync_running), label.text.toString())
                assertNotEquals(it.getString(R.string.health_sync_no_new), label.text.toString())
            }
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.onActivity { assertNull(it.window.decorView.findViewWithTag<View>("health-sync-platform-status")) }
        }
    }
}
