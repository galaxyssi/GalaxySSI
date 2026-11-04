package com.galaxyssi.chat

import android.content.ContentValues
import androidx.test.platform.app.InstrumentationRegistry
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

internal fun seedHealthSleep(records: HealthRecordStore, now: Long, zone: ZoneId): HealthObservation {
    val first = HealthReminderPolicy.day(now, zone).minusDays(21)
    return (0..20).map { day ->
        val time = first.plusDays(day.toLong()).atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
        val draft = HealthDraft(HealthMetric.SLEEP_DURATION, mapOf("sleep_duration" to if (day < 14) "7" else "6"), "h", time,
            note = "private-not-in-snapshot")
        (records.save(draft) as HealthSaveResult.Saved).record
    }.last()
}

class HealthSleepAlertDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val zone = ZoneId.of("UTC")
    private val now = LocalDate.of(2024, 11, 4).atTime(10, 0).atZone(zone).toInstant().toEpochMilli()
    private data class Fixture(val store: HealthReminderStore, val records: HealthRecordStore,
        val reminderName: String, val recordName: String, val privacyName: String)
    private fun fixture(test: (Fixture) -> Unit) {
        val id = UUID.randomUUID()
        val names = listOf("health-reminder-test-$id.db", "health-weekly-test-$id.db", "health-privacy-test-$id.db")
        try { HealthReminderStore(context, names[0]).use { store -> HealthRecordStore(context, names[1]).use {
            test(Fixture(store, it, names[0], names[1], names[2]))
        } } } finally { names.forEach(context::deleteDatabase) }
    }
    private fun evaluate(f: Fixture, time: Long = now) = HealthSleepAlertEngine.evaluate(context, f.store, time, zone, f.recordName, f.privacyName)
    private fun enable(f: Fixture) = f.store.save(f.store.settings().copy(sleepChanges = true), now)

    @Test fun disabledSleepRuleDoesNotReadMeasurementsOrCreatePrivacyDatabase() = fixture { f ->
        assertFalse(evaluate(f))
        assertFalse(context.getDatabasePath(f.privacyName).exists())
        assertFalse(f.store.hasSleepHistory())
    }
    @Test fun realEncryptedRecordsProduceOneScopedAuditedEpisodeAndSkipUnchangedRuns() = fixture { f ->
        seedHealthSleep(f.records, now, zone)
        enable(f)
        assertTrue(evaluate(f))
        val opened = f.store.activeSleep()!!
        assertEquals(7, opened.evidence.recentDays); assertEquals(14, opened.evidence.baselineDays)
        assertEquals(60, opened.evidence.decrease.toInt())
        assertFalse(opened.json().toString().contains("private-not-in-snapshot"))
        assertTrue(evaluate(f, now + 1000))
        assertEquals(opened.id, f.store.activeSleep()!!.id)
        assertEquals(1, f.store.sleepPage(HealthReminderFilter.ALL, null).rows.size)
        HealthPrivacyStore(context, f.privacyName).use { access ->
            val event = access.page().entries.single()
            assertEquals(HealthAccessPurpose.SLEEP_CHANGE, event.scope.purpose)
            assertEquals(HealthAccessOutcome.COMPLETE, event.outcome)
        }
    }
    @Test fun revisionUpdatesKeepOriginalTriggerAndClearAnInvalidatedConclusion() = fixture { f ->
        val source = seedHealthSleep(f.records, now, zone)
        enable(f); evaluate(f)
        val first = f.store.activeSleep()!!
        val edited = (f.records.save(source.editable().copy(values = mapOf("sleep_duration" to "5"))) as HealthSaveResult.Saved).record
        evaluate(f, now + 1000)
        val changed = f.store.activeSleep()!!
        assertEquals(first.id, changed.id); assertEquals(first.trigger, changed.trigger)
        assertNotEquals(first.evidence.metricVersion, changed.evidence.metricVersion)
        assertTrue(runCatching { f.store.actSleep(first, HealthReminderAction.COMPLETE, now + 2000) }.exceptionOrNull() is HealthReminderConflict)
        f.records.save(edited.editable().copy(values = mapOf("sleep_duration" to "12")))
        evaluate(f, now + 2000)
        assertNull(f.store.activeSleep())
        assertEquals(HealthReminderState.STALE, f.store.sleepAlert(first.id)!!.state)
        assertTrue(f.store.sleepPage(HealthReminderFilter.PENDING, null).rows.isEmpty())
    }
    @Test fun restartRestoresSnoozeAndPrivacyRevocationStopsTheActiveEpisode() = fixture { f ->
        seedHealthSleep(f.records, now, zone); enable(f); evaluate(f)
        val alert = f.store.activeSleep()!!
        f.store.actSleep(alert, HealthReminderAction.SNOOZE, now)
        HealthReminderStore(context, f.reminderName).use { reopened ->
            assertEquals(now + HealthReminderPolicy.HOUR, reopened.activeSleep()!!.resumeAt)
            evaluate(f, now + HealthReminderPolicy.HOUR)
            assertEquals(HealthReminderState.PENDING, reopened.activeSleep()!!.state)
            HealthPrivacyStore(context, f.privacyName).use { access ->
                access.change(HealthPrivacyOption.CONFIRMED_METRICS, false, access.policy().version)
            }
            assertFalse(evaluate(f, now + HealthReminderPolicy.HOUR + 1))
            assertNull(reopened.activeSleep())
        }
    }
    @Test fun disablingSleepLeavesDailyPlanAndRetainsTheRecordedHandlingOutcome() = fixture { f ->
        seedHealthSleep(f.records, now, zone)
        f.store.save(f.store.settings().copy(enabled = true, sleepChanges = true), now)
        evaluate(f)
        val alert = f.store.activeSleep()!!
        f.store.actSleep(alert, HealthReminderAction.DISABLE, now + 1)
        assertTrue(f.store.settings().enabled); assertFalse(f.store.settings().sleepChanges)
        assertEquals(HealthReminderState.DISABLED, f.store.sleepAlert(alert.id)!!.state)
        assertEquals(now + 1, f.store.sleepAlert(alert.id)!!.handledAt)
    }
    @Test fun schemaOneUpgradePreservesExistingSettingsAndDailyHistory() {
        val name = "health-reminder-test-${UUID.randomUUID()}.db"
        try {
            val due = now - 2 * HealthReminderPolicy.HOUR
            val old = HealthReminderStore(context, name).use {
                val saved = it.save(it.settings().copy(enabled = true, minute = 480, quiet = false), due - 1)
                it.reconcile(now, zone)
                assertEquals(1, it.page(HealthReminderFilter.ALL, null).rows.size)
                saved
            }
            context.openOrCreateDatabase(name, 0, null).use { db ->
                val json = old.json().apply { remove("sleepChanges"); remove("sleepDecrease"); remove("mergeSleepChanges") }
                val plain = json.toString().toByteArray(Charsets.UTF_8)
                try { db.update("settings", ContentValues().apply {
                    put("payload", AgentStorageCipher.encryptBinary(plain, "$name|health-reminders-v1|settings".toByteArray()))
                }, "id=1", null) } finally { plain.fill(0) }
                db.execSQL("DROP TABLE sleep_alerts")
                db.execSQL("DROP TABLE sleep_eval")
                db.version = 1
            }
            HealthReminderStore(context, name).use {
                assertEquals(old, it.settings())
                assertFalse(it.settings().sleepChanges)
                assertEquals(1, it.page(HealthReminderFilter.ALL, null).rows.size)
                assertFalse(it.hasSleepHistory())
            }
        } finally { context.deleteDatabase(name) }
    }
}
