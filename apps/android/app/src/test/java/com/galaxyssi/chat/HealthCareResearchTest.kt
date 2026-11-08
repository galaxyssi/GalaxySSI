package com.galaxyssi.chat

import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class HealthCareResearchTest {
    private val now = 1_793_000_000_000L
    private val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "source-v1",
        HealthCareAssessment(HealthCareRecordRef(UUID.randomUUID().toString(), 1), now, "6.3", "mmol/L", "4-6", setOf(HealthCareSignal.REPORT_HIGH)))
    private val grant = HealthCareDiscussionGrant(UUID.randomUUID().toString(), UUID.randomUUID().toString(), issue.id,
        1, "settings", "privacy", "a".repeat(64), now, "fixture-model-provider", "fixture-model", "high")
    private val authorization = HealthCareResearchAuthorization(UUID.randomUUID().toString(), grant, "b".repeat(64))
    private val ongoing = grant.copy(researchAuthorizationId = authorization.id)
    private val action = HealthCareAction(UUID.randomUUID().toString(), HealthCareActionKind.RECHECK, "Discuss repeat testing",
        "Synthetic fixture", "https://example.test", HealthCareActionState.CONFIRMED, now + 1000, now + 2000, now)
    private fun key(c: HealthCareConcern = issue, at: Long = now) = HealthCareResearchPolicy.trigger(c, at)

    @Test fun consentAndTurnBindingsRoundTripWithoutChangingManualGrantEncoding() {
        assertEquals(authorization, HealthCareResearchAuthorization.from(authorization.json()))
        assertEquals(ongoing, HealthCareDiscussionGrant.from(ongoing.json()))
        assertFalse(grant.json().has("research_authorization"))
        assertEquals(grant, HealthCareDiscussionGrant.from(grant.json()))
    }
    @Test fun standingConsentRequiresItsOwnIdentifierAndFixedDestination() {
        assertTrue(authorization.permits(ongoing))
        listOf(grant, ongoing.copy(researchAuthorizationId = UUID.randomUUID().toString()),
            ongoing.copy(concernId = UUID.randomUUID().toString()), ongoing.copy(conversationId = UUID.randomUUID().toString()),
            ongoing.copy(settingsVersion = "new"), ongoing.copy(privacyVersion = "new"), ongoing.copy(destination = "c".repeat(64)),
            ongoing.copy(modelId = "other"), ongoing.copy(targetId = "other"), ongoing.copy(effort = "low"))
            .forEach { assertFalse(it.toString(), authorization.permits(it)) }
        assertFalse(authorization.copy(revokedAt = now).permits(ongoing))
    }
    @Test fun newTurnsNeedFreshRevisionGrantButNotNewStandingConsent() {
        assertTrue(authorization.permits(ongoing.copy(turnId = UUID.randomUUID().toString(), revision = 2, approvedAt = now + 1000)))
        assertThrows(IllegalArgumentException::class.java) { authorization.copy(scope = ongoing) }
    }
    @Test fun displayChangesAndFuturePlansDoNotCauseSelfTriggeredResearch() {
        assertEquals(key(), key(issue.copy(revision = 2, updatedAt = now + 1, conversationId = UUID.randomUUID().toString(),
            stage = HealthCareStage.REVIEW_EVIDENCE, reviewNote = "Displayed again", reviewedBy = "user")))
        assertEquals(key(), key(issue.copy(actions = listOf(action))))
        assertEquals(key(), key(issue.copy(actions = listOf(action.copy(state = HealthCareActionState.PROPOSED)))))
    }
    @Test fun newMeasurementsContextTargetsAndOutcomesTriggerResearch() {
        assertNotEquals(key(), key(issue.copy(inputVersion = "source-v2")))
        assertNotEquals(key(), key(issue.copy(context = HealthCareContext(issue.assessment.record!!, confirmedAt = now))))
        assertNotEquals(key(), key(issue.copy(targetRevision = 1)))
        assertNotEquals(key(), key(issue.copy(actions = listOf(action.copy(state = HealthCareActionState.DONE, outcome = "Result recorded")))))
    }
    @Test fun dueDeadlineChangesKeyOnceRatherThanEveryClockTick() {
        val planned = issue.copy(actions = listOf(action))
        assertNotEquals(key(planned), key(planned, now + 1000))
        assertEquals(key(planned, now + 1000), key(planned, now + 900000))
        assertNotEquals(key(planned, now + 1000), key(planned.copy(actions = listOf(action.copy(dueFrom = now + 20000, dueUntil = now + 30000))), now + 1000))
    }
    @Test fun actionOrderingDoesNotChangeEvidenceIdentity() {
        val second = action.copy(id = UUID.randomUUID().toString(), state = HealthCareActionState.DONE, outcome = "Fixture outcome")
        assertEquals(key(issue.copy(actions = listOf(action, second)), now + 1000),
            key(issue.copy(actions = listOf(second, action)), now + 1000))
    }
    @Test fun pausedClosedAndRemovedDataAreNotEligible() {
        assertTrue(HealthCareResearchPolicy.eligible(issue))
        assertFalse(HealthCareResearchPolicy.eligible(issue.copy(stage = HealthCareStage.PAUSED)))
        assertFalse(HealthCareResearchPolicy.eligible(issue.copy(stage = HealthCareStage.CLOSED, reviewNote = "Reviewed", reviewedBy = "user")))
        assertFalse(HealthCareResearchPolicy.eligible(issue.copy(assessment = issue.assessment.copy(record = null,
            signals = setOf(HealthCareSignal.SOURCE_REMOVED)))))
        assertFalse(HealthCareResearchPolicy.eligible(issue.copy(assessment = issue.assessment.copy(signals = setOf(HealthCareSignal.SOURCE_REMOVED)))))
    }
    @Test fun terminalJobsCannotRestartOrChangeOutcome() {
        HealthCareResearchState.entries.forEach { before -> HealthCareResearchState.entries.forEach { after ->
            val allowed = HealthCareResearchPolicy.transition(before, after)
            if (before !in setOf(HealthCareResearchState.QUEUED, HealthCareResearchState.DISPATCHED)) assertEquals(before == after, allowed)
            if (before == HealthCareResearchState.DISPATCHED && after == HealthCareResearchState.QUEUED) assertFalse(allowed)
        } }
        assertFalse(HealthCareResearchPolicy.transition(HealthCareResearchState.QUEUED, HealthCareResearchState.COMPLETED))
    }
    @Test fun jobsContainNoRawMeasurementAndPreserveExactTurnOnRoundTrip() {
        val job = HealthCareResearchJob(UUID.randomUUID().toString(), authorization.id, issue.id, grant.conversationId, key(), 1, now)
        assertEquals(job, HealthCareResearchJob.from(job.json()))
        assertFalse(job.json().has("assessment")); assertFalse(job.json().has("snapshot"))
    }
}
