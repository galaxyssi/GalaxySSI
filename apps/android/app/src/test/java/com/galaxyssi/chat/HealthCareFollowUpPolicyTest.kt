package com.galaxyssi.chat

import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareFollowUpPolicyTest {
    private val now = 1_793_000_000_000L
    private val settings = HealthCareSettings(true, "settings")
    private val privacy = HealthPrivacyPolicy(version = "permission")
    private val unbound = HealthCareAction(UUID.randomUUID().toString(), HealthCareActionKind.CONTEXT,
        "Confirm report conditions", "Synthetic fixture", "https://example.test", HealthCareActionState.CONFIRMED,
        now + 86_400_000L, now + 172_800_000L, now)
    private val base = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "source",
        HealthCareAssessment(HealthCareRecordRef(UUID.randomUUID().toString(), 1), now, "6.3", "mmol/L", "4-6", setOf(HealthCareSignal.REPORT_HIGH)),
        actions = listOf(unbound))
    private val action = unbound.copy(basis = HealthCareFollowUpPolicy.basis(base))
    private val issue = base.copy(actions = listOf(action))
    private fun schedule(c: HealthCareConcern = issue, a: HealthCareAction = action, p: HealthPrivacyPolicy = privacy,
        s: HealthCareSettings = settings, source: String = issue.inputVersion, at: Long = now + 60_000) =
        HealthCareFollowUpPolicy.schedule(c, a, s, p, source, at, now)

    @Test fun reminderTimeDoesNotRewriteClinicalWindowOrTarget() {
        val value = schedule()
        assertEquals(now + 60000, value.dueAt); assertEquals(now + 86400000, action.dueFrom)
        assertNull(issue.target); assertEquals(value, HealthCareReminder.from(value.json()))
    }
    @Test fun onlyConfirmedActionsCanHaveReminders() {
        HealthCareActionState.entries.filter { it != HealthCareActionState.CONFIRMED }.forEach { state ->
            val a = action.copy(state = state, outcome = if (state == HealthCareActionState.DONE) "Fixture completed" else "")
            assertThrows(HealthCareConflict::class.java) { schedule(issue.copy(actions = listOf(a)), a) }
        }
        assertThrows(HealthCareConflict::class.java) { schedule(a = action.copy(id = UUID.randomUUID().toString())) }
    }
    @Test fun permissionAndSourceChangesPreventScheduling() {
        assertThrows(HealthCareConflict::class.java) { schedule(p = privacy.copy(metrics = false)) }
        assertThrows(HealthCareConflict::class.java) { schedule(p = privacy.copy(profile = false)) }
        assertThrows(HealthCareConflict::class.java) { schedule(s = settings.copy(enabled = false)) }
        assertThrows(HealthCareConflict::class.java) { schedule(source = "new-source") }
        assertThrows(HealthCareConflict::class.java) { schedule(c = issue.copy(stage = HealthCareStage.PAUSED)) }
    }
    @Test fun pastOrPresentReminderTimeIsRejected() {
        listOf(0L, now - 1, now).forEach { at -> assertThrows(IllegalArgumentException::class.java) { schedule(at = at) } }
    }
    @Test fun oldPlanCannotBeRearmedAgainstNewMeasurementsWithoutReview() {
        val newer = issue.copy(inputVersion = "new-source")
        assertThrows(HealthCareConflict::class.java) { schedule(c = newer, source = newer.inputVersion) }
        assertThrows(HealthCareConflict::class.java) { schedule(c = base, a = unbound) }
    }
    @Test fun discussionRevisionDoesNotInvalidateUnchangedActionButContextDoes() {
        val reminder = schedule()
        fun current(c: HealthCareConcern, p: HealthPrivacyPolicy = privacy) =
            HealthCareFollowUpPolicy.current(reminder, c, settings, p, c.inputVersion)
        assertTrue(current(issue.copy(revision = 3, conversationId = UUID.randomUUID().toString())))
        assertFalse(current(issue.copy(context = HealthCareContext(issue.assessment.record!!, confirmedAt = now))))
        assertFalse(current(issue.copy(inputVersion = "updated")))
        assertFalse(current(issue, privacy.copy(version = "revoked-and-reenabled")))
        assertFalse(current(issue.copy(actions = listOf(action.copy(description = "Changed action")))))
    }
    @Test fun completionRequiresOutcomeAndNeverDeclaresNormalOrMaintenance() {
        assertThrows(IllegalArgumentException::class.java) { HealthCareFollowUpPolicy.finish(issue, action.id, "  ", now) }
        val saved = HealthCareFollowUpPolicy.finish(issue, action.id, "  Prepared questions  ", now + 1)
        assertEquals("Prepared questions", saved.actions.single().outcome)
        assertEquals(HealthCareActionState.DONE, saved.actions.single().state)
        assertEquals(HealthCareStage.REASSESS, saved.stage); assertNull(saved.target)
        assertEquals(issue.assessment, saved.assessment)
        assertThrows(HealthCareConflict::class.java) { HealthCareFollowUpPolicy.finish(saved, action.id, "Again", now + 2) }
    }
    @Test fun completionDoesNotResumePausedTracking() {
        val saved = HealthCareFollowUpPolicy.finish(issue.copy(stage = HealthCareStage.PAUSED), action.id, "Prepared questions", now)
        assertEquals(HealthCareStage.PAUSED, saved.stage)
    }
    @Test fun quietHoursAndGlobalPauseDeferRatherThanChangeReminderTime() {
        val zone = ZoneId.of("Asia/Shanghai")
        val at = Instant.parse("2026-11-07T15:00:00Z").toEpochMilli()
        val end = Instant.parse("2026-11-08T00:00:00Z").toEpochMilli()
        assertEquals(end, HealthCareFollowUpPolicy.deliveryTime(at, HealthReminderSettings(), at, zone))
        assertEquals(end + 1000, HealthCareFollowUpPolicy.deliveryTime(at, HealthReminderSettings(pauseUntil = end + 1000), at, zone))
        assertEquals(at, HealthCareFollowUpPolicy.deliveryTime(at, HealthReminderSettings(quiet = false), at, zone))
    }
}
