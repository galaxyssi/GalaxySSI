package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareTargetTest {
    private val now = 1_793_000_000_000L
    private val ref = HealthCareRecordRef(UUID.randomUUID().toString(), 1)
    private val sample = HealthCareSample(ref, HealthMetric.GLUCOSE, now, mapOf("glucose" to "5.8"), "mmol/L", "4-6", "fasting", "", "manual", "", "")
    private val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "input1",
        HealthCareAssessment(ref, now, "5.8", "mmol/L", "4-6", emptySet(), sample = sample))
    private val review = HealthCareApplicability(HealthCareApplicabilityMode.INDIVIDUALIZED,
        listOf(HealthCareApplicabilityCheck(HealthCareApplicabilityField.metric, HealthCareApplicabilityOperator.EQUALS, "GLUCOSE", 0)), emptyList(), emptyList())
    private val draft = HealthCareTargetProposal("glucose", "4.0", "6.0", "mmol/L", true, false, "Synthetic test only; not a medical target", 0, review)
    private val grant = HealthCareDiscussionGrant(UUID.randomUUID().toString(), UUID.randomUUID().toString(), issue.id, 1,
        "settings", "privacy", "a".repeat(64), now, "fixture", "fixture", "high")
    private val source = HealthCarePlanSource("Synthetic source", "https://example.test/target", "fixture", "Fixture only",
        UUID.randomUUID().toString(), "Synthetic target bounds for isolated testing only")
    private fun plan(target: HealthCareTargetProposal = draft) = HealthCarePlan(grant, issue.inputVersion, now, "b".repeat(64), "Fixture only",
        listOf(source), emptyList(), target = target)
    private fun accepted(p: HealthCarePlan = plan()) = HealthCarePlanPolicy.accept(p, issue, emptySet(), now + 1, true)
    private fun input() = mapOf("uncertainty" to "Fixture only", "sources" to listOf(mapOf("title" to source.title, "url" to source.url,
        "version" to source.version, "applicability" to source.applicability, "evidence_id" to source.evidenceId, "supporting_quote" to source.quote)),
        "actions" to emptyList<String>(), "target_proposal" to mapOf("field" to draft.field, "low" to draft.low, "high" to draft.high,
            "unit" to draft.unit, "low_inclusive" to true, "high_inclusive" to false, "rationale" to draft.rationale, "source_index" to 0,
            "applicability" to mapOf("mode" to "INDIVIDUALIZED", "checks" to listOf(mapOf("field" to "metric", "operator" to "EQUALS",
                "expected" to "GLUCOSE", "source_index" to 0)), "missing_information" to emptyList<String>(), "conflicts" to emptyList<String>())))

    @Test fun targetOnlyDraftRemainsUnconfirmedAndRoundTrips() {
        val plan = HealthCarePlanPolicy.parse(input(), grant, issue, now)
        assertEquals(draft, plan.target); assertFalse(plan.targetSelected); assertTrue(plan.actions.isEmpty())
        assertEquals(plan, HealthCarePlan.from(plan.json())); assertNull(issue.target)
    }
    @Test fun targetIsNeverAutomaticallySelected() {
        assertThrows(IllegalArgumentException::class.java) { HealthCarePlanPolicy.accept(plan(), issue, emptySet(), now) }
        val next = accepted()
        assertEquals("user", next.target!!.confirmedBy); assertEquals(grant.turnId, next.target!!.planId)
        assertEquals(1, next.targetRevision); assertEquals(HealthCareStage.REVIEW_PLAN, next.stage)
        assertNull(next.nextDue); assertEquals(issue.assessment, next.assessment)
        assertEquals(next, HealthCareConcern.from(next.json()))
    }
    @Test fun unknownFieldsCannotAssertClinicianApprovalOrConfirmation() {
        listOf("confirmed_by", "confirmed_at", "basis", "plan_id", "clinician_approved").forEach { field ->
            assertThrows(IllegalArgumentException::class.java) { HealthCareTargetProposal.from(draft.json().put(field, "forged")) }
        }
    }
    @Test fun invalidNumbersAndEmptyOrReversedRangesAreRejected() {
        listOf("1e9999", "NaN", "-1", "<6", "4-6", "positive", "1,5", " 5 ", "1".repeat(21)).forEach {
            assertThrows(IllegalArgumentException::class.java) { draft.copy(low = it) }
        }
        assertThrows(IllegalArgumentException::class.java) { draft.copy(low = null, high = null) }
        assertThrows(IllegalArgumentException::class.java) { draft.copy(low = "7") }
        assertThrows(IllegalArgumentException::class.java) { draft.copy(low = "6") }
        assertNotNull(draft.copy(low = "6", highInclusive = true))
    }
    @Test fun stringBooleanAndFractionalIndicesAreNotAccepted() {
        assertThrows(IllegalArgumentException::class.java) { HealthCareTargetProposal.from(draft.json().put("low_inclusive", "true")) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareTargetProposal.from(draft.json().put("source_index", 0.5)) }
        assertThrows(IllegalArgumentException::class.java) { plan(draft.copy(sourceIndex = 1)) }
    }
    @Test fun targetsRequireMatchedApplicability() {
        val unknown = review.copy(checks = listOf(HealthCareApplicabilityCheck(HealthCareApplicabilityField.pregnant,
            HealthCareApplicabilityOperator.EQUALS, "NO", 0)))
        assertFalse(HealthCareTargetPolicy.canAccept(draft.copy(applicability = unknown), issue))
        assertThrows(IllegalArgumentException::class.java) { accepted(plan(draft.copy(applicability = unknown))) }
        assertFalse(HealthCareTargetPolicy.canAccept(draft.copy(applicability = review.copy(missingInformation = listOf("Clinical context"))), issue))
        assertThrows(IllegalArgumentException::class.java) { draft.copy(applicability = review.copy(mode = HealthCareApplicabilityMode.DISCUSSION_ONLY)) }
    }
    @Test fun fieldAndUnitCannotBeSilentlyConverted() {
        assertFalse(HealthCareTargetPolicy.canAccept(draft.copy(unit = "mg/dL"), issue))
        assertFalse(HealthCareTargetPolicy.canAccept(draft.copy(field = "pulse"), issue))
    }
    @Test fun inclusiveAndExclusiveBoundsCompareOnlyExactValues() {
        assertEquals(HealthCareTargetComparison.WITHIN, HealthCareTargetPolicy.comparison(accepted()))
        assertEquals(HealthCareTargetComparison.ABOVE, HealthCareTargetPolicy.comparison(accepted(plan(draft.copy(high = "5.80")))))
        assertEquals(HealthCareTargetComparison.WITHIN, HealthCareTargetPolicy.comparison(accepted(plan(draft.copy(high = "5.80", highInclusive = true)))))
        assertEquals(HealthCareTargetComparison.BELOW, HealthCareTargetPolicy.comparison(accepted(plan(draft.copy(low = "5.8", lowInclusive = false)))))
        val nonExact = accepted().copy(assessment = issue.assessment.copy(sample = sample.copy(values = mapOf("glucose" to "<5.8"))))
        assertEquals(HealthCareTargetComparison.NOT_COMPARABLE, HealthCareTargetPolicy.comparison(nonExact))
    }
    @Test fun oneSidedBoundsRemainOneSided() {
        assertEquals(HealthCareTargetComparison.WITHIN, HealthCareTargetPolicy.comparison(accepted(plan(draft.copy(low = null)))))
        assertEquals(HealthCareTargetComparison.WITHIN, HealthCareTargetPolicy.comparison(accepted(plan(draft.copy(high = null)))))
    }
    @Test fun newReportOrContextRequiresReviewButPreservesTarget() {
        val saved = accepted()
        assertEquals(HealthCareTargetComparison.REVIEW_REQUIRED, HealthCareTargetPolicy.comparison(saved.copy(inputVersion = "new-input")))
        assertEquals(HealthCareTargetComparison.REVIEW_REQUIRED, HealthCareTargetPolicy.comparison(saved.copy(context = HealthCareContext(ref, confirmedAt = now))))
        assertEquals(saved.target, saved.copy(inputVersion = "new-input").target)
    }
    @Test fun legacyTargetRemainsReadableButIsNotConsideredCurrent() {
        val json = accepted().target!!.json().apply { remove("plan_id"); remove("basis"); remove("low_inclusive"); remove("high_inclusive") }
        val legacy = HealthCareTarget.from(json)
        assertEquals(HealthCareTargetComparison.REVIEW_REQUIRED, HealthCareTargetPolicy.comparison(issue.copy(target = legacy)))
        assertTrue(legacy.highInclusive)
    }
    @Test fun targetChangesAndRevocationDoNotResurrectOldActionBasis() {
        val original = HealthCareFollowUpPolicy.basis(issue)
        val saved = accepted(); assertNotEquals(original, HealthCareFollowUpPolicy.basis(saved))
        val revoked = HealthCareTargetPolicy.revoke(saved)
        assertNull(revoked.target); assertEquals(2, revoked.targetRevision); assertEquals(HealthCareStage.REASSESS, revoked.stage)
        assertNotEquals(original, HealthCareFollowUpPolicy.basis(revoked))
        assertNotEquals(HealthCareFollowUpPolicy.basis(saved), HealthCareFollowUpPolicy.basis(revoked))
    }
    @Test fun selectedActionsUseNewTargetBasisAtomically() {
        val action = HealthCareAction(UUID.randomUUID().toString(), HealthCareActionKind.CONTEXT, "Synthetic action", "Fixture", "Fixture")
        val p = plan().copy(actions = listOf(action))
        val next = HealthCarePlanPolicy.accept(p, issue, setOf(action.id), now, true)
        assertEquals(HealthCareFollowUpPolicy.basis(next), next.actions.single().basis)
        val onlyAction = HealthCarePlanPolicy.accept(p, issue, setOf(action.id), now)
        assertNull(onlyAction.target); assertEquals(0, onlyAction.targetRevision)
    }
    @Test fun acceptedPlanRecordsTargetSelectionSeparately() {
        val p = plan().copy(state = HealthCarePlanState.ACCEPTED, targetSelected = true, resolvedAt = now)
        assertEquals(p, HealthCarePlan.from(p.json()))
        assertThrows(IllegalArgumentException::class.java) { plan().copy(targetSelected = true) }
    }
    @Test fun snapshotDistinguishesWithinTargetFromStability() {
        val next = accepted()
        assertEquals("WITHIN", JSONObject(HealthCareDiscussionPolicy.snapshot(next)).getString("target_comparison"))
        assertEquals(HealthCareStage.REVIEW_PLAN, next.stage)
        assertTrue(HealthCareDiscussionPolicy.prompt("Review", "{}").contains("does not establish stability"))
    }
    @Test fun nativeSchemaAcceptsTargetProposalWithoutGrantingConfirmation() {
        val registry = AgentNativeToolRegistry().register(HealthCarePlanTool.definition { _, request ->
            HealthCarePlanPolicy.parse(request, grant, issue, now)
        })
        val result = registry.invoke(HealthCarePlanTool.ID, input(), AgentNativeToolInvocationContext(conversationId = grant.conversationId, turnId = grant.turnId))
        assertEquals(AgentNativeToolResultStatus.SUCCEEDED, result.status)
    }
}
