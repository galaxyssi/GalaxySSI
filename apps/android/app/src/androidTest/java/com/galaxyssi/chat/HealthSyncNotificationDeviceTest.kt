package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class HealthSyncNotificationDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val scope = HealthConnectScope.BLOOD_PRESSURE
    private val zone = ZoneId.of("UTC")
    private val day = LocalDate.of(2026, 10, 31)
    private val now = HealthReminderPolicy.at(day, 23 * 60, zone)

    private fun fixture(test: (HealthOverviewDatabases, HealthRecordStore, HealthSyncCheckpoint) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            HealthRecordStore(context, names.records).use {
                test(names, it, HealthSyncCheckpoint(scope, lastAttempt = now, outcome = HealthSyncOutcome.NETWORK))
            }
        } finally { clearHealthOverviewFixture(context, names) }
    }

    @Test fun quietPauseRetryAndRecoveryUseOneDurableReceiptPerOutage() = fixture { names, records, mark ->
        val quietEnd = HealthReminderPolicy.at(day.plusDays(1), 480, zone)
        val pauseEnd = quietEnd + 60_000L
        val settings = HealthReminderSettings(notifications = true, pauseUntil = pauseEnd)
        val visible = mutableMapOf<String, Boolean>()
        val posts = mutableListOf<String>()
        fun reconcile(at: Long) = HealthSyncNotificationDelivery.reconcile(records, settings, setOf(scope), at, zone, true, visible.toMap(),
            { posts += it.id; visible[it.id] = true; true }, { visible.remove(it) })
        records.saveHealthSyncCheckpoint(mark, systemDelivery = true)
        val first = requireNotNull(records.healthSyncIncident(scope))
        assertEquals(pauseEnd, reconcile(now))
        assertTrue(posts.isEmpty())
        assertEquals(HealthReminderDelivery.WAITING, records.healthSyncIncident(scope)?.delivery)
        records.saveHealthSyncCheckpoint(mark.copy(lastAttempt = now + 1, outcome = HealthSyncOutcome.PERMISSION), systemDelivery = true)
        assertEquals(first.id, records.healthSyncIncident(scope)?.id)
        assertNull(reconcile(pauseEnd))
        assertEquals(listOf(first.id), posts)
        HealthRecordStore(context, names.records).use {
            assertEquals(HealthReminderDelivery.POSTED, it.healthSyncIncident(scope)?.delivery)
        }
        records.saveHealthSyncCheckpoint(mark.copy(lastAttempt = pauseEnd + 1), systemDelivery = true)
        assertNull(reconcile(pauseEnd + 1))
        assertEquals(listOf(first.id), posts)
        records.saveHealthSyncCheckpoint(mark.copy(lastAttempt = pauseEnd + 2, lastSuccess = pauseEnd + 2, outcome = HealthSyncOutcome.NO_NEW))
        assertNull(reconcile(pauseEnd + 2))
        assertTrue(visible.isEmpty())
        assertEquals(HealthReminderDelivery.POSTED, records.healthSyncIncident(scope)?.delivery)
        records.saveHealthSyncCheckpoint(mark.copy(lastAttempt = pauseEnd + 3), systemDelivery = true)
        val next = requireNotNull(records.healthSyncIncident(scope))
        assertNull(reconcile(pauseEnd + 3))
        assertEquals(2, posts.distinct().size)
        records.acknowledgeHealthSyncIncident(next, pauseEnd + 4)
        assertNull(reconcile(pauseEnd + 4))
        assertTrue(visible.isEmpty())
        assertEquals(HealthReminderDelivery.POSTED, records.healthSyncIncident(scope)?.delivery)
    }

    @Test fun optOutDeselectAndLegacyIncidentsNeverReplayAsNewNotifications() = fixture { _, records, mark ->
        val settings = HealthReminderSettings(notifications = true, quiet = false)
        fun reconcile(selected: Set<HealthConnectScope>, permission: Boolean, visible: Map<String, Boolean> = emptyMap(),
            cancel: (String) -> Unit = { fail("Unexpected cancel") }) =
            HealthSyncNotificationDelivery.reconcile(records, settings, selected, now, zone, permission, visible,
                { fail("Unexpected system notification"); false }, cancel)
        records.saveHealthSyncCheckpoint(mark)
        assertEquals(HealthReminderDelivery.IN_APP_ONLY, records.healthSyncIncident(scope)?.delivery)
        assertNull(reconcile(setOf(scope), true))
        val old = requireNotNull(records.healthSyncIncident(scope))
        val legacy = HealthSyncIncident.from(old.json().apply { remove("delivery") })
        assertEquals(HealthReminderDelivery.IN_APP_ONLY, legacy.delivery)
        records.saveHealthSyncCheckpoint(mark.copy(lastSuccess = now + 1, outcome = HealthSyncOutcome.NO_NEW))
        records.saveHealthSyncCheckpoint(mark.copy(lastAttempt = now + 2), systemDelivery = true)
        assertNull(reconcile(setOf(scope), false))
        assertEquals(HealthReminderDelivery.IN_APP_ONLY, records.healthSyncIncident(scope)?.delivery)
        assertNull(reconcile(setOf(scope), true))
        records.saveHealthSyncCheckpoint(mark.copy(lastSuccess = now + 3, outcome = HealthSyncOutcome.NO_NEW))
        records.saveHealthSyncCheckpoint(mark.copy(lastAttempt = now + 4), systemDelivery = true)
        val queued = requireNotNull(records.healthSyncIncident(scope))
        val cancelled = mutableListOf<String>()
        assertNull(reconcile(emptySet(), true, mapOf(queued.id to true)) { cancelled += it })
        assertEquals(listOf(queued.id), cancelled)
        assertEquals(HealthReminderDelivery.IN_APP_ONLY, records.healthSyncIncident(scope)?.delivery)
        assertNull(reconcile(setOf(scope), true))
    }

    @Test fun handlingAndPostingCanRaceWithoutResurrectingTheAlert() = fixture { _, records, mark ->
        val settings = HealthReminderSettings(notifications = true, quiet = false)
        records.saveHealthSyncCheckpoint(mark, systemDelivery = true)
        val expected = requireNotNull(records.healthSyncIncident(scope))
        val cancelled = mutableListOf<String>()
        val checkpoint = records.healthSyncCheckpoint(scope)
        assertNull(HealthSyncNotificationDelivery.reconcile(records, settings, setOf(scope), now, zone, true, emptyMap(),
            {
                records.acknowledgeHealthSyncIncident(expected, now)
                true
            }, { cancelled += it }))
        assertEquals(listOf(expected.id), cancelled)
        assertEquals(checkpoint, records.healthSyncCheckpoint(scope))
        assertTrue(requireNotNull(records.healthSyncIncident(scope)).handled)
        assertEquals(HealthReminderDelivery.IN_APP_ONLY, records.healthSyncIncident(scope)?.delivery)
    }

    @Test fun reconciliationAdoptsAnAlreadyVisibleNoticeWithoutPostingAgain() = fixture { _, records, mark ->
        records.saveHealthSyncCheckpoint(mark, systemDelivery = true)
        val id = requireNotNull(records.healthSyncIncident(scope)).id
        assertNull(HealthSyncNotificationDelivery.reconcile(records, HealthReminderSettings(notifications = true), setOf(scope),
            now, zone, true, mapOf(id to true), { fail("Already visible"); false }, { fail("Still pending") }))
        assertEquals(HealthReminderDelivery.POSTED, records.healthSyncIncident(scope)?.delivery)
    }

    @Test fun nativeNotificationHasExactRecoveryRouteAndNoMetricDetails() = fixture { _, records, mark ->
        val manager = context.getSystemService(NotificationManager::class.java)
        assumeTrue("App notification permission is required for native posting", manager.areNotificationsEnabled())
        records.saveHealthSyncCheckpoint(mark, systemDelivery = true)
        val incident = requireNotNull(records.healthSyncIncident(scope))
        val intent = incident.intent(context)
        assertEquals(HealthSyncActivity::class.java.name, intent.component?.className)
        assertEquals(scope.name, intent.getStringExtra("health_sync_scope"))
        assertEquals(incident.id, intent.data?.lastPathSegment)
        val channel = "health-sync-fixture-${incident.id}"
        manager.createNotificationChannel(NotificationChannel(channel, "Health connection test", NotificationManager.IMPORTANCE_LOW))
        val notice = HealthReminderWork.notification(context, intent, 0, R.string.health_sync_reminder_notice, HealthReminderSettings())
        val fixtureNotice = Notification.Builder.recoverBuilder(context, notice).setChannelId(channel).build()
        try {
            manager.notify(channel, 1, fixtureNotice)
            fun waitForVisible(visible: Boolean) {
                val deadline = SystemClock.elapsedRealtime() + 5000L
                do {
                    if (manager.activeNotifications.any { it.tag == channel && it.id == 1 } == visible) return
                    SystemClock.sleep(50)
                } while (SystemClock.elapsedRealtime() < deadline)
                fail("Unexpected native notification state")
            }
            waitForVisible(true)
            val active = manager.activeNotifications.single { it.tag == channel && it.id == 1 }.notification
            assertEquals(context.getString(R.string.health_sync_reminder_notice), active.extras.getCharSequence(Notification.EXTRA_TEXT))
            assertEquals(Notification.VISIBILITY_PRIVATE, active.visibility)
            assertNull(active.publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT))
            manager.cancel(channel, 1)
            waitForVisible(false)
        } finally {
            manager.cancel(channel, 1)
            manager.deleteNotificationChannel(channel)
            notice.contentIntent.cancel()
        }
    }
}
