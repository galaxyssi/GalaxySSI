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

    @Test fun partialFeedbackDoesNotPretendAnAlreadyReviewedActionBecameDueAgain() {
        val old = issue.copy(actions = listOf(action.copy(dueFrom = now - 1000)))
        val feedback = HealthCareFeedback(UUID.randomUUID().toString(), HealthCareFeedbackKind.BARRIER,
            "Synthetic barrier", now + 1, old.actions.single().basis, HealthCareQuestionPolicy.scope(old))
        val current = HealthCareFeedbackPolicy.apply(old, action.id, feedback)
        val value = handoff(current, old)
        assertEquals(listOf("action_feedback"), strings(value, "reasons"))
        assertEquals(listOf(action.id), strings(value, "new_feedback_action_ids"))
        assertTrue(strings(value, "new_outcome_action_ids").isEmpty())
        assertTrue(strings(value, "newly_due_action_ids").isEmpty())
        assertFalse(value.getBoolean("elapsed_time_only"))
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

    private val sourceGrant = HealthCareDiscussionGrant(conversation, prior.turnId, issue.id, 1, "settings", "privacy",
        "a".repeat(64), now, "fixture-provider", "fixture-model", "high")
    private fun source(excerpt: String = "Synthetic source body, not medical guidance."): HealthCareEvidence {
        val url = "https://example.test/source"
        val hash = "e".repeat(64)
        return HealthCareEvidence(UUID.randomUUID().toString(), sourceGrant, "fixture-read", url, "Synthetic source",
            AgentWebIntelligenceText.citationId(url, hash), hash, excerpt, now, now)
    }
    @Test fun sourceReuseRequiresSameConcernConversationDestinationAndPrivacy() {
        val next = sourceGrant.copy(turnId = job.turnId, approvedAt = job.createdAt)
        val read = source()
        assertTrue(HealthCareResearchHandoff.reusable(read, next))
        listOf(next.copy(concernId = UUID.randomUUID().toString()), next.copy(conversationId = UUID.randomUUID().toString()),
            next.copy(destination = "b".repeat(64)), next.copy(privacyVersion = "other"), next.copy(settingsVersion = "other"),
            next.copy(turnId = prior.turnId), next.copy(approvedAt = now - 1)).forEach {
            assertFalse(HealthCareResearchHandoff.reusable(read, it))
        }
    }
    @Test fun sourceHandoffIsBoundedHistoricalAndCannotAuthorizeANewPlan() {
        val reads = List(10) { source("Synthetic body. ".repeat(90)) }
        val value = HealthCareResearchHandoff.snapshot(issue, job, prior, issue, reads)
        val saved = value.getJSONArray("prior_automatic_source_reads")
        assertEquals(8, saved.length())
        val first = saved.getJSONObject(0)
        assertEquals(1000, first.getString("excerpt").length)
        assertTrue(first.getBoolean("excerpt_truncated"))
        assertFalse(first.getBoolean("medical_applicability_verified"))
        assertFalse(first.getBoolean("usable_for_new_plan"))
        assertFalse(first.has("grant")); assertFalse(first.has("evidence_id"))
        assertEquals(Instant.ofEpochMilli(now).toString(), first.getString("retrieved_at"))
        assertEquals(0, handoff().getJSONArray("prior_automatic_source_reads").length())
    }
    @Test fun completedResponseDoesNotPretendInitialResearchWasFinished() {
        val progress = handoff().getJSONObject("research_progress")
        assertTrue(progress.getBoolean("prior_response_completed"))
        assertTrue(progress.getBoolean("initial_source_review_pending"))
        assertFalse(progress.getBoolean("source_context_available"))
        assertFalse(progress.getBoolean("recorded_plan_exists"))
        assertEquals(0, progress.getInt("recorded_action_count"))
    }
    @Test fun priorSourcePlanOrActionPreventsBlindInitialPlanRecreation() {
        val withSource = HealthCareResearchHandoff.snapshot(issue, job, prior, issue, listOf(source()))
        val withPlan = HealthCareResearchHandoff.snapshot(issue, job, prior, issue, recordedPlanExists = true)
        val withAction = handoff(issue.copy(actions = listOf(action)))
        listOf(withSource, withPlan, withAction).forEach {
            assertFalse(it.getJSONObject("research_progress").getBoolean("initial_source_review_pending"))
        }
        assertTrue(withPlan.getJSONObject("research_progress").getBoolean("recorded_plan_exists"))
    }
}
