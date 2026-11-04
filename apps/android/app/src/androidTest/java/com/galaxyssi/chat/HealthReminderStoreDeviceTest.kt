package com.galaxyssi.chat

import androidx.test.platform.app.InstrumentationRegistry
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthReminderStoreDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val zone = ZoneId.of("UTC")
    private val now = Instant.parse("2026-11-04T09:00:00Z").toEpochMilli()
    private val day = LocalDate.parse("2026-11-04")
    private fun fixture(test: (String, HealthReminderStore) -> Unit) {
        val db = "health-reminder-test-${UUID.randomUUID()}.db"
        try { HealthReminderStore(context, db).use { test(db, it) } } finally { context.deleteDatabase(db) }
    }
    private fun enable(store: HealthReminderStore) = store.save(store.settings().copy(enabled = true), now - HealthReminderPolicy.HOUR)

    @Test fun disabledPlanDoesNotCreateAnOccurrence() = fixture { _, store ->
        store.reconcile(now, zone)
        assertTrue(store.page(HealthReminderFilter.ALL, null).rows.isEmpty())
    }
    @Test fun repeatedRecoveryAndZoneChangeKeepOneOriginalSnapshot() = fixture { name, store ->
        enable(store); store.reconcile(now, zone)
        val original = requireNotNull(store.occurrence(day))
        HealthReminderStore(context, name).use { reopened ->
            reopened.reconcile(now, zone); reopened.reconcile(now, ZoneId.of("Asia/Shanghai"))
            assertEquals(listOf(original), reopened.page(HealthReminderFilter.ALL, null).rows)
        }
    }
    @Test fun deliveryStatusDoesNotMarkReminderCompleteAndCompletionSurvivesReopen() = fixture { name, store ->
        enable(store); store.reconcile(now, zone)
        val event = store.pendingDelivery(now).single()
        store.delivered(event, HealthReminderDelivery.IN_APP_ONLY)
        assertEquals(HealthReminderState.PENDING, store.occurrence(day)!!.state)
        assertTrue(store.pendingDelivery(now).isEmpty())
        store.act(day, event.revision, HealthReminderAction.COMPLETE, now)
        HealthReminderStore(context, name).use {
            it.reconcile(now + 60_000, zone)
            assertTrue(it.page(HealthReminderFilter.PENDING, null).rows.isEmpty())
            assertEquals(HealthReminderDelivery.IN_APP_ONLY, it.page(HealthReminderFilter.HANDLED, null).rows.single().delivery)
        }
    }
    @Test fun snoozeIsDurableAndStaleActionsCannotMutateIt() = fixture { name, store ->
        enable(store); store.reconcile(now, zone)
        val event = store.occurrence(day)!!
        store.act(day, event.revision, HealthReminderAction.SNOOZE, now)
        assertTrue(runCatching { store.act(day, event.revision, HealthReminderAction.COMPLETE, now) }.exceptionOrNull() is HealthReminderConflict)
        HealthReminderStore(context, name).use {
            assertEquals(now + HealthReminderPolicy.HOUR, it.nextSnooze())
            it.reconcile(now + HealthReminderPolicy.HOUR - 1, zone)
            assertEquals(HealthReminderState.SNOOZED, it.occurrence(day)!!.state)
            it.reconcile(now + HealthReminderPolicy.HOUR, zone)
            assertEquals(HealthReminderState.PENDING, it.occurrence(day)!!.state)
            assertEquals(day, it.pendingDelivery(now + HealthReminderPolicy.HOUR).single().day)
        }
    }
    @Test fun disablingClosesOpenItemsAndReenablingDoesNotRecreateTheSameDay() = fixture { _, store ->
        enable(store); store.reconcile(now, zone)
        val event = store.occurrence(day)!!
        store.act(day, event.revision, HealthReminderAction.DISABLE, now)
        assertFalse(store.settings().enabled)
        assertEquals(HealthReminderState.DISABLED, store.occurrence(day)!!.state)
        store.save(store.settings().copy(enabled = true), now + 60_000)
        store.reconcile(now + 120_000, zone)
        assertEquals(HealthReminderState.DISABLED, store.occurrence(day)!!.state)
    }
    @Test fun preferencesUseOptimisticRevisionsAndEncryptedPayloads() = fixture { name, store ->
        val initial = store.settings()
        val saved = store.save(initial.copy(enabled = true, target = HealthReminderTarget.MEASUREMENTS), now)
        assertTrue(runCatching { store.save(initial.copy(quiet = false), now) }.exceptionOrNull() is HealthReminderConflict)
        assertEquals(saved, store.settings())
        context.openOrCreateDatabase(name, 0, null).use { db -> db.rawQuery("SELECT payload FROM settings", null).use {
            assertTrue(it.moveToFirst())
            assertFalse(it.getBlob(0).toString(Charsets.ISO_8859_1).contains("MEASUREMENTS"))
        } }
    }
    @Test fun keysetPagesKeepAllDaysAndExpiredItemsDoNotNotify() = fixture { _, store ->
        enable(store)
        repeat(65) { store.reconcile(now + it * HealthReminderPolicy.DAY, zone) }
        val all = hashSetOf<LocalDate>(); var cursor: LocalDate? = null
        do {
            val page = store.page(HealthReminderFilter.ALL, cursor)
            assertTrue(page.rows.size <= 30); page.rows.forEach { assertTrue(all.add(it.day)) }; cursor = page.next
        } while (cursor != null)
        assertEquals(65, all.size)
        assertEquals(day.plusDays(64), store.pendingDelivery(now + 64 * HealthReminderPolicy.DAY).single().day)
    }
}
