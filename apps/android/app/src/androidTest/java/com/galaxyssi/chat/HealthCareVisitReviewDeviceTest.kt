package com.galaxyssi.chat

import android.app.Notification
import androidx.test.platform.app.InstrumentationRegistry
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareVisitReviewDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val settings = HealthReminderSettings(notifications = true, quiet = false)
    private fun fixture(test: (HealthCareVisitFollowUpFixture) -> Unit) = HealthCareVisitFollowUpFixture(context).use { it.start(); test(it) }
    private fun schedule(f: HealthCareVisitFollowUpFixture) = f.repository.schedule(f.snapshot(), System.currentTimeMillis() + 60000)
    private fun deliver(f: HealthCareVisitFollowUpFixture, now: Long, allowed: Boolean = true, config: HealthReminderSettings = settings,
        visible: Set<String> = emptySet(), post: (HealthCareReminder) -> Boolean = { true }, cancel: (String) -> Unit = {}) =
        HealthCareReminderRuntime.reconcile(context, config, now, ZoneId.of("UTC"), allowed, visible, post, cancel, f.names)
    private fun command(f: HealthCareVisitFollowUpFixture, kind: HealthCareVisitFollowUpKind) =
        f.record(HealthCareVisitFollowUpInput(kind, note = "Synthetic user decision"))

    @Test fun explicitScheduleIsEncryptedAndDoesNotAlterClinicalPlan(): Unit = fixture { f ->
        val before = f.snapshot(); assertNull(before.reminder)
        val saved = schedule(f); val after = f.snapshot()
        assertEquals(saved, after.reminder); assertEquals(before.followUp, after.followUp)
        assertEquals(before.visit.issue.actions, after.visit.issue.actions.filter { it.visitReview == null })
        assertEquals(before.visit.issue.assessment, after.visit.issue.assessment); assertEquals(before.visit.issue.target, after.visit.issue.target)
        assertFalse(after.visit.issue.actions.last().json().toString().contains(before.followUp!!.goal))
        context.openOrCreateDatabase(f.names.care, 0, null).use { db -> db.rawQuery("SELECT payload FROM action_reminders", null).use {
            assertTrue(it.moveToFirst()); assertFalse(it.getBlob(0).toString(Charsets.UTF_8).contains(saved.anchor))
        } }
    }
    @Test fun invalidDateAndStaleCommandsCannotPartiallyCreateActions(): Unit = fixture { f ->
        val before = f.snapshot(); val now = System.currentTimeMillis()
        assertThrows(IllegalArgumentException::class.java) { f.repository.schedule(before, now - 1, now) }
        assertEquals(before, f.snapshot())
        schedule(f)
        assertThrows(HealthCareConflict::class.java) { f.repository.schedule(before, now + 60000) }
        assertEquals(1, f.snapshot().visit.issue.actions.count { it.visitReview != null })
    }
    @Test fun reschedulingRotatesTokenAndOrdinaryCheckinsPreserveIt(): Unit = fixture { f ->
        val first = schedule(f); val second = schedule(f)
        assertEquals(first.actionId, second.actionId); assertNotEquals(first.token, second.token)
        f.record(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN, note = "Synthetic observation"))
        assertEquals(second, f.snapshot().reminder)
        HealthCareStore(context, f.names.care).use { store ->
            assertTrue(store.visitReviewCurrent(store.concern(f.issue.id)!!, store.concern(f.issue.id)!!.actions.last()))
            assertThrows(HealthCareConflict::class.java) { store.markReminderDelivered(first.actionId, first.token, second.dueAt) }
        }
    }
    @Test fun pauseAndResumeRequireNewReminderConfirmation(): Unit = fixture { f ->
        schedule(f); command(f, HealthCareVisitFollowUpKind.PAUSE)
        assertEquals(HealthCareReminderState.CANCELLED, f.snapshot().reminder!!.state)
        command(f, HealthCareVisitFollowUpKind.RESUME)
        assertEquals(HealthCareReminderState.CANCELLED, f.snapshot().reminder!!.state)
        assertEquals(HealthCareReminderState.SCHEDULED, schedule(f).state)
    }
    @Test fun archiveAndReopenNeverResumeOldDelivery(): Unit = fixture { f ->
        val first = schedule(f); command(f, HealthCareVisitFollowUpKind.ARCHIVE); command(f, HealthCareVisitFollowUpKind.REOPEN)
        var posts = 0; deliver(f, first.dueAt, post = { posts++; true })
        assertEquals(0, posts); assertEquals(HealthCareReminderState.CANCELLED, f.snapshot().reminder!!.state)
    }
    @Test fun changedGoalInvalidatesOnlyJournalReminder(): Unit = fixture { f ->
        val journal = schedule(f)
        val other = HealthCareStore(context, f.names.care).use { store ->
            val issue = store.concern(f.issue.id)!!
            store.scheduleReminder(issue.id, issue.actions.first().id, issue.revision, null,
                HealthPrivacyStore(context, f.names.privacy).use { it.policy() }, issue.inputVersion, journal.dueAt, System.currentTimeMillis())
        }
        f.record(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.REVIEW, goal = "New synthetic goal", note = "User revision",
            decision = HealthCareVisitReviewDecision.CONTINUE))
        assertEquals(HealthCareReminderState.CANCELLED, f.snapshot().reminder!!.state)
        HealthCareStore(context, f.names.care).use { assertEquals(other, it.reminder(other.actionId)) }
    }
    @Test fun revisedVisitNeedsAcknowledgementBeforeRescheduling(): Unit = fixture { f ->
        schedule(f)
        HealthCareStore(context, f.names.care).use { store -> store.saveEncounter(f.issue.id, store.concern(f.issue.id)!!.revision,
            f.visit.id, f.visit.revision, f.visit.details.copy(note = "Synthetic source revision"), UUID.randomUUID().toString(), System.currentTimeMillis()) }
        assertEquals(HealthCareReminderState.CANCELLED, f.snapshot().reminder!!.state)
        assertThrows(HealthCareConflict::class.java) { schedule(f) }
        f.record(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.REVIEW, note = "Source checked", decision = HealthCareVisitReviewDecision.CONTINUE))
        assertEquals(HealthCareReminderState.SCHEDULED, schedule(f).state)
    }
    @Test fun deletionKeepsAuditButCannotResurrectDelivery(): Unit = fixture { f ->
        val first = schedule(f); val before = f.snapshot(); f.repository.delete(before)
        assertNull(f.snapshot().followUp)
        HealthCareStore(context, f.names.care).use { store ->
            assertEquals(HealthCareReminderState.CANCELLED, store.reminder(first.actionId)!!.state)
            assertTrue(store.concern(f.issue.id)!!.actions.last().sourceInvalidated)
        }
        assertThrows(HealthCareConflict::class.java) { f.repository.schedule(before, first.dueAt) }
        f.start(); assertNotEquals(first.actionId, schedule(f).actionId)
    }
    @Test fun foregroundSuppressesOnlyThisJournalAndDatabase(): Unit = fixture { f ->
        val first = schedule(f); val owner = Any(); var posts = 0
        try {
            HealthCareVisitReviewVisibility.show(owner, f.names.care, f.visit.id)
            deliver(f, first.dueAt, post = { posts++; true })
            assertEquals(0, posts); assertEquals(HealthCareReminderState.DELIVERED, f.snapshot().reminder!!.state)
            val next = schedule(f)
            HealthCareVisitReviewVisibility.show(owner, "other-database", f.visit.id)
            deliver(f, next.dueAt, post = { posts++; true }); assertEquals(1, posts)
        } finally { HealthCareVisitReviewVisibility.hide(owner) }
    }
    @Test fun openingJournalRemovesExistingNoticeAndLeavingAllowsNewOne(): Unit = fixture { f ->
        val first = schedule(f); deliver(f, first.dueAt)
        val owner = Any(); val cancelled = mutableListOf<String>()
        try {
            HealthCareVisitReviewVisibility.show(owner, f.names.care, f.visit.id)
            deliver(f, first.dueAt + 1, visible = setOf(first.actionId), cancel = { cancelled += it })
            assertEquals(listOf(first.actionId), cancelled)
        } finally { HealthCareVisitReviewVisibility.hide(owner) }
        val next = schedule(f); var posts = 0
        repeat(3) { deliver(f, next.dueAt + it, post = { posts++; true }) }
        assertEquals(1, posts)
    }
    @Test fun permissionsQuietHoursAndPausePreservePendingReview(): Unit = fixture { f ->
        val first = schedule(f)
        assertNull(deliver(f, first.dueAt, allowed = false))
        assertEquals(HealthCareReminderState.SCHEDULED, f.snapshot().reminder!!.state)
        assertEquals(first.dueAt + 60000, deliver(f, first.dueAt, config = settings.copy(pauseUntil = first.dueAt + 60000)))
        deliver(f, first.dueAt + 60000)
        assertEquals(HealthCareReminderState.DELIVERED, f.snapshot().reminder!!.state)
    }
    @Test fun revokedPrivacyInvalidatesPendingAndOpenEditors(): Unit = fixture { f ->
        val first = schedule(f); val before = f.snapshot()
        HealthPrivacyStore(context, f.names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        assertThrows(HealthPrivacyConflict::class.java) { f.repository.schedule(before, first.dueAt) }
        deliver(f, first.dueAt, post = { fail("Revoked reminder was posted"); true })
        HealthCareStore(context, f.names.care).use { assertEquals(HealthCareReminderState.CANCELLED, it.reminder(first.actionId)!!.state) }
    }
    @Test fun notificationOpensTheScopedJournalAndHidesPrivateFields(): Unit = fixture { f ->
        val first = schedule(f); val intent = HealthCareReminderRuntime.openIntent(context, first, f.names)
        assertEquals(HealthCareVisitFollowUpActivity::class.java.name, intent.component!!.className)
        assertEquals(f.issue.id, intent.getStringExtra("health_care_id")); assertEquals(f.visit.id, intent.getStringExtra("health_encounter_id"))
        assertEquals(f.names, intent.healthNavigationDatabases())
        val notice = HealthReminderWork.notification(context, intent, 1908, R.string.health_visit_review_notice_private, settings)
        assertEquals(Notification.VISIBILITY_PRIVATE, notice.visibility)
        assertFalse(notice.extras.toString().contains(f.snapshot().followUp!!.goal))
        assertNull(notice.publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT))
    }
}
