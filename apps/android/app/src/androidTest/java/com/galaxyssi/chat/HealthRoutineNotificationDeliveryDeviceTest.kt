package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class HealthRoutineNotificationDeliveryDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val zone = ZoneId.of("UTC")
    private val day = LocalDate.of(2026, 10, 31)
    private val now = HealthReminderPolicy.at(day, 23 * 60, zone)

    @Test fun rewindingTheClockDoesNotPostAnAlreadyReconciledSnoozeEarly() = fixture { name, store ->
        store.save(store.settings().copy(enabled = true, notifications = true, quiet = false), now - HealthReminderPolicy.DAY)
        store.reconcile(now, zone)
        val original = requireNotNull(store.occurrence(day))
        store.act(day, original.revision, HealthReminderAction.SNOOZE, now)
        val wake = now + HealthReminderPolicy.HOUR
        store.reconcile(wake, zone)
        val pending = requireNotNull(store.occurrence(day))
        assertEquals(HealthReminderState.PENDING, pending.state)
        HealthReminderStore(context, name).use { reopened ->
            val posted = arrayListOf<LocalDate>()
            val cancelled = arrayListOf<LocalDate>()
            fun deliver(at: Long, visible: Map<LocalDate, Boolean> = emptyMap()) = HealthRoutineNotificationDelivery.daily(
                reopened, reopened.settings(), at, zone, true, visible, { posted += it.day; true }, { cancelled += it })
            assertEquals(wake, deliver(wake - 1, mapOf(day to true)))
            assertEquals(listOf(day), cancelled)
            assertTrue(posted.isEmpty())
            assertTrue(reopened.pendingDelivery(wake - 1).isEmpty())
            assertEquals(HealthReminderDelivery.WAITING, reopened.occurrence(day)?.delivery)
            assertNull(deliver(wake))
            assertNull(deliver(wake + 1))
            assertEquals(listOf(day), posted)
            assertEquals(HealthReminderDelivery.POSTED, reopened.occurrence(day)?.delivery)
            assertEquals(original.dueAt, reopened.occurrence(day)?.dueAt)
        }
    }

    @Test fun sleepWaitsForBothQuietHoursAndPauseAfterReopeningTheStore() = fixture { name, store ->
        val quietEnd = HealthReminderPolicy.at(day.plusDays(1), 8 * 60, zone)
        val resume = quietEnd + HealthReminderPolicy.HOUR
        val settings = store.save(store.settings().copy(sleepChanges = true, notifications = true, pauseUntil = resume), now - 1)
        store.applySleep(settings.revision, "fixture", evidence(), now)
        val id = requireNotNull(store.activeSleep()).id
        HealthReminderStore(context, name).use { reopened ->
            var posts = 0
            fun deliver(time: Long) = HealthRoutineNotificationDelivery.sleep(reopened, reopened.activeSleep(),
                reopened.settings(), time, zone, true, emptyMap(), { posts++; true }, {})
            assertEquals(resume, deliver(now - 1))
            assertEquals(resume, deliver(now))
            assertEquals(resume, deliver(quietEnd))
            assertEquals(0, posts)
            assertEquals(HealthReminderDelivery.WAITING, reopened.sleepAlert(id)?.delivery)
            assertNull(deliver(resume))
            assertNull(deliver(resume + 1))
            assertEquals(1, posts)
            assertEquals(HealthReminderDelivery.POSTED, reopened.sleepAlert(id)?.delivery)
            assertEquals(HealthReminderState.PENDING, reopened.sleepAlert(id)?.state)
        }
    }

    @Test fun aDeniedPermissionKeepsBothReminderTypesInAppWithoutReplayingThem() = fixture { _, store ->
        val settings = store.save(store.settings().copy(enabled = true, sleepChanges = true, notifications = true, quiet = false),
            now - HealthReminderPolicy.DAY)
        store.reconcile(now, zone)
        store.applySleep(settings.revision, null, evidence(), now)
        for (allowed in listOf(false, true)) {
            val time = now + if (allowed) 1 else 0
            assertNull(HealthRoutineNotificationDelivery.daily(store, settings, time, zone, allowed, emptyMap(),
                { fail("Do not replay a daily reminder after permission returns"); false }, {}))
            assertNull(HealthRoutineNotificationDelivery.sleep(store, store.activeSleep(), settings, time, zone, allowed,
                emptyMap(), { fail("Do not replay a sleep reminder after permission returns"); false }, {}))
        }
        assertEquals(HealthReminderDelivery.IN_APP_ONLY, store.occurrence(day)?.delivery)
        assertEquals(HealthReminderState.PENDING, store.occurrence(day)?.state)
        assertEquals(HealthReminderDelivery.IN_APP_ONLY, store.activeSleep()?.delivery)
        assertEquals(HealthReminderState.PENDING, store.activeSleep()?.state)
    }

    @Test fun userHandlingDuringPostRemovesTheOrphanedNotification() = fixture { _, store ->
        val settings = store.save(store.settings().copy(enabled = true, sleepChanges = true, notifications = true, quiet = false),
            now - HealthReminderPolicy.DAY)
        store.reconcile(now, zone)
        store.applySleep(settings.revision, null, evidence(), now)
        val alert = requireNotNull(store.activeSleep())
        val removed = arrayListOf<String>()
        assertNull(HealthRoutineNotificationDelivery.daily(store, settings, now, zone, true, emptyMap(),
            { store.act(it.day, it.revision, HealthReminderAction.COMPLETE, now); true }, { removed += it.toString() }))
        assertNull(HealthRoutineNotificationDelivery.sleep(store, alert, settings, now, zone, true, emptyMap(),
            { store.actSleep(it, HealthReminderAction.COMPLETE, now); true }, { removed += it }))
        assertEquals(listOf(day.toString(), alert.id), removed)
        assertEquals(HealthReminderState.COMPLETE, store.occurrence(day)?.state)
        assertEquals(HealthReminderState.COMPLETE, store.sleepAlert(alert.id)?.state)
    }

    @Test fun enablingPauseCancelsAnActualSilentSleepNotificationWithoutHandlingIt() = fixture { name, store ->
        val manager = context.getSystemService(NotificationManager::class.java)
        assumeTrue("Native posting requires existing notification permission", manager.areNotificationsEnabled())
        val settings = store.save(store.settings().copy(sleepChanges = true, notifications = true, quiet = false), now - 1)
        store.applySleep(settings.revision, null, evidence(), now)
        val alert = requireNotNull(store.activeSleep())
        val tag = "health-sleep-fixture-${alert.id}"
        val channel = NotificationChannel(tag, "Isolated health reminder", NotificationManager.IMPORTANCE_LOW)
        manager.createNotificationChannel(channel)
        val intent = Intent(context, HealthReminderActivity::class.java).putExtra("health_reminder_test_db", name)
            .putExtra("health_sleep_alert_id", alert.id).setData(Uri.parse("galaxyssi://health/fixture/${alert.id}"))
        val template = HealthReminderWork.notification(context, intent, 0, R.string.health_sleep_alert_title, settings)
        val notice = Notification.Builder.recoverBuilder(context, template).setChannelId(tag).build()
        var posts = 0
        fun deliver(config: HealthReminderSettings, time: Long) = HealthRoutineNotificationDelivery.sleep(
            store, store.activeSleep(), config, time, zone, true,
            manager.activeNotifications.filter { it.tag == tag }.associate { alert.id to (it.notification.visibility == Notification.VISIBILITY_PRIVATE) },
            { posts++; manager.notify(tag, 1, notice); true }, { manager.cancel(tag, 1) })
        try {
            assertNull(deliver(settings, now))
            awaitVisible(manager, tag, true)
            assertNull(notice.publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT))
            val pause = now + HealthReminderPolicy.HOUR
            val muted = store.save(settings.copy(pauseUntil = pause), now + 1)
            assertNull(deliver(muted, now + 1))
            awaitVisible(manager, tag, false)
            assertEquals(HealthReminderState.PENDING, store.sleepAlert(alert.id)?.state)
            assertEquals(HealthReminderDelivery.POSTED, store.sleepAlert(alert.id)?.delivery)
            assertNull(deliver(muted, pause))
            awaitVisible(manager, tag, false)
            assertEquals(1, posts)
        } finally {
            manager.cancel(tag, 1)
            manager.deleteNotificationChannel(tag)
            template.contentIntent.cancel()
        }
    }

    private fun evidence() = HealthSleepAlertEvidence(day.minusDays(1), zone.id, "test-record-version", now,
        HealthSleepAlertPolicy.VERSION, 45, BigDecimal("360"), BigDecimal("420"), List(7) { BigDecimal("360") }, 14, 7)
    private fun fixture(test: (String, HealthReminderStore) -> Unit) {
        val name = "health-reminder-test-${UUID.randomUUID()}.db"
        try { HealthReminderStore(context, name).use { test(name, it) } }
        finally { context.deleteDatabase(name) }
    }
    private fun awaitVisible(manager: NotificationManager, tag: String, expected: Boolean) {
        val until = SystemClock.elapsedRealtime() + 5_000
        do {
            if (manager.activeNotifications.any { it.tag == tag && it.id == 1 } == expected) return
            SystemClock.sleep(50)
        } while (SystemClock.elapsedRealtime() < until)
        fail("Native notification did not reach visibility=$expected at ${Instant.now()}")
    }
}
