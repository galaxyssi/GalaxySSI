package com.galaxyssi.chat

import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareAgendaTest {
    private val now = 1_793_000_000_000L
    private val base = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "fixture",
        HealthCareAssessment(HealthCareRecordRef(UUID.randomUUID().toString(), 1), now, "6.3", "mmol/L", "4-6", setOf(HealthCareSignal.REPORT_HIGH)))
    private val action = HealthCareAction(UUID.randomUUID().toString(), HealthCareActionKind.CONTEXT,
        "Confirm source conditions", "Synthetic fixture", "Synthetic user plan", HealthCareActionState.CONFIRMED,
        now, now + 86_400_000, now, basis = HealthCareFollowUpPolicy.basis(base))
    private val issue = base.copy(actions = listOf(action))
    private fun item(c: HealthCareConcern = issue, a: HealthCareAction = action, r: HealthCareReminder? = null) = HealthCareAgenda.item(c, a, r)
    private fun reminder() = HealthCareFollowUpPolicy.schedule(issue, action, HealthCareSettings(true, "settings"),
        HealthPrivacyPolicy(version = "fixture-permission"), issue.inputVersion, now + 60_000, now)

    @Test fun confirmedPlanPreservesItsWindowWithoutInventingReminder() {
        assertEquals(0, item().bucket); assertEquals(now, item().plannedAt); assertNull(item().reminder)
        assertEquals(now + 86_400_000, item().action.dueUntil)
    }
    @Test fun noTimeIsDistinctFromToday() {
        val result = item(a = action.copy(dueFrom = null, dueUntil = null))
        assertNull(result.plannedAt); assertEquals(Long.MAX_VALUE, result.due)
    }
    @Test fun proposedAndStaleActionsNeedReview() {
        assertEquals(1, item(a = action.copy(state = HealthCareActionState.PROPOSED)).bucket)
        assertEquals(1, item(c = issue.copy(inputVersion = "new-result")).bucket)
        assertEquals(1, item(a = action.copy(basis = "")).bucket)
    }
    @Test fun pausedAndClosedPlansDoNotBecomeTodaysActions() {
        assertEquals(1, item(c = issue.copy(stage = HealthCareStage.PAUSED)).bucket)
        assertEquals(1, item(c = issue.copy(stage = HealthCareStage.CLOSED, reviewNote = "User review", reviewedBy = "User")).bucket)
    }
    @Test fun recordedOutcomesRemainRecordedEvenWhenContextChanges() {
        assertEquals(2, item(c = issue.copy(inputVersion = "new"), a = action.copy(state = HealthCareActionState.DONE, outcome = "Recorded")).bucket)
        assertEquals(2, item(a = action.copy(state = HealthCareActionState.DECLINED)).bucket)
    }
    @Test fun reminderOverridesWindowButCancellationDoesNotDeletePlan() {
        val notice = reminder()
        assertEquals(notice.dueAt, item(r = notice).plannedAt)
        assertEquals(now, item(r = notice.copy(state = HealthCareReminderState.CANCELLED)).plannedAt)
        assertEquals(0, item(r = notice.copy(state = HealthCareReminderState.CANCELLED)).bucket)
    }
    @Test fun deliveryDoesNotCompleteAction() {
        val result = item(r = reminder().copy(state = HealthCareReminderState.DELIVERED))
        assertEquals(0, result.bucket); assertEquals(HealthCareActionState.CONFIRMED, result.action.state)
    }
    @Test fun anotherConcernOrStaleAnchorCannotRescheduleAction() {
        assertEquals(now, item(r = reminder().copy(concernId = UUID.randomUUID().toString())).plannedAt)
        assertEquals(now, item(r = reminder().copy(anchor = "0".repeat(64))).plannedAt)
    }
    @Test fun localMidnightRatherThanFixedTwentyFourHoursHandlesDst() {
        val zone = ZoneId.of("America/New_York")
        val spring = Instant.parse("2026-03-08T05:00:00Z").toEpochMilli()
        val autumn = Instant.parse("2026-11-01T04:00:00Z").toEpochMilli()
        assertEquals(23 * 3_600_000L, HealthCareAgenda.dayEnd(spring, zone) - spring)
        assertEquals(25 * 3_600_000L, HealthCareAgenda.dayEnd(autumn, zone) - autumn)
    }
    @Test fun timezoneChangesMoveTheLocalDayBoundary() {
        assertNotEquals(HealthCareAgenda.dayEnd(now, ZoneId.of("Asia/Shanghai")), HealthCareAgenda.dayEnd(now, ZoneId.of("UTC")))
    }
}
