package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareMaintenanceTest {
    private val now = 1_793_000_000_000L
    private fun id() = UUID.randomUUID().toString()
    private val samples = (0..2).map { HealthCareSample(HealthCareRecordRef(id(), 1), HealthMetric.WEIGHT,
        now - it * 86_400_000L, mapOf("weight" to (60 + it).toString()), "kg", "50-70", "resting", "unspecified", "manual", "", "") }
    private val base = HealthCareConcern(id(), HealthMetric.WEIGHT, 1, now, now, "input1",
        HealthCareAssessment(samples[0].record, now, "60", "kg", "50-70", emptySet(), sample = samples[0], series = HealthCareSeries(samples, false)))
    private val issue = base.copy(target = HealthCareTarget("weight", "50", "70", "kg", "Synthetic fixture, not clinical advice", "fixture source", "user", now,
        planId = id(), basis = HealthCareTargetPolicy.basis(base)))
    private val grant = HealthCareDiscussionGrant(id(), id(), issue.id, issue.revision, "settings", "privacy", "a".repeat(64), now, "fixture", "fixture", "high")
    private val applicability = HealthCareApplicability(HealthCareApplicabilityMode.INDIVIDUALIZED,
        listOf(HealthCareApplicabilityCheck(HealthCareApplicabilityField.metric, HealthCareApplicabilityOperator.EQUALS, "WEIGHT", 0)), emptyList(), emptyList())
    private val action = HealthCareAction(id(), HealthCareActionKind.RECHECK, "Synthetic reassessment", "Synthetic window, not advice", "fixture source",
        dueFrom = now + 10000, dueUntil = now + 20000)
    private val proposal = HealthCareMaintenanceProposal("Synthetic maintenance review", samples.map { it.record }, 0, 0, applicability)
    private val plan = HealthCarePlan(grant, issue.inputVersion, now, "b".repeat(64), "Not independently clinically verified",
        listOf(HealthCarePlanSource("Synthetic source", "https://example.test", "fixture", "Synthetic only")), listOf(action),
        applicability = mapOf(action.id to applicability), maintenance = proposal)
    private fun gaps(p: HealthCarePlan = plan, c: HealthCareConcern = issue, time: Long = now) = HealthCareMaintenancePolicy.gaps(p, c, time)
    private fun accept(p: HealthCarePlan = plan, c: HealthCareConcern = issue) = HealthCarePlanPolicy.accept(p, c, setOf(action.id), now, acceptMaintenance = true)

    @Test fun proposalAndAcceptanceRoundTripWithoutAutomaticConfirmation() {
        assertEquals(plan, HealthCarePlan.from(JSONObject(plan.json().toString())))
        assertFalse(plan.maintenanceSelected); assertNull(issue.maintenance); assertTrue(gaps().isEmpty())
        assertEquals(HealthCareStage.WAITING_RESULTS, HealthCarePlanPolicy.accept(plan, issue, setOf(action.id), now).stage)
        val saved = accept()
        assertEquals(HealthCareStage.MAINTENANCE, saved.stage); assertEquals(plan.id, saved.maintenance!!.planId)
        assertEquals(saved, HealthCareConcern.from(JSONObject(saved.json().toString())))
        assertEquals(action.dueFrom, saved.nextDue); assertTrue(saved.open)
    }
    @Test fun numericTargetsAreNotInventedWhenOnlyRiskReviewIsAppropriate() {
        val risk = plan.copy(maintenance = proposal.copy(goalBasis = HealthCareMaintenanceBasis.RISK_REVIEW))
        assertTrue(gaps(risk, base).isEmpty()); assertNull(accept(risk, base).target)
        assertTrue(HealthCareMaintenanceGap.TARGET in gaps(risk, issue))
        assertTrue(HealthCareMaintenanceGap.TARGET in gaps(plan, base))
    }
    @Test fun missingRecheckSelectionCannotAcceptOrSilentlySchedule() {
        assertThrows(IllegalArgumentException::class.java) { HealthCarePlanPolicy.accept(plan, issue, emptySet(), now, acceptMaintenance = true) }
        assertThrows(IllegalArgumentException::class.java) { HealthCarePlanPolicy.accept(plan, issue, setOf(action.id), now, true, true) }
        assertTrue(HealthCareMaintenanceGap.RECHECK in gaps(time = action.dueFrom!!))
        assertTrue(HealthCareMaintenanceGap.RECHECK in gaps(plan.copy(actions = listOf(action.copy(dueFrom = null, dueUntil = null)))))
    }
    @Test fun oneResultCorrectionAndCherryPickingNeverEstablishAWindow() {
        assertThrows(IllegalArgumentException::class.java) { proposal.copy(records = listOf(samples.first().record)) }
        assertThrows(IllegalArgumentException::class.java) { proposal.copy(records = listOf(samples[0].record, samples[0].record.copy(revision = 2))) }
        assertTrue(HealthCareMaintenanceGap.HISTORY in gaps(plan.copy(maintenance = proposal.copy(records = listOf(samples[0].record, samples[2].record)))))
        assertTrue(HealthCareMaintenanceGap.HISTORY in gaps(plan.copy(maintenance = proposal.copy(records = proposal.records.reversed()))))
        assertTrue(HealthCareMaintenanceGap.HISTORY in gaps(c = issue.copy(assessment = issue.assessment.copy(series = HealthCareSeries(samples, true)))))
        val tied = samples[1].copy(record = HealthCareRecordRef("00000000-0000-0000-0000-000000000001", 1))
        val tiedIssue = issue.copy(assessment = issue.assessment.copy(series = HealthCareSeries(listOf(samples[0], samples[1], tied, samples[2]), false)))
        assertTrue(HealthCareMaintenanceGap.HISTORY in gaps(plan.copy(maintenance = proposal.copy(records = proposal.records.take(2))), tiedIssue))
    }
    @Test fun changedConditionsUnitsSourcesAndMissingContextBlockReview() {
        listOf(samples[1].copy(condition = "unspecified"), samples[1].copy(condition = "after_exercise"), samples[1].copy(unit = "lb"),
            samples[1].copy(origin = "different-lab"), samples[1].copy(reference = "55-75")).forEach { changed ->
            val c = issue.copy(assessment = issue.assessment.copy(series = HealthCareSeries(listOf(samples[0], changed, samples[2]), false)))
            assertTrue(HealthCareMaintenanceGap.COMPARABILITY in gaps(c = c))
        }
        val stale = issue.copy(inputVersion = "new-source")
        assertTrue(HealthCareMaintenanceGap.TARGET in gaps(c = stale))
    }
    @Test fun oldActionsAndUnresolvedApplicabilityCannotBeHiddenByMaintenance() {
        assertTrue(HealthCareMaintenanceGap.OPEN_ACTIONS in gaps(c = issue.copy(actions = listOf(action))))
        val missing = proposal.copy(applicability = applicability.copy(missingInformation = listOf("Missing clinical context")))
        assertTrue(HealthCareMaintenanceGap.APPLICABILITY in gaps(plan.copy(maintenance = missing)))
        assertThrows(IllegalArgumentException::class.java) { accept(plan.copy(maintenance = missing)) }
    }
    @Test fun deadlineTargetChangeAndMissingLegacyEvidenceReopenAssessment() {
        val saved = accept()
        assertFalse(HealthCareMaintenancePolicy.needsReassessment(saved, now + 1))
        assertTrue(HealthCareMaintenancePolicy.needsReassessment(saved, action.dueFrom!!))
        assertTrue(HealthCareMaintenancePolicy.needsReassessment(saved.copy(target = saved.target!!.copy(high = "65")), now))
        assertTrue(HealthCareMaintenancePolicy.needsReassessment(saved.copy(maintenance = null), now))
        assertFalse(HealthCareMaintenancePolicy.needsReassessment(saved.copy(stage = HealthCareStage.PAUSED), action.dueUntil!!))
        val changed = HealthCarePolicy.reconcile(saved, saved.metric, saved.assessment, "new-source", now + 1)!!
        assertEquals(HealthCareStage.REASSESS, changed.stage); assertEquals(saved.maintenance, changed.maintenance)
    }
    @Test fun malformedIndicesExtraAuthorityAndDuplicateRecordsAreRejected() {
        assertThrows(IllegalArgumentException::class.java) { HealthCareMaintenanceProposal.from(proposal.json().put("confirmed", true)) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareMaintenanceProposal.from(proposal.json().put("recheck_index", 0.1)) }
        assertThrows(IllegalArgumentException::class.java) { plan.copy(maintenance = proposal.copy(recheckIndex = 7)) }
        assertThrows(IllegalArgumentException::class.java) { plan.copy(maintenanceSelected = true) }
        assertEquals(proposal, HealthCareMaintenanceProposal.from(proposal.json()))
    }
    @Test fun earlierAcceptedActionReopensBeforeTheMaintenanceRecheck() {
        val saved = accept()
        val earlier = action.copy(id = id(), kind = HealthCareActionKind.CONTEXT,
            state = HealthCareActionState.CONFIRMED, confirmedAt = now, dueFrom = now + 1000,
            basis = HealthCareFollowUpPolicy.basis(saved))
        val combined = saved.copy(actions = saved.actions + earlier)
        assertFalse(HealthCareMaintenancePolicy.needsReassessment(combined, now))
        assertTrue(HealthCareMaintenancePolicy.needsReassessment(combined, now + 1000))
        assertFalse(HealthCareMaintenancePolicy.needsReassessment(combined.copy(stage = HealthCareStage.REASSESS), now + 1000))
    }
}
