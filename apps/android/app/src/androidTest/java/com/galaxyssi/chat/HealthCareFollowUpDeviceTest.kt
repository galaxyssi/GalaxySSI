package com.galaxyssi.chat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentValues
import android.content.Intent
import androidx.test.platform.app.InstrumentationRegistry
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test

internal object HealthCareFollowUpTestFixture {
    fun confirmed(context: android.content.Context, names: HealthOverviewDatabases): HealthCareConcern {
        val plan = HealthCarePlanTestFixture.propose(context, names)
        return HealthCareStore(context, names.care).use { store ->
            store.resolvePlan(plan.id, plan.actions.map { it.id }.toSet(), plan.grant.revision,
                HealthPrivacyStore(context, names.privacy).use { it.policy() }, plan.inputVersion, System.currentTimeMillis())
        }
    }
}

class HealthCareFollowUpDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val zone = ZoneId.of("UTC")
    private val deliverySettings = HealthReminderSettings(notifications = true, quiet = false)
    private fun fixture(test: (HealthOverviewDatabases, HealthCareStore, HealthCareConcern) -> Unit) {
        val names = HealthOverviewDatabases(UUID.randomUUID().toString())
        try { val issue = HealthCareFollowUpTestFixture.confirmed(context, names); HealthCareStore(context, names.care).use { test(names, it, issue) } }
        finally { listOf(names.care, names.records, names.privacy, names.reminders).forEach(context::deleteDatabase) }
    }
    private fun schedule(names: HealthOverviewDatabases, store: HealthCareStore, issue: HealthCareConcern, at: Long,
        action: HealthCareAction = issue.actions.first(), token: String? = null): HealthCareReminder =
        store.scheduleReminder(issue.id, action.id, issue.revision, token, HealthPrivacyStore(context, names.privacy).use { it.policy() },
            issue.inputVersion, at, at - 1000)
    private fun deliver(names: HealthOverviewDatabases, now: Long, visible: Set<String> = emptySet(), allowed: Boolean = true,
        settings: HealthReminderSettings = deliverySettings, post: (HealthCareReminder) -> Boolean = { true }, cancel: (String) -> Unit = {}) =
        HealthCareReminderRuntime.reconcile(context, settings, now, zone, allowed, visible, post, cancel, names)

    @Test fun confirmedPlanDoesNotScheduleUntilExplicitlyRequestedAndReopensEncrypted(): Unit = fixture { names, store, issue ->
        assertNull(store.nextReminder()); assertTrue(store.reminders(issue.id).isEmpty())
        val at = System.currentTimeMillis() + 60000; val saved = schedule(names, store, issue, at)
        HealthCareStore(context, names.care).use { assertEquals(saved, it.reminder(saved.actionId)); assertEquals(at, it.nextReminder()) }
        context.openOrCreateDatabase(names.care, 0, null).use { db -> db.rawQuery("SELECT payload FROM action_reminders", null).use {
            assertTrue(it.moveToFirst()); assertFalse(it.getBlob(0).toString(Charsets.UTF_8).contains(saved.anchor))
        } }
        assertEquals(issue, store.concern(issue.id))
    }
    @Test fun deliveryIsPersistentAndRepeatedReconciliationDoesNotRepost(): Unit = fixture { names, store, issue ->
        val at = System.currentTimeMillis() + 1000; val saved = schedule(names, store, issue, at); var posts = 0
        repeat(4) { deliver(names, at + it, post = { posts++; true }) }
        assertEquals(1, posts); assertNull(store.nextReminder())
        HealthCareStore(context, names.care).use { assertEquals(HealthCareReminderState.DELIVERED, it.reminder(saved.actionId)!!.state) }
    }
    @Test fun snoozeReplacesOnlyThisActionAndRejectsStaleDelivery(): Unit = fixture { names, store, issue ->
        val now = System.currentTimeMillis(); val first = schedule(names, store, issue, now + 1000)
        val other = schedule(names, store, issue, now + 5000, issue.actions.last())
        val later = schedule(names, store, issue, now + 10000, token = first.token)
        assertNotEquals(first.token, later.token)
        assertThrows(HealthCareConflict::class.java) { store.markReminderDelivered(first.actionId, first.token, now + 1001) }
        assertEquals(other, store.reminder(other.actionId)); assertEquals(now + 5000, store.nextReminder())
    }
    @Test fun missingNotificationPermissionKeepsPendingWithoutBusyRetry(): Unit = fixture { names, store, issue ->
        val at = System.currentTimeMillis() + 1000; val value = schedule(names, store, issue, at)
        assertNull(deliver(names, at, allowed = false, post = { fail("Unexpected delivery"); true }))
        assertEquals(HealthCareReminderState.SCHEDULED, store.reminder(value.actionId)!!.state)
        deliver(names, at + 10); assertEquals(HealthCareReminderState.DELIVERED, store.reminder(value.actionId)!!.state)
    }
    @Test fun quietAndPauseDoNotConsumeThePendingReminder(): Unit = fixture { names, store, issue ->
        val at = System.currentTimeMillis() + 1000; val value = schedule(names, store, issue, at)
        assertEquals(at + 60000, deliver(names, at, settings = deliverySettings.copy(pauseUntil = at + 60000)))
        assertEquals(HealthCareReminderState.SCHEDULED, store.reminder(value.actionId)!!.state)
        assertEquals(at + 60000, deliver(names, at, post = { false }))
    }
    @Test fun newResultCancelsOldReminderWithoutAutomaticallyResolvingConcern(): Unit = fixture { names, store, issue ->
        val at = System.currentTimeMillis() + 2000; val value = schedule(names, store, issue, at)
        HealthRecordStore(context, names.records).use { it.save(HealthDraft(HealthMetric.GLUCOSE, mapOf("glucose" to "5.0"), "mmol/L", at - 1000, reference = "4-6")) }
        val cancelled = mutableListOf<String>()
        deliver(names, at, setOf(value.actionId), post = { fail("Stale reminder delivered"); true }, cancel = { cancelled += it })
        assertEquals(HealthCareReminderState.CANCELLED, store.reminder(value.actionId)!!.state)
        assertTrue(value.actionId in cancelled); assertEquals(HealthCareStage.REASSESS, store.concern(issue.id)!!.stage)
    }
    @Test fun privacyRevocationCancelsFutureAndVisibleRemindersWithoutReenabling(): Unit = fixture { names, store, issue ->
        val at = System.currentTimeMillis() + 60000; val value = schedule(names, store, issue, at)
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        val cancelled = mutableListOf<String>(); deliver(names, at - 100, setOf(value.actionId), cancel = { cancelled += it })
        assertEquals(HealthCareReminderState.CANCELLED, store.reminder(value.actionId)!!.state); assertTrue(value.actionId in cancelled)
        HealthPrivacyStore(context, names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, true, it.policy().version) }
        deliver(names, at + 1, post = { fail("Reminder resumed without confirmation"); true })
    }
    @Test fun completionAndReminderCancellationAreAtomicAndDoNotDeclareNormal(): Unit = fixture { names, store, issue ->
        val value = schedule(names, store, issue, System.currentTimeMillis() + 60000)
        assertThrows(IllegalArgumentException::class.java) { store.finishAction(issue.id, issue.revision, value.actionId, " ", System.currentTimeMillis()) }
        assertEquals(value, store.reminder(value.actionId)); assertEquals(issue, store.concern(issue.id))
        val saved = store.finishAction(issue.id, issue.revision, value.actionId, "已整理问题，仅用于测试", System.currentTimeMillis())
        assertEquals(HealthCareStage.REASSESS, saved.stage); assertNull(saved.target)
        assertEquals(HealthCareReminderState.CANCELLED, store.reminder(value.actionId)!!.state)
        assertEquals(HealthCareActionState.CONFIRMED, saved.actions.last().state)
        assertThrows(HealthCareConflict::class.java) { store.finishAction(issue.id, issue.revision, value.actionId, "重复", System.currentTimeMillis()) }
    }
    @Test fun pauseDeleteAndDisabledReviewRemoveScheduledDelivery(): Unit = fixture { names, store, issue ->
        val value = schedule(names, store, issue, System.currentTimeMillis() + 60000)
        val paused = store.update(issue.id, issue.revision, "fixture_pause") { it.copy(stage = HealthCareStage.PAUSED) }
        assertEquals(HealthCareReminderState.CANCELLED, store.reminder(value.actionId)!!.state)
        store.delete(paused.id, paused.revision); assertNull(store.reminder(value.actionId)); assertNull(store.nextReminder())
    }
    @Test fun indexTamperingIsDetected(): Unit = fixture { names, store, issue ->
        val value = schedule(names, store, issue, System.currentTimeMillis() + 60000)
        context.openOrCreateDatabase(names.care, 0, null).use { it.update("action_reminders", ContentValues().apply { put("due", value.dueAt + 1) }, null, null) }
        assertThrows(IllegalStateException::class.java) { store.reminder(value.actionId) }
    }
    @Test fun corruptCareStateCancelsItsNoticesWithoutBlockingSharedReminderScheduling(): Unit = fixture { names, store, issue ->
        val value = schedule(names, store, issue, System.currentTimeMillis() + 1000)
        context.openOrCreateDatabase(names.care, 0, null).use { it.update("concerns", ContentValues().apply { put("payload", byteArrayOf(1, 2, 3)) }, null, null) }
        val cancelled = mutableListOf<String>()
        assertNull(deliver(names, value.dueAt, setOf(value.actionId), post = { fail("Corrupt care state posted a notice"); true }, cancel = { cancelled += it }))
        assertEquals(listOf(value.actionId), cancelled)
    }
    @Test fun systemNotificationIsGenericPrivateAndRemovedAfterCompletion(): Unit = fixture { names, store, issue ->
        val manager = context.getSystemService(NotificationManager::class.java)
        assumeTrue(manager.areNotificationsEnabled())
        val channel = "health-care-fixture-${UUID.randomUUID()}"
        val tag = "health-care-fixture-${UUID.randomUUID()}"
        val value = schedule(names, store, issue, System.currentTimeMillis() + 1000)
        try {
            manager.createNotificationChannel(NotificationChannel(channel, "Health fixture", NotificationManager.IMPORTANCE_LOW))
            deliver(names, value.dueAt, post = {
                val intent = Intent(context, HealthCareActivity::class.java).putHealthNavigationFixture(names).putExtra("health_care_id", issue.id)
                val base = HealthReminderWork.notification(context, intent, 1907, R.string.health_care_followup_notice, deliverySettings)
                val notification = Notification.Builder.recoverBuilder(context, base).setChannelId(channel).build()
                manager.notify(tag, 1907, notification); true
            })
            val end = android.os.SystemClock.elapsedRealtime() + 5000
            while (manager.activeNotifications.none { it.tag == tag } && android.os.SystemClock.elapsedRealtime() < end) android.os.SystemClock.sleep(50)
            val posted = manager.activeNotifications.single { it.tag == tag }.notification
            assertEquals(Notification.VISIBILITY_PRIVATE, posted.visibility)
            assertEquals(context.getString(R.string.health_care_followup_notice), posted.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
            assertFalse(posted.extras.toString().contains(issue.actions.first().description))
            assertNull(posted.publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT))
            store.finishAction(issue.id, issue.revision, value.actionId, "已完成测试", System.currentTimeMillis())
            deliver(names, value.dueAt + 1, setOf(value.actionId), cancel = { manager.cancel(tag, 1907) })
            val cancelEnd = android.os.SystemClock.elapsedRealtime() + 5000
            while (manager.activeNotifications.any { it.tag == tag } && android.os.SystemClock.elapsedRealtime() < cancelEnd) android.os.SystemClock.sleep(50)
            assertTrue(manager.activeNotifications.none { it.tag == tag })
        } finally { manager.cancel(tag, 1907); manager.deleteNotificationChannel(channel) }
    }
    @Test fun schemaThreeUpgradePreservesConfirmedPlansAndConcern(): Unit = fixture { names, store, issue ->
        store.close()
        context.openOrCreateDatabase(names.care, 0, null).use {
            restoreHealthCareSchemaFive(it)
            it.execSQL("DROP TABLE evidence_reads"); it.execSQL("DROP TABLE action_reminders"); it.version = 3
        }
        HealthCareStore(context, names.care).use { upgraded ->
            assertEquals(issue, upgraded.concern(issue.id)); assertTrue(upgraded.reminders(issue.id).isEmpty())
            assertNotNull(schedule(names, upgraded, issue, System.currentTimeMillis() + 60000))
        }
    }
}
