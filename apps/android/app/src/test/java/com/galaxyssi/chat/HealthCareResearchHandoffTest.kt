package com.galaxyssi.chat

import java.time.Instant
import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareResearchHandoffTest {
    private val now = 1_793_000_000_000L
    private val conversation = UUID.randomUUID().toString()
    private val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "source-v1",
        HealthCareAssessment(HealthCareRecordRef(UUID.randomUUID().toString(), 1), now, "6.3", "mmol/L", "4-6",
            setOf(HealthCareSignal.REPORT_HIGH)), conversationId = conversation)
    private val prior = HealthCareResearchJob(UUID.randomUUID().toString(), UUID.randomUUID().toString(), issue.id,
        conversation, "a".repeat(64), 1, now, HealthCareResearchState.COMPLETED)
    private val job = prior.copy(turnId = UUID.randomUUID().toString(), createdAt = now + 2000,
        state = HealthCareResearchState.QUEUED)
    private val action = HealthCareAction(UUID.randomUUID().toString(), HealthCareActionKind.RECHECK, "Synthetic follow-up",
        "Scheduler fixture, not a clinical interval", "https://example.test", HealthCareActionState.CONFIRMED,
        now + 1000, now + 5000, now)
    private fun handoff(current: HealthCareConcern = issue, before: HealthCareConcern? = issue,
        previous: HealthCareResearchJob? = prior, run: HealthCareResearchJob = job) =
        HealthCareResearchHandoff.snapshot(current, run, previous, before)
    private fun strings(value: JSONObject, field: String) = value.getJSONArray(field).let { array ->
        (0 until array.length()).map(array::getString)
    }

    @Test fun deadlineUsesDurableRunTimeAndDoesNotInventNewEvidence() {
        val planned = issue.copy(actions = listOf(action))
        val value = handoff(planned, planned)
        assertEquals(listOf("review_due"), strings(value, "reasons"))
        assertTrue(value.getBoolean("elapsed_time_only"))
        assertEquals(listOf(action.id), strings(value, "newly_due_action_ids"))
        assertTrue(strings(value, "new_outcome_action_ids").isEmpty())
        assertEquals(Instant.ofEpochMilli(job.createdAt).toString(), value.getString("observed_at"))
        assertEquals(prior.turnId, value.getJSONObject("previous_review").getString("turn_id"))
        assertEquals(listOf("authorization_review"), strings(handoff(planned, planned,
            run = job.copy(createdAt = now + 999)), "reasons"))
    }

    @Test fun AlreadyReviewedDeadlineIsNotNewOnEveryRun() {
        val planned = issue.copy(actions = listOf(action.copy(dueFrom = now - 1000)))
        val value = handoff(planned, planned)
        assertEquals(listOf("authorization_review"), strings(value, "reasons"))
        assertFalse(value.getBoolean("elapsed_time_only"))
        assertTrue(strings(value, "newly_due_action_ids").isEmpty())
        assertEquals(listOf(action.id), strings(value, "due_action_ids"))
    }

    @Test fun NewMeasurementAndCorrectionAreDifferentFromHistoryChanges() {
        val updated = issue.copy(assessment = issue.assessment.copy(record = HealthCareRecordRef(UUID.randomUUID().toString(), 1)))
        assertEquals(listOf("new_measurement"), strings(handoff(updated), "reasons"))
        assertEquals(listOf("record_corrected"), strings(handoff(issue.copy(assessment = issue.assessment.copy(
            record = issue.assessment.record!!.copy(revision = 2)))), "reasons"))
        assertEquals(listOf("measurement_history_changed"), strings(handoff(issue.copy(inputVersion = "source-v2")), "reasons"))
    }

    @Test fun FeedbackContextAndTargetChangesDoNotGetDescribedAsElapsedTimeOnly() {
        val done = action.copy(id = UUID.randomUUID().toString(), state = HealthCareActionState.DONE, outcome = "Cannot follow this plan")
        val value = handoff(issue.copy(context = HealthCareContext(issue.assessment.record!!, confirmedAt = now),
            targetRevision = 1, actions = listOf(action, done)))
        assertEquals(listOf("measurement_context_changed", "reviewed_target_changed", "action_feedback", "review_due"), strings(value, "reasons"))
        assertFalse(value.getBoolean("elapsed_time_only"))
        assertEquals(listOf(done.id), strings(value, "new_outcome_action_ids"))
    }

    @Test fun ExistingFeedbackIsNotRepeatedButCorrectedFeedbackIsNew() {
        val done = action.copy(state = HealthCareActionState.DONE, outcome = "Not done yet")
        val baseline = issue.copy(actions = listOf(done))
        assertTrue(strings(handoff(baseline, baseline), "new_outcome_action_ids").isEmpty())
        assertEquals(listOf("action_feedback"), strings(handoff(issue.copy(actions = listOf(done.copy(outcome = "Barrier explained"))), baseline), "reasons"))
    }

    @Test fun ProposedDeclinedAndCompletedActionsAreNotDue() {
        listOf(HealthCareActionState.PROPOSED, HealthCareActionState.DECLINED, HealthCareActionState.DONE).forEach { state ->
            assertTrue(strings(handoff(issue.copy(actions = listOf(action.copy(state = state,
                outcome = if (state == HealthCareActionState.DONE) "Synthetic outcome" else "")))), "due_action_ids").isEmpty())
        }
    }

    @Test fun MissingRevisionCannotClaimNothingChanged() {
        val value = handoff(before = null)
        assertEquals(listOf("prior_context_unavailable"), strings(value, "reasons"))
        assertFalse(value.getBoolean("comparison_available")); assertFalse(value.getBoolean("elapsed_time_only"))
        assertTrue(value.isNull("new_outcome_action_ids"))
        assertTrue(value.isNull("newly_due_action_ids"))
    }

    @Test fun ForeignOrFutureReviewsCannotSupplyContext() {
        listOf(prior.copy(concernId = UUID.randomUUID().toString()), prior.copy(conversationId = UUID.randomUUID().toString()),
            prior.copy(turnId = job.turnId), prior.copy(createdAt = job.createdAt + 1),
            prior.copy(state = HealthCareResearchState.FAILED)).forEach {
            val value = handoff(previous = it)
            assertTrue(value.isNull("previous_review")); assertFalse(value.getBoolean("comparison_available"))
        }
    }

    @Test fun RevisionAndConversationMustMatchPreviousReviewExactly() {
        listOf(issue.copy(revision = 2), issue.copy(id = UUID.randomUUID().toString()),
            issue.copy(conversationId = UUID.randomUUID().toString())).forEach {
            assertFalse(handoff(before = it).getBoolean("comparison_available"))
        }
    }

    @Test fun FirstReviewDoesNotClaimUnchangedOrInventPriorReview() {
        val value = handoff(previous = null, before = null)
        assertEquals(listOf("initial_review"), strings(value, "reasons"))
        assertTrue(value.isNull("previous_review")); assertFalse(value.getBoolean("elapsed_time_only"))
    }

    @Test fun CurrentJobMustMatchCurrentConcernAndConversation() {
        listOf(job.copy(revision = 2), job.copy(concernId = UUID.randomUUID().toString()),
            job.copy(conversationId = UUID.randomUUID().toString())).forEach {
            assertThrows(IllegalArgumentException::class.java) { handoff(run = it) }
        }
    }

    @Test fun ManualSnapshotDoesNotPretendToBeAnAutomaticFollowUp() {
        assertFalse(JSONObject(HealthCareDiscussionPolicy.snapshot(issue)).has("automatic_follow_up"))
        val snapshot = JSONObject(HealthCareDiscussionPolicy.snapshot(issue, handoff()))
        assertEquals(listOf("authorization_review"), strings(snapshot.getJSONObject("automatic_follow_up"), "reasons"))
        assertEquals("6.3", snapshot.getJSONObject("assessment").getString("value"))
    }
}
