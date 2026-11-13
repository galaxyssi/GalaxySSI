package com.galaxyssi.chat

import android.app.Notification
import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

internal class HealthCareAppointmentFixture(private val context: Context) : AutoCloseable {
    val names = HealthOverviewDatabases(UUID.randomUUID().toString())
    val issue = HealthCareFollowUpTestFixture.confirmed(context, names)
    val repository = HealthCareEncounterRepository(context, names)
    val now = System.currentTimeMillis()
    val at = now + 20 * 60_000L
    val visit = HealthCareStore(context, names.care).use {
        it.saveEncounter(issue.id, it.concern(issue.id)!!.revision, UUID.randomUUID().toString(), null,
            HealthCareEncounterDraft("Synthetic appointment", "Synthetic clinic", HealthCareEncounterState.BOOKING_RECORDED,
                now + 7_200_000L, zone = "UTC", note = "Private synthetic appointment note"),
            UUID.randomUUID().toString(), now).encounter
    }
    fun snapshot() = repository.load(issue.id, selectedId = visit.id)
    fun schedule() = repository.scheduleAppointment(snapshot(), at, now)
    fun revise(draft: HealthCareEncounterDraft) = snapshot().let {
        repository.save(it, visit.id, it.selected!!.revision, draft, UUID.randomUUID().toString())
    }
    override fun close() {
        listOf(names.care, names.records, names.privacy, names.profile, names.reminders).forEach(context::deleteDatabase)
    }
}

class HealthCareAppointmentReminderDeviceTest {
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val settings = HealthReminderSettings(notifications = true, quiet = false)
    private fun fixture(run: (HealthCareAppointmentFixture) -> Unit) = HealthCareAppointmentFixture(context).use(run)
    private fun reconcile(f: HealthCareAppointmentFixture, now: Long, config: HealthReminderSettings = settings,
        visible: Set<String> = emptySet(), post: (HealthCareReminder) -> Boolean = { true }, cancel: (String) -> Unit = {}) =
        HealthCareReminderRuntime.reconcile(context, config, now, ZoneId.of("UTC"), true, visible, post, cancel, f.names)

    @Test fun explicitConfirmationSurvivesReopenWithoutChangingCareOrResearch() = fixture { f ->
        val before = f.snapshot()
        assertNull(before.reminder)
        val trigger = HealthCareResearchPolicy.trigger(before.issue, f.now)
        val saved = f.schedule()
        val after = f.snapshot()
        assertEquals(saved, after.reminder)
        assertEquals(before.issue, after.issue)
        assertEquals(before.selected, after.selected)
        assertEquals(trigger, HealthCareResearchPolicy.trigger(after.issue, f.now))
        HealthCareStore(context, f.names.care).use {
            assertEquals(saved, it.reminder(saved.storageKey))
            assertTrue(it.reminders(f.issue.id).isEmpty())
            assertTrue(it.researchJobs(f.issue.id).isEmpty())
        }
        context.openOrCreateDatabase(f.names.care, 0, null).use { db ->
            db.rawQuery("SELECT payload FROM action_reminders WHERE action_id=?", arrayOf(saved.storageKey)).use {
                assertTrue(it.moveToFirst())
                assertFalse(it.getBlob(0).toString(Charsets.UTF_8).contains(f.visit.id))
            }
        }
    }

    @Test fun staleConfirmationAndInvalidTimesNeverReplaceCurrentReminder() = fixture { f ->
        val initial = f.snapshot()
        val planned = requireNotNull(f.visit.details.plannedAt)
        listOf(f.now, planned, planned + 60_000L).forEach { at ->
            assertThrows(IllegalArgumentException::class.java) { f.repository.scheduleAppointment(initial, at, f.now) }
        }
        assertNull(f.snapshot().reminder)
        val first = f.schedule()
        val beforeChange = f.snapshot()
        val next = f.repository.scheduleAppointment(beforeChange, f.at + 60_000L, f.now)
        assertEquals(first.storageKey, next.storageKey)
        assertNotEquals(first.token, next.token)
        assertThrows(HealthCareConflict::class.java) { f.repository.cancelAppointment(beforeChange) }
        assertThrows(HealthCareConflict::class.java) { f.repository.scheduleAppointment(initial, f.at, f.now) }
        assertEquals(next, f.snapshot().reminder)
    }

    @Test fun reschedulingTheVisitRequiresNewConsentAndDoesNotCancelAnotherAction() = fixture { f ->
        val old = f.schedule()
        val other = HealthCareStore(context, f.names.care).use {
            val snapshot = f.snapshot()
            it.scheduleReminder(f.issue.id, f.issue.actions.first().id, snapshot.issue.revision, null,
                snapshot.privacy, snapshot.issue.inputVersion, f.at, f.now)
        }
        val revised = f.revise(f.visit.details.copy(plannedAt = f.visit.details.plannedAt!! + 3_600_000L))
        assertEquals(HealthCareReminderState.CANCELLED, f.snapshot().reminder!!.state)
        val next = f.schedule()
        assertNotEquals(old.token, next.token)
        assertEquals(revised.encounter.revision, next.appointment!!.revision)
        HealthCareStore(context, f.names.care).use { assertEquals(other, it.reminder(other.actionId)) }
    }

