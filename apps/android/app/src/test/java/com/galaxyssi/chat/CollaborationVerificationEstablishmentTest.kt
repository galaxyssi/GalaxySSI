package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationVerificationEstablishmentTest {
    private fun sum() = JSONObject().put("id", "sum")
        .put("requirement", "Compute the exact integer sum: 2 + 3.")
        .put("verification", "computational").put("evidence_kind", "observed")
        .put("status", "open").put("evidence", JSONArray())
        .put("validator", JSONObject().put("id", "exact_integer_sum.v1").put("operands", JSONArray().put("2").put("3")))

    private fun withoutRoute(value: JSONObject) = JSONObject(value.toString()).apply { remove("validator") }
    private fun accepts(value: JSONObject) = CollaborationQualifiedValidation.canEstablish(withoutRoute(value), value)

    @Test fun scopedRouteCanBeEstablishedButIsNotPreservedUntilItIsSaved() {
        val value = sum()
        val before = withoutRoute(value)
        assertTrue(CollaborationQualifiedValidation.canEstablish(before, value))
        assertFalse(CollaborationQualifiedValidation.preserved(before, value))
        assertFalse(CollaborationQualifiedValidation.canEstablish(value, value))
        assertTrue(CollaborationQualifiedValidation.preserved(value, JSONObject(value.toString())))
        assertFalse(before.has("validator"))
    }

    @Test fun typeRequirementAndIdentityCannotBeReinterpreted() {
        val before = withoutRoute(sum())
        listOf(sum().put("id", "other"), sum().put("requirement", "Prove a theorem"),
            sum().put("verification", "physical"), sum().put("verification", "documentary")).forEach {
            assertFalse(CollaborationQualifiedValidation.canEstablish(before, it))
        }
        assertFalse(accepts(sum().put("requirement", "Design a protein and validate its function")))
        assertFalse(accepts(sum().put("verification", "physical")))
        assertFalse(accepts(sum().apply { getJSONObject("validator").put("operands", JSONArray().put("1").put("4")) }))
    }

    @Test fun noRetroactiveAcceptanceFromPreviouslyClaimedEvidenceOrDelivery() {
        val mutations: List<(JSONObject) -> Unit> = listOf(
            { it.put("status", "met") }, { it.put("evidence", JSONArray().put("already done")) },
            { it.put("delivery", JSONObject()) }, { it.put("review", JSONObject.NULL) },
            { it.put("evidence_kind", "simulation") }, { it.put("evidence_kind", "proposal") },
            { it.remove("evidence") }
        )
        mutations.forEach { mutate ->
            val before = withoutRoute(sum()).also(mutate)
            assertFalse(CollaborationQualifiedValidation.canEstablish(before, sum()))
            assertFalse(CollaborationQualifiedValidation.canEstablish(withoutRoute(sum()), sum().also(mutate)))
        }
    }

    @Test fun unknownMalformedAndAlreadyBoundMethodsCannotBePromoted() {
        listOf(JSONObject.NULL, "exact_integer_sum.v1", JSONObject().put("id", "model_signed_pass"),
            JSONObject().put("id", "exact_integer_sum.v1").put("operands", JSONArray().put("2"))).forEach {
            assertFalse(CollaborationQualifiedValidation.canEstablish(withoutRoute(sum()), sum().put("validator", it)))
        }
        assertFalse(CollaborationQualifiedValidation.canEstablish(sum(), withoutRoute(sum())))
        assertFalse(CollaborationQualifiedValidation.canEstablish(withoutRoute(sum()).put("validator", JSONObject.NULL), sum()))
        assertFalse(CollaborationQualifiedValidation.canEstablish(withoutRoute(sum()), null))
    }

    @Test fun originalSourceObligationsCannotBeDropped() {
        val source = JSONArray().put(JSONObject().put("origin", "desktop_codex_tool").put("tool", "codex.commandExecution"))
        val before = withoutRoute(sum()).put("required_observations", source)
        assertFalse(CollaborationQualifiedValidation.canEstablish(before, sum()))
        assertTrue(CollaborationQualifiedValidation.canEstablish(before, sum().put("required_observations", source)))
    }

    @Test fun numericRouteStillMeansOnlyTheDeclaredFiniteCases() {
        val value = sum().put("requirement", CollaborationNumericModelValidator.REQUIREMENT)
            .put("validator", JSONObject().put("id", CollaborationNumericModelValidator.id).put("variables", JSONArray().put("x"))
                .put("cases", JSONArray().put(JSONObject().put("id", "case").put("input", JSONObject().put("x", "2"))
                    .put("expected", "4").put("absolute_tolerance", "0"))))
        assertTrue(accepts(value))
        assertFalse(accepts(JSONObject(value.toString()).put("requirement", "Prove this model is true for all inputs")))
        value.getJSONObject("validator").getJSONArray("cases").getJSONObject(0).put("absolute_tolerance", "-1")
        assertFalse(accepts(value))
    }

    @Test fun executableRouteStillRequiresRegisteredTargetAndRegressionCases() {
        fun case(id: String, purpose: String) = JSONObject().put("id", id).put("purpose", purpose).put("reason", "Fixture scope")
            .put("input", JSONObject()).put("expected", true)
        val value = sum().put("requirement", CollaborationExecutableAcceptance.REQUIREMENT)
            .put("validator", JSONObject().put("id", CollaborationExecutableAcceptance.id).put("environment", "fixture runtime")
                .put("purpose", "Check a saved tool").put("oracle_basis", "Supplied cases, not certified truth")
                .put("coverage_gaps", "Unseen cases").put("cases", JSONArray().put(case("t", "target")).put(case("r", "regression"))))
        assertTrue(accepts(value))
        assertFalse(accepts(JSONObject(value.toString()).put("requirement", "Prove general correctness")))
        value.getJSONObject("validator").getJSONArray("cases").remove(1)
        assertFalse(accepts(value))
    }

    @Test fun newlyEstablishedRouteDoesNotQualifyAnIncorrectComputation() {
        val value = sum()
        assertTrue(accepts(value))
        val body = JSONObject().put("computation", JSONObject().put("validator_id", "exact_integer_sum.v1").put("result", "6"))
        assertThrows(IllegalArgumentException::class.java) { CollaborationQualifiedValidation.validate(value, body) }
        body.getJSONObject("computation").put("result", "5")
        CollaborationQualifiedValidation.validate(value, body)
    }

    @Test fun oldSemanticCoverageCannotBeReplayedAfterEstablishingTheRoute() {
        val f = CollaborationGoalAcceptanceTest.Fixture(requirement = sum().getString("requirement"), verification = "computational",
            computation = JSONObject().put("validator_id", "exact_integer_sum.v1").put("result", "5"))
        val registered = JSONObject(f.criterion.toString()).put("validator", sum().getJSONObject("validator"))
        assertTrue(CollaborationQualifiedValidation.canEstablish(f.criterion, registered))
        val report = f.assessment()
        report.getJSONArray("criteria").getJSONObject(0).put("validator", registered.getJSONObject("validator"))
        val receipt = f.evaluate(report.toString(), previous = JSONArray().put(registered).toString())
        assertFalse(receipt.accepted)
        assertNotEquals(CollaborationSemanticGoalCoverage.criteriaHash(JSONArray(f.prior)),
            CollaborationSemanticGoalCoverage.criteriaHash(JSONArray().put(registered)))
    }
}
