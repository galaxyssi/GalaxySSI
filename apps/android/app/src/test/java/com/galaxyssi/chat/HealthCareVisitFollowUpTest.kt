package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareVisitFollowUpTest {
    private fun id() = UUID.randomUUID().toString()
    private val now = 1_793_000_000_000L
    private val issue = HealthCareConcern(id(), HealthMetric.GLUCOSE, 10, now, now, "fixture-source",
        HealthCareAssessment(HealthCareRecordRef(id(), 1), now, "6.3", "mmol/L", "4-6", setOf(HealthCareSignal.REPORT_HIGH)))
    private val visit = HealthCareEncounter(id(), issue.id, 9, issue.assessment.record, now, now,
        HealthCareEncounterDraft("合成就诊", state = HealthCareEncounterState.ATTENDED, attendedAt = now))
    private val start = HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.START, goal = "记录活动能力与睡眠")
    private fun apply(input: HealthCareVisitFollowUpInput = start, before: HealthCareVisitFollowUp? = null,
        source: HealthCareEncounter = visit, at: Long = now) = HealthCareVisitFollowUpPolicy.apply(
        issue.copy(revision = maxOf(issue.revision, before?.revision ?: 0)), source, before, input, id(), at)

    @Test fun journalNeedsAnAttendedVisitAndNeverCreatesAClinicalConclusion() {
        val value = apply()
        assertEquals(HealthCareVisitFollowUpState.ACTIVE, value.value.state)
        assertEquals("user_reported", value.json().getString("provenance"))
        assertEquals(issue.assessment.record, value.sourceRecord)
        listOf(HealthCareEncounterState.PLANNED, HealthCareEncounterState.BOOKING_RECORDED, HealthCareEncounterState.CANCELLED).forEach {
            assertThrows(HealthCareConflict::class.java) { apply(source = visit.copy(details = visit.details.copy(state = it, attendedAt = null, plannedAt = now))) }
        }
    }
    @Test fun checkinsKeepIndependentFieldsAndOnlyExplicitReviewFlagChangesJournalState() {
        val before = apply().value
        val entry = HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN, feelings = "主观变化", function = "活动记录", sleep = "睡眠记录", barriers = "执行困难")
        val after = apply(entry, before)
        assertEquals(before.state, after.value.state); assertEquals(entry, after.input)
        assertEquals(HealthCareVisitFollowUpState.REVIEW, apply(entry.copy(needsReview = true), before).value.state)
    }
    @Test fun pauseResumeArchiveReopenDoNotMeanRecovery() {
        val active = apply().value
        fun command(kind: HealthCareVisitFollowUpKind, value: HealthCareVisitFollowUp) = apply(HealthCareVisitFollowUpInput(kind, note = "用户选择"), value).value
        val paused = command(HealthCareVisitFollowUpKind.PAUSE, active)
        assertEquals(HealthCareVisitFollowUpState.PAUSED, paused.state)
        assertThrows(HealthCareConflict::class.java) { apply(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN, note = "不应写入"), paused) }
        val resumed = command(HealthCareVisitFollowUpKind.RESUME, paused)
        assertEquals(HealthCareVisitFollowUpState.REVIEW, resumed.state)
        val archived = command(HealthCareVisitFollowUpKind.ARCHIVE, resumed)
        assertEquals(HealthCareVisitFollowUpState.ARCHIVED, archived.state)
        assertEquals(HealthCareVisitFollowUpState.REVIEW, command(HealthCareVisitFollowUpKind.REOPEN, archived).state)
        assertThrows(HealthCareConflict::class.java) { command(HealthCareVisitFollowUpKind.RESUME, active) }
        assertThrows(HealthCareConflict::class.java) { command(HealthCareVisitFollowUpKind.REOPEN, active) }
    }
    @Test fun proposedMaintenanceAndAdjustmentRemainPendingReview() {
        val before = apply().value
        HealthCareVisitReviewDecision.entries.forEach { choice ->
            val result = apply(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.REVIEW, goal = "更新后的跟进内容", note = "复评说明", decision = choice), before)
            assertEquals(if (choice == HealthCareVisitReviewDecision.CONTINUE) HealthCareVisitFollowUpState.ACTIVE else HealthCareVisitFollowUpState.REVIEW, result.value.state)
            assertEquals("更新后的跟进内容", result.value.goal); assertEquals(before.id, result.value.id)
        }
    }
    @Test fun changedVisitRemainsUnreviewedAfterCheckinUntilExplicitReview() {
        val before = apply().value; val changed = visit.copy(revision = 10)
        val checkin = apply(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN, note = "新记录"), before, changed)
        assertEquals(visit.revision, checkin.value.encounterRevision); assertEquals(changed.revision, checkin.encounterRevision)
        val reviewed = apply(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.REVIEW, note = "已核对记录", decision = HealthCareVisitReviewDecision.CONTINUE), checkin.value, changed)
        assertEquals(changed.revision, reviewed.value.encounterRevision)
    }
    @Test fun ownershipAndSecondStartCannotReplaceAnExistingJournal() {
        val before = apply().value
        assertThrows(HealthCareConflict::class.java) { apply(before = before) }
        assertThrows(HealthCareConflict::class.java) { apply(source = visit.copy(concernId = id())) }
        assertThrows(HealthCareConflict::class.java) { apply(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.PAUSE, note = "暂停"), before.copy(encounterId = id())) }
    }
    @Test fun malformedAndEmptyInputsAreRejectedWithoutSilentlyTruncatingThem() {
        assertThrows(IllegalArgumentException::class.java) { start.copy(goal = " ") }
        assertThrows(IllegalArgumentException::class.java) { start.copy(goal = "x".repeat(1001)) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN, note = "x".repeat(2001)) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.REVIEW, note = "未选结论") }
        assertThrows(IllegalArgumentException::class.java) { start.copy(needsReview = true) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.PAUSE, feelings = "不能隐藏额外输入", note = "暂停") }
    }
    @Test fun receiptsRoundTripAndRejectClinicianProvenance() {
        val result = apply()
        assertEquals(result, HealthCareVisitFollowUpReceipt.from(result.json()))
        assertThrows(IllegalArgumentException::class.java) { HealthCareVisitFollowUpReceipt.from(result.json().put("provenance", "clinician_verified")) }
        assertThrows(IllegalArgumentException::class.java) { result.copy(expectedConcern = 1) }
    }
    @Test fun clockSkewCannotReorderHistoryOrRewriteTheOriginalStart() {
        val before = apply(at = now + 5000).value
        val after = apply(HealthCareVisitFollowUpInput(HealthCareVisitFollowUpKind.CHECK_IN, note = "时间回拨"), before, at = now - 5000)
        assertTrue(after.value.revision > before.revision); assertEquals(before.updatedAt, after.value.updatedAt)
        assertEquals(before.createdAt, after.value.createdAt); assertEquals(now - 5000, after.recordedAt)
    }
}