    @Test fun attendanceCancellationAndDeletionSuppressOldDelivery() = fixture { f ->
        val first = f.schedule()
        f.revise(f.visit.details.copy(state = HealthCareEncounterState.ATTENDED, attendedAt = f.now))
        assertFalse(f.snapshot().canRemind)
        assertEquals(HealthCareReminderState.CANCELLED, f.snapshot().reminder!!.state)
        f.revise(f.visit.details)
        f.schedule()
        f.revise(f.visit.details.copy(state = HealthCareEncounterState.CANCELLED))
        assertFalse(f.snapshot().canRemind)
        f.revise(f.visit.details)
        f.schedule()
        val snapshot = f.snapshot()
        f.repository.delete(snapshot, snapshot.selected!!)
        reconcile(f, first.dueAt, post = { fail("Deleted appointment was delivered"); false })
        HealthCareStore(context, f.names.care).use { assertEquals(HealthCareReminderState.CANCELLED, it.reminder(first.storageKey)!!.state) }
    }

    @Test fun quietHoursNeverDeliverAnExpiredAppointmentAndDeliveryIsOncePerToken() = fixture { f ->
        val saved = f.schedule()
        val planned = requireNotNull(f.visit.details.plannedAt)
        val deferred = planned + 60_000L
        assertEquals(deferred, reconcile(f, f.at, settings.copy(pauseUntil = deferred), post = { fail("Delivery during pause"); false }))
        reconcile(f, deferred, post = { fail("Expired appointment delivered"); false })
        assertEquals(HealthCareReminderState.CANCELLED, f.snapshot().reminder!!.state)
        val next = f.schedule()
        val posted = mutableListOf<HealthCareReminder>()
        repeat(2) { reconcile(f, next.dueAt + it, post = { posted += it; true }) }
        assertEquals(listOf(next), posted)
        assertEquals(HealthCareReminderState.DELIVERED, f.snapshot().reminder!!.state)
        val cancelled = mutableListOf<String>()
        assertTrue(HealthCareReminder.validStorageKey(saved.storageKey))
        assertTrue(HealthCareReminder.validStorageKey(saved.actionId))
        assertFalse(HealthCareReminder.validStorageKey("another:${saved.actionId}"))
        reconcile(f, planned, visible = setOf(saved.storageKey), cancel = { cancelled += it })
        assertEquals(listOf(saved.storageKey), cancelled)
    }

    @Test fun pausingConcernOrRevokingPermissionDoesNotReviveDelivery() = fixture { f ->
        f.schedule()
        HealthCareStore(context, f.names.care).use {
            val paused = it.update(f.issue.id, f.snapshot().issue.revision, "fixture_pause") { issue ->
                issue.copy(stage = HealthCareStage.PAUSED)
            }
            it.update(paused.id, paused.revision, "fixture_resume") { issue -> issue.copy(stage = f.issue.stage) }
        }
        assertEquals(HealthCareReminderState.CANCELLED, f.snapshot().reminder!!.state)
        val saved = f.schedule()
        val before = f.snapshot()
        HealthPrivacyStore(context, f.names.privacy).use { it.change(HealthPrivacyOption.PROFILE_CONTEXT, false, it.policy().version) }
        assertThrows(HealthPrivacyConflict::class.java) { f.repository.scheduleAppointment(before, f.at) }
        reconcile(f, f.at, post = { fail("Revoked appointment delivered"); false })
        HealthCareStore(context, f.names.care).use { assertEquals(HealthCareReminderState.CANCELLED, it.reminder(saved.storageKey)!!.state) }
    }

    @Test fun notificationUsesOnlyGenericCopyAndOpensTheExactVisit() = fixture { f ->
        val intent = HealthCareReminderRuntime.openIntent(context, f.schedule(), f.names)
        assertEquals(HealthCareEncountersActivity::class.java.name, intent.component!!.className)
        assertEquals(f.issue.id, intent.getStringExtra("health_care_id"))
        assertEquals(f.visit.id, intent.getStringExtra("health_encounter_id"))
        assertEquals(f.names, intent.healthNavigationDatabases())
        val notice = HealthReminderWork.notification(context, intent, 1926, R.string.health_appointment_notification, settings)
        assertEquals(Notification.VISIBILITY_PRIVATE, notice.visibility)
        assertNull(notice.publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT))
        assertFalse(notice.extras.toString().contains(f.visit.details.facility))
        assertFalse(notice.extras.toString().contains(f.visit.details.note))
    }
}
