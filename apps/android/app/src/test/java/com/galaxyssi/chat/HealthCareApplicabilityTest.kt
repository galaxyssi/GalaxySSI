package com.galaxyssi.chat

import java.util.UUID
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HealthCareApplicabilityTest {
    private val now = 1_793_000_000_000L
    private val record = HealthCareRecordRef(UUID.randomUUID().toString(), 1)
    private val issue = HealthCareConcern(UUID.randomUUID().toString(), HealthMetric.GLUCOSE, 1, now, now, "input",
        HealthCareAssessment(record, now, "6.3", "mmol/L", "4-6", setOf(HealthCareSignal.REPORT_HIGH)))
    private val confirmed = issue.copy(context = HealthCareContext(record, HealthCareTruth.YES, HealthCareTruth.NO,
        HealthCareTruth.NO, HealthCareSpecimen.LAB_PLASMA, 8, HealthCareTruth.NO, now))
    private fun check(field: HealthCareApplicabilityField = HealthCareApplicabilityField.adult, expected: String = "YES",
        operator: HealthCareApplicabilityOperator = HealthCareApplicabilityOperator.EQUALS, source: Int = 0) =
        HealthCareApplicabilityCheck(field, operator, expected, source)
    private fun review(checks: List<HealthCareApplicabilityCheck> = listOf(check()), missing: List<String> = emptyList(),
        conflicts: List<HealthCareSourceConflict> = emptyList(), mode: HealthCareApplicabilityMode = HealthCareApplicabilityMode.INDIVIDUALIZED) =
        HealthCareApplicability(mode, checks, missing, conflicts)
    private fun plan(review: HealthCareApplicability? = review(), kind: HealthCareActionKind = HealthCareActionKind.RECHECK): HealthCarePlan {
        val grant = HealthCareDiscussionGrant(UUID.randomUUID().toString(), UUID.randomUUID().toString(), issue.id, 1,
            "settings", "privacy", "a".repeat(64), now, "fixture", "fixture", "high")
        val sources = (1..2).map { HealthCarePlanSource("Fixture $it", "https://example.test/$it", "fixture", "Synthetic only") }
        val action = HealthCareAction(UUID.randomUUID().toString(), kind, "Synthetic next step", "Fixture rationale", sources[0].url)
        return HealthCarePlan(grant, issue.inputVersion, now, "b".repeat(64), "Fixture uncertainty", sources, listOf(action),
            applicability = review?.let { mapOf(action.id to it) }.orEmpty())
    }
    @Test fun unknownIsNotNoAndModelCannotSupplyActualFacts() {
        val requirement = check(HealthCareApplicabilityField.pregnant, "NO")
        assertEquals(HealthCareCheckResult.UNKNOWN, HealthCareApplicabilityPolicy.result(requirement, issue))
        assertEquals(HealthCareCheckResult.MATCH, HealthCareApplicabilityPolicy.result(requirement, confirmed))
        assertEquals(HealthCareApplicabilityStatus.NEEDS_CONTEXT, HealthCareApplicabilityPolicy.status(review(listOf(requirement)), issue))
        assertThrows(IllegalArgumentException::class.java) { HealthCareApplicabilityCheck.from(requirement.json().put("actual", "NO")) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareApplicability.from(review().json().put("verified", true)) }
    }
    @Test fun contextFromAnotherRecordOrRevisionDoesNotCount() {
        for (ref in listOf(record.copy(revision = 2), HealthCareRecordRef(UUID.randomUUID().toString(), 1))) {
            val changed = confirmed.copy(context = confirmed.context!!.copy(record = ref))
            assertEquals(HealthCareCheckResult.UNKNOWN, HealthCareApplicabilityPolicy.result(check(), changed))
        }
    }
    @Test fun matchingDeclaredChecksIsNotClinicalVerification() {
        val requirements = listOf(check(), check(HealthCareApplicabilityField.pregnant, "NO"),
            check(HealthCareApplicabilityField.specimen, "LAB_PLASMA"),
            check(HealthCareApplicabilityField.fasting, "8", HealthCareApplicabilityOperator.AT_LEAST))
        val plan = plan(review(requirements))
        assertEquals(HealthCareApplicabilityStatus.DECLARED_CHECKS_MATCH, HealthCareApplicabilityPolicy.status(review(requirements), confirmed))
        val next = HealthCarePlanPolicy.accept(plan, confirmed, setOf(plan.actions.single().id), now)
        assertEquals(HealthCareStage.WAITING_RESULTS, next.stage); assertNull(next.target)
        assertFalse(plan.json().toString().contains("clinically_verified"))
    }
    @Test fun missingAndMismatchingFactsCannotBeAcceptedEvenOutsideUi() {
        val plan = plan()
        for (value in listOf(issue, confirmed.copy(context = confirmed.context!!.copy(adult = HealthCareTruth.NO)))) {
            assertFalse(HealthCareApplicabilityPolicy.canAccept(plan, value, plan.actions.single()))
            assertThrows(IllegalArgumentException::class.java) { HealthCarePlanPolicy.accept(plan, value, setOf(plan.actions.single().id), now) }
        }
    }
    @Test fun declaredMissingFactorsStillBlockMatchedChecks() {
        val value = review(missing = listOf("Medication context requires professional review"))
        assertEquals(HealthCareApplicabilityStatus.NEEDS_CONTEXT, HealthCareApplicabilityPolicy.status(value, confirmed))
        val plan = plan(value)
        assertFalse(HealthCareApplicabilityPolicy.canAccept(plan, confirmed, plan.actions.first()))
    }
    @Test fun conflictingSourcesArePreservedAndNeverAveragedOrImplicitlyResolved() {
        val conflict = HealthCareSourceConflict(listOf(0, 1), "Synthetic intervals disagree", "Discuss populations and versions")
        val value = review(conflicts = listOf(conflict))
        val plan = plan(value)
        assertEquals(plan, HealthCarePlan.from(JSONObject(plan.json().toString())))
        assertEquals(HealthCareApplicabilityStatus.CONFLICT, HealthCareApplicabilityPolicy.status(value, confirmed))
        assertFalse(HealthCareApplicabilityPolicy.canAccept(plan, confirmed, plan.actions.single()))
        assertThrows(IllegalArgumentException::class.java) { HealthCarePlanPolicy.accept(plan, confirmed, setOf(plan.actions.single().id), now) }
    }
    @Test fun clarificationAndClinicianDiscussionRemainPossibleWithoutClaimingEligibility() {
        val value = review(missing = listOf("Context unknown"), conflicts = listOf(HealthCareSourceConflict(listOf(0, 1), "Conflict", "Ask clinician")),
            mode = HealthCareApplicabilityMode.DISCUSSION_ONLY)
        for (kind in listOf(HealthCareActionKind.CONTEXT, HealthCareActionKind.CLINICIAN_DISCUSSION)) {
            val plan = plan(value, kind)
            assertTrue(HealthCareApplicabilityPolicy.canAccept(plan, issue, plan.actions.single()))
            assertEquals(HealthCareStage.REVIEW_PLAN, HealthCarePlanPolicy.accept(plan, issue, setOf(plan.actions.single().id), now).stage)
        }
        for (kind in listOf(HealthCareActionKind.LIFESTYLE, HealthCareActionKind.RECHECK))
            assertThrows(IllegalArgumentException::class.java) { plan(value, kind) }
    }
    @Test fun legacyDraftStaysReadableButCannotAdoptUnreviewedClinicalActions() {
        val plan = plan(null)
        val legacy = plan.json().apply { remove("applicability") }
        assertEquals(plan, HealthCarePlan.from(legacy))
        assertFalse(HealthCareApplicabilityPolicy.canAccept(plan, confirmed, plan.actions.single()))
        val discussion = plan(null, HealthCareActionKind.CLINICIAN_DISCUSSION)
        assertTrue(HealthCareApplicabilityPolicy.canAccept(discussion, issue, discussion.actions.single()))
    }
    @Test fun sourceIndicesMustReferToActualIncludedPassages() {
        assertThrows(IllegalArgumentException::class.java) { plan(review(listOf(check(source = 2)))) }
        assertThrows(IllegalArgumentException::class.java) { plan(review(conflicts = listOf(HealthCareSourceConflict(listOf(0, 2), "Conflict", "Review")))) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareSourceConflict(listOf(0, 0), "Conflict", "Review") }
        assertThrows(IllegalArgumentException::class.java) { HealthCareApplicabilityCheck.from(check().json().put("source_index", 0.5)) }
        assertThrows(IllegalArgumentException::class.java) { HealthCareSourceConflict.from(JSONObject("""{"source_indices":[0,0.5],"detail":"Conflict","next_step":"Review"}""")) }
    }
    @Test fun incompleteUnsupportedAndOutOfRangeConditionsAreRejected() {
        assertThrows(IllegalArgumentException::class.java) { review(emptyList()) }
        assertThrows(IllegalArgumentException::class.java) { check(expected = "UNKNOWN") }
        assertThrows(IllegalArgumentException::class.java) { check(operator = HealthCareApplicabilityOperator.AT_LEAST) }
        assertThrows(IllegalArgumentException::class.java) { check(HealthCareApplicabilityField.fasting, "8.5") }
        assertThrows(IllegalArgumentException::class.java) { check(HealthCareApplicabilityField.fasting, "73") }
        assertThrows(IllegalArgumentException::class.java) { check(HealthCareApplicabilityField.specimen, "UNKNOWN") }
        assertThrows(IllegalArgumentException::class.java) { check(HealthCareApplicabilityField.collection_condition, "unspecified") }
        assertThrows(IllegalArgumentException::class.java) { review(List(13) { check() }) }
    }
    @Test fun unitsAndFastingComparatorsUseExactStoredFacts() {
        assertEquals(HealthCareCheckResult.MISMATCH, HealthCareApplicabilityPolicy.result(check(HealthCareApplicabilityField.unit, "mg/dL"), confirmed))
        assertEquals(HealthCareCheckResult.MATCH, HealthCareApplicabilityPolicy.result(check(HealthCareApplicabilityField.fasting, "8", HealthCareApplicabilityOperator.AT_MOST), confirmed))
        assertEquals(HealthCareCheckResult.MISMATCH, HealthCareApplicabilityPolicy.result(check(HealthCareApplicabilityField.fasting, "9", HealthCareApplicabilityOperator.AT_LEAST), confirmed))
        assertEquals(HealthCareCheckResult.UNKNOWN, HealthCareApplicabilityPolicy.result(check(HealthCareApplicabilityField.collection_condition, "fasting"), confirmed))
    }
}
