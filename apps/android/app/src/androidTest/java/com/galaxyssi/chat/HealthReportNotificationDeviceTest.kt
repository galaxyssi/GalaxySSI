package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.net.Uri
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

class HealthReportNotificationDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val zone = ZoneId.of("UTC")
    private val day = LocalDate.of(2026, 10, 31)
    private val now = HealthReminderPolicy.at(day, 23 * 60, zone)

    private fun fixture(test: (HealthOverviewDatabases, HealthReminderStore, HealthReportReviewRepository, String) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try {
            val report = overviewOcrJob(context, names, now - 100L).first.id
            HealthReminderStore(context, names.reminders).use {
                test(names, it, HealthReportReviewRepository(context, names), report)
            }
        } finally { clearHealthOverviewFixture(context, names) }
    }

    @Test fun quietAndPauseDeferDurableDeliveryWithoutReplayingTheSameReport() = fixture { names, store, repository, id ->
        val quietEnd = HealthReminderPolicy.at(day.plusDays(1), 480, zone)
        val pauseEnd = quietEnd + 20 * 60_000L
        val settings = store.save(store.settings().copy(notifications = true, pauseUntil = pauseEnd), now - 1)
        assertFalse(settings.enabled)
        assertTrue(store.admitReportNotice(id, now))
        val posted = arrayListOf<String>()
        fun reconcile(at: Long) = HealthReportNotificationDelivery.reconcile(store, settings, at, zone, true, emptyMap(),
            { repository.byId(store, it) }, { posted += it.id; true }, { fail("Unexpected cancellation") })
        assertEquals(pauseEnd, reconcile(now))
        assertTrue(posted.isEmpty())
        assertEquals(HealthReminderDelivery.WAITING, store.reportNotice(id)?.delivery)
        assertNull(reconcile(pauseEnd))
        assertEquals(listOf(id), posted)
        HealthReminderStore(context, names.reminders).use {
            assertEquals(HealthReminderDelivery.POSTED, it.reportNotice(id)?.delivery)
            assertFalse(it.admitReportNotice(id, pauseEnd + 5))
        }
        assertNull(reconcile(pauseEnd + 10))
        assertEquals(listOf(id), posted)
        assertEquals(HealthReminderState.PENDING, repository.byId(store, setOf(id)).getValue(id).state(pauseEnd))
    }

    @Test fun snoozeCancelsVisibleNoticeThenPostsOnceAndHandlingDoesNotChangeRecords() = fixture { names, store, repository, id ->
        val settings = store.save(store.settings().copy(notifications = true, quiet = false), now - 1)
        assertTrue(store.admitReportNotice(id, now))
        val visible = mutableMapOf<String, Boolean>()
        var posts = 0
        fun reconcile(at: Long) = HealthReportNotificationDelivery.reconcile(store, settings, at, zone, true, visible.toMap(),
            { repository.byId(store, it) }, { visible[it.id] = true; posts++; true }, { visible.remove(it) })
        assertNull(reconcile(now))
        assertEquals(1, posts)
        val report = repository.byId(store, setOf(id)).getValue(id)
        repository.act(store, report, HealthReminderAction.SNOOZE, now + 1)
        val resume = now + 1 + HealthReminderPolicy.HOUR
        assertEquals(resume, reconcile(now + 1))
        assertFalse(id in visible)
        assertNull(reconcile(resume))
        assertEquals(2, posts)
        repository.act(store, repository.byId(store, setOf(id)).getValue(id), HealthReminderAction.COMPLETE, resume + 1)
        assertNull(reconcile(resume + 1))
        assertFalse(id in visible)
        assertEquals(HealthReminderDelivery.POSTED, store.reportNotice(id)?.delivery)
        assertEquals(HealthReminderState.COMPLETE, repository.byId(store, setOf(id)).getValue(id).state(resume + 2))
        HealthRecordStore(context, names.records).use { assertEquals(0L, it.count()) }
    }

    @Test fun deniedPermissionAndDisabledCategoryLeaveTheReportInAppWithoutBacklogReplay() = fixture { _, store, repository, id ->
        val settings = store.save(store.settings().copy(notifications = true, quiet = false), now - 1)
        assertTrue(store.admitReportNotice(id, now))
        fun reconcile(at: Long, allowed: Boolean, config: HealthReminderSettings) =
            HealthReportNotificationDelivery.reconcile(store, config, at, zone, allowed, emptyMap(),
                { repository.byId(store, it) }, { fail("Unexpected post"); false }, { fail("Unexpected cancel") })
        assertNull(reconcile(now, false, settings))
        assertEquals(HealthReminderDelivery.IN_APP_ONLY, store.reportNotice(id)?.delivery)
        assertNull(reconcile(now + 1, true, settings))
        repository.act(store, repository.byId(store, setOf(id)).getValue(id), HealthReminderAction.SNOOZE, now + 2)
        assertNotNull(store.nextReportNotice())
        val disabled = store.save(settings.copy(reportReviews = false), now + 3)
        assertNull(store.nextReportNotice())
        assertNull(reconcile(now + HealthReminderPolicy.HOUR + 3, true, disabled))
        assertEquals(HealthReminderState.PENDING,
            repository.byId(store, setOf(id)).getValue(id).state(now + HealthReminderPolicy.HOUR + 3))
    }

    @Test fun cancelledSourceAndConcurrentHandlingCannotLeaveAVisibleNotice() = fixture { _, store, repository, id ->
        val settings = store.save(store.settings().copy(notifications = true, quiet = false), now - 1)
        assertTrue(store.admitReportNotice(id, now))
        val cancelled = arrayListOf<String>()
        assertNull(HealthReportNotificationDelivery.reconcile(store, settings, now, zone, true, emptyMap(),
            { repository.byId(store, it) }, {
                repository.act(store, it, HealthReminderAction.COMPLETE, now)
                true
            }, { cancelled += it }))
        assertEquals(listOf(id), cancelled)
        assertEquals(HealthReminderDelivery.IN_APP_ONLY, store.reportNotice(id)?.delivery)
        val missing = UUID.randomUUID().toString()
        assertTrue(store.admitReportNotice(missing, now))
        assertNull(HealthReportNotificationDelivery.reconcile(store, settings, now, zone, true, emptyMap(),
            { repository.byId(store, it) }, { fail("Deleted source must not post"); false }, {}))
        assertEquals(HealthReminderDelivery.IN_APP_ONLY, store.reportNotice(missing)?.delivery)
    }

    @Test fun nativeNotificationUsesAnExactImmutableRouteAndGenericLockScreenContent() = fixture { names, store, repository, id ->
        val report = repository.byId(store, setOf(id)).getValue(id).copy(name = "PRIVATE_SYNTHETIC_REPORT.pdf")
        val intent = report.intent(context, names.fixture).setData(Uri.parse("galaxyssi://health/report-review/$id"))
        assertEquals(id, intent.getStringExtra("health_job"))
        assertEquals(HealthCaptureActivity::class.java.name, intent.component?.className)
        assertFalse(intent.extras.toString().contains(report.name))
        val notice = HealthReminderWork.notification(context, intent, 0, R.string.health_report_review_notice, store.settings())
        assertEquals(Notification.VISIBILITY_PRIVATE, notice.visibility)
        assertEquals(Notification.VISIBILITY_PUBLIC, notice.publicVersion.visibility)
        assertEquals(context.getString(R.string.health_report_review_notice), notice.extras.getCharSequence(Notification.EXTRA_TEXT))
        assertNull(notice.publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT))
        assertNotNull(notice.contentIntent)
        assertFalse(notice.extras.toString().contains(report.name))
        notice.contentIntent.cancel()
    }

    @Test fun androidAcceptsAndCancelsTheRedactedNotificationOnAnIsolatedSilentChannel() = fixture { names, store, repository, id ->
        val manager = context.getSystemService(NotificationManager::class.java)
        assumeTrue("App notification permission is required for native posting", manager.areNotificationsEnabled())
        val channel = "health-report-fixture-$id"
        manager.createNotificationChannel(NotificationChannel(channel, "Health review test", NotificationManager.IMPORTANCE_LOW))
        val report = repository.byId(store, setOf(id)).getValue(id)
        val intent = report.intent(context, names.fixture).setData(Uri.parse("galaxyssi://health/report-review/$id"))
        val notice = HealthReminderWork.notification(context, intent, 0, R.string.health_report_review_notice, store.settings())
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
