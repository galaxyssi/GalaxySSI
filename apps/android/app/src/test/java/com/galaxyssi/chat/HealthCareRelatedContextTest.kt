package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareRelatedContextTest {
    private val now = 1_793_000_000_000L
    private val conversation = UUID.randomUUID().toString()
    private val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "source-v1",
        HealthCareAssessment(HealthCareRecordRef(UUID.randomUUID().toString(), 1), now, "6.3", "mmol/L", "4-6", setOf(HealthCareSignal.REPORT_HIGH)),
        conversationId = conversation)
    private val grant = HealthCareDiscussionGrant(conversation, UUID.randomUUID().toString(), issue.id, 1,
        "settings", "privacy", "a".repeat(64), now, "fixture-provider", "fixture-model", "high")
    private val related = mapOf(HealthMetric.WEIGHT to "b".repeat(64), HealthMetric.BLOOD_PRESSURE to "c".repeat(64))

    @Test fun legacyGrantsShareNoOtherMetricAndSelectedScopesRoundTrip() {
        assertFalse(grant.json().has("related_measurements"))
        assertTrue(HealthCareDiscussionGrant.from(grant.json()).related.isEmpty())
        val scoped = grant.copy(related = related)
        assertEquals(scoped, HealthCareDiscussionGrant.from(scoped.json()))
        assertThrows(IllegalArgumentException::class.java) { grant.copy(related = mapOf(HealthMetric.WEIGHT to "not-a-hash")) }
        assertThrows(IllegalArgumentException::class.java) {
            HealthCareDiscussionGrant.from(grant.json().put("related_measurements", JSONObject().put("UNKNOWN", "b".repeat(64))))
        }
    }
    @Test fun standingConsentFixesSelectedMetricsButAllowsNewSourceRevisions() {
        val auth = HealthCareResearchAuthorization(UUID.randomUUID().toString(), grant.copy(related = related), "d".repeat(64))
        val turn = auth.scope.copy(researchAuthorizationId = auth.id, turnId = UUID.randomUUID().toString())
        assertTrue(auth.permits(turn.copy(related = related + (HealthMetric.WEIGHT to "e".repeat(64)))))
        assertFalse(auth.permits(turn.copy(related = related - HealthMetric.WEIGHT)))
        assertFalse(auth.permits(turn.copy(related = related + (HealthMetric.HBA1C to "e".repeat(64)))))
        assertFalse(auth.copy(revokedAt = now).permits(turn))
        assertFalse(auth.copy(scope = grant).permits(turn))
    }
    @Test fun triggerIgnoresOrderingAndClockTicksButTracksSelectedEvidence() {
        val key = HealthCareResearchPolicy.trigger(issue, now, related)
        assertEquals(key, HealthCareResearchPolicy.trigger(issue, now + 100000, related.entries.reversed().associate { it.toPair() }))
        assertNotEquals(key, HealthCareResearchPolicy.trigger(issue, now, related + (HealthMetric.WEIGHT to "e".repeat(64))))
        assertNotEquals(key, HealthCareResearchPolicy.trigger(issue, now))
        assertEquals(HealthCareResearchPolicy.trigger(issue, now), HealthCareResearchPolicy.trigger(issue, now, emptyMap()))
        val auth = HealthCareResearchAuthorization(UUID.randomUUID().toString(), grant.copy(related = related), "d".repeat(64))
        val job = HealthCareResearchJob(UUID.randomUUID().toString(), auth.id, issue.id, conversation, key, 1, now, HealthCareResearchState.COMPLETED)
        assertEquals(HealthCareResearchState.COMPLETED, HealthCareResearchPolicy.displayState(issue, auth, job, now, related))
        assertNull(HealthCareResearchPolicy.displayState(issue, auth, job, now, related - HealthMetric.WEIGHT))
    }
    @Test fun withdrawingMeasurementsRemovesDerivedHistoryEvenWhenFeedbackIsShared() {
        val prior = grant.copy(turnId = UUID.randomUUID().toString(), related = related)
        val text = AgentTranscriptEntry(UUID.randomUUID().toString(), AgentTranscriptRole.ASSISTANT, "合成综合评估", now,
            conversationId = conversation, turnId = prior.turnId)
        val history = AgentConversationContext(conversation, "综合摘要", listOf(text), true, trackingPaused = true)
        listOf(false, true).forEach { feedback ->
            val next = grant.copy(feedbackHistoryShared = feedback)
            assertTrue(HealthCareDiscussionPolicy.historyForGrant(history, next) { prior }.turns.isEmpty())
            assertTrue(HealthCareDiscussionPolicy.historyForGrant(history, next.copy(related = related - HealthMetric.WEIGHT)) { prior }.turns.isEmpty())
            assertEquals(listOf(text), HealthCareDiscussionPolicy.historyForGrant(history, next.copy(related = related)) { prior }.turns)
            assertTrue(HealthCareDiscussionPolicy.historyForGrant(history, next.copy(related = related)) { null }.turns.isEmpty())
        }
        assertFalse(AgentConversationRecallTool.permittedHealthTurn(grant.copy(feedbackHistoryShared = true), prior))
        assertFalse(AgentConversationRecallTool.permittedHealthTurn(grant.copy(related = related), prior))
        assertTrue(AgentConversationRecallTool.permittedHealthTurn(grant.copy(feedbackHistoryShared = true, related = related), prior))
        assertFalse(AgentConversationRecallTool.permittedHealthTurn(grant.copy(feedbackHistoryShared = true, related = related), null))
    }
    @Test fun displayOnlyChangesDoNotChangeRelatedEvidenceBasis() {
        fun basis(value: HealthCareConcern) = HealthCareRelatedContext.basis(HealthCareRelatedMeasurement.of(value))
        assertEquals(basis(issue), basis(issue.copy(revision = 2, reviewNote = "Reviewed")))
        assertNotEquals(basis(issue), basis(issue.copy(inputVersion = "changed")))
        assertNotEquals(basis(issue), basis(issue.copy(context =
            HealthCareContext(issue.assessment.record!!, confirmedAt = now))))
    }
    @Test fun relatedChangesExplainTheNewReviewWithoutClaimingClinicalProgress() {
        val auth = UUID.randomUUID().toString()
        val priorGrant = grant.copy(researchAuthorizationId = auth, related = related)
        val input = HealthCareModelReviewInput("合成测试", "测量时间不同", "缺少测量情境", "核对资料",
            HealthCareReviewDecision.CLARIFY, listOf(HealthCareReviewEvent.SOURCE_CHANGE), listOf(issue.assessment.record!!),
            emptyList(), "", false, "无需提醒")
        val prior = HealthCareResearchJob(grant.turnId, auth, issue.id, conversation, "a".repeat(64), 1, now, HealthCareResearchState.COMPLETED)
        val review = HealthCareModelReview(priorGrant, prior.trigger, issue.inputVersion, now, input)
        val next = prior.copy(turnId = UUID.randomUUID().toString(), createdAt = now + 1, state = HealthCareResearchState.QUEUED)
        val changed = related + (HealthMetric.WEIGHT to "d".repeat(64))
        val handoff = HealthCareResearchHandoff.snapshot(issue, next, prior, issue, modelReview = review, related = changed)
        assertEquals("related_measurements_changed", handoff.getJSONArray("reasons").getString(0))
        assertFalse(handoff.getBoolean("elapsed_time_only"))
        assertFalse(handoff.getJSONObject("prior_model_assessment").getBoolean("clinical_verification"))
        assertFalse(review.reusable(grant.copy(turnId = next.turnId, approvedAt = now + 1)))
        assertTrue(review.reusable(grant.copy(turnId = next.turnId, approvedAt = now + 1, related = changed)))
    }
}
