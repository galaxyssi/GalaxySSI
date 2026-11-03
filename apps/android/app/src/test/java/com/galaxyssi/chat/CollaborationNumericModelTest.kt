package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationNumericModelTest {
    private val validator = CollaborationNumericModelValidator
    private fun constant(value: Any) = JSONObject().put("constant", value)
    private fun variable(value: String = "x") = JSONObject().put("variable", value)
    private fun operation(value: String, vararg args: JSONObject) = JSONObject().put("op", value).put("args", JSONArray(args.toList()))
    private fun row(id: String, x: Any, expected: Any, tolerance: Any = 0) = JSONObject().put("id", id)
        .put("input", JSONObject().put("x", x)).put("expected", expected).put("absolute_tolerance", tolerance)
    private fun spec(vararg rows: JSONObject) = JSONObject().put("id", validator.id).put("variables", JSONArray().put("x"))
        .put("cases", JSONArray(rows.toList().ifEmpty { listOf(row("positive", 2, 4), row("negative", -3, 9)) }))
    private fun computation(model: JSONObject = operation("mul", variable(), variable())) = JSONObject().put("validator_id", validator.id).put("model", model)
    private fun criterion(spec: JSONObject = spec()) = JSONObject().put("id", "numeric").put("requirement", CollaborationNumericModelValidator.REQUIREMENT)
        .put("verification", "computational").put("evidence_kind", "observed").put("status", "open").put("evidence", JSONArray()).put("validator", spec)
    private fun reject(block: () -> Any?) = assertNotNull(runCatching(block).exceptionOrNull())

    @Test fun replaysTheSavedModelWithoutAcceptingAnAuthoredPassOrScore() {
        val result = validator.evaluate(spec(), computation())
        assertTrue(result.toString(), result.getBoolean("passed"))
        assertEquals(2, result.getInt("case_count"))
        assertEquals(0, result.getInt("failed_cases"))
        assertTrue(result.getString("meaning").contains("not_independent_reference_truth_or_generalization"))
        reject { validator.evaluate(spec(), computation().put("passed", true)) }
        reject { validator.evaluate(spec(), computation().put("score", 1)) }
    }

    @Test fun counterexampleChangesExecutableCandidateWhileCasesStayFixed() {
        val registered = spec()
        val before = registered.toString()
        val bad = computation(operation("mul", constant(2), variable()))
        val failed = validator.evaluate(registered, bad)
        assertFalse(failed.getBoolean("passed"))
        assertEquals("negative", failed.getJSONObject("worst_case").getString("id"))
        assertEquals("-6.0", failed.getJSONObject("worst_case").getString("actual"))
        val error = runCatching { validator.validate(criterion(registered), JSONObject().put("computation", bad)) }.exceptionOrNull()!!
        assertTrue(error.message.orEmpty().contains("negative"))
        val corrected = computation()
        assertTrue(validator.evaluate(registered, corrected).getBoolean("passed"))
        assertNotEquals(failed.getString("model_sha256"), validator.evaluate(registered, corrected).getString("model_sha256"))
        assertEquals(before, registered.toString())
    }

    @Test fun toleranceUsesDecimalComparisonAndCannotHideLargeIntegerRounding() {
        assertTrue(validator.evaluate(spec(row("edge", 0, "1.001", "0.001")), computation(constant(1))).getBoolean("passed"))
        assertFalse(validator.evaluate(spec(row("outside", 0, "1.0011", "0.001")), computation(constant(1))).getBoolean("passed"))
        val large = "9007199254740993"
        assertFalse(validator.evaluate(spec(row("rounding", 0, large)), computation(constant(large))).getBoolean("passed"))
    }

    @Test fun nonFiniteIntermediateCannotBeHiddenByLaterOperations() {
        val overflow = operation("min", constant(1), operation("exp", constant(1000)))
        val report = validator.evaluate(spec(row("overflow", 0, 1)), computation(overflow))
        assertFalse(report.getBoolean("passed"))
        assertTrue(report.getJSONObject("worst_case").getString("error").contains("finite"))
        for (model in listOf(operation("div", constant(1), constant(0)), operation("sqrt", constant(-1)),
            operation("log", constant(0)), operation("pow", constant(-1), constant(0.5))))
            assertFalse(validator.evaluate(spec(), computation(model)).getBoolean("passed"))
    }

    @Test fun everyRegisteredCaseIsEvaluatedAndNegativeOutcomesAreCounted() {
        val registered = spec(row("ok", 1, 1), row("zero", 0, 0), row("wrong", 2, 4))
        val model = computation(operation("div", constant(1), variable()))
        val result = validator.evaluate(registered, model)
        assertEquals(3, result.getInt("case_count"))
        assertEquals(2, result.getInt("failed_cases"))
        assertEquals("zero", result.getJSONObject("worst_case").getString("id"))
    }

    @Test fun allSupportedOperatorsHaveLocalDeterministicSemantics() {
        val examples = listOf(
            operation("neg", constant(2)) to -2, operation("abs", constant(-2)) to 2,
            operation("exp", constant(0)) to 1, operation("log", constant(1)) to 0,
            operation("expm1", constant(0)) to 0, operation("log1p", constant(0)) to 0,
            operation("sqrt", constant(4)) to 2, operation("sin", constant(0)) to 0,
            operation("cos", constant(0)) to 1, operation("add", constant(2), constant(3)) to 5,
            operation("sub", constant(2), constant(3)) to -1, operation("mul", constant(2), constant(3)) to 6,
            operation("div", constant(6), constant(3)) to 2, operation("pow", constant(2), constant(3)) to 8,
            operation("min", constant(2), constant(3)) to 2, operation("max", constant(2), constant(3)) to 3)
        examples.forEach { (model, expected) ->
            assertTrue(model.toString(), validator.evaluate(spec(row("case", 0, expected)), computation(model)).getBoolean("passed"))
        }
    }

    @Test fun smallExponentialAndLogarithmicChangesDoNotLoseAllPrecision() {
        val small = "1e-20"
        for (op in listOf("expm1", "log1p")) {
            val result = validator.evaluate(spec(row(op, 0, small, "1e-35")), computation(operation(op, constant(small))))
            assertTrue(result.toString(), result.getBoolean("passed"))
        }
        assertFalse(validator.evaluate(spec(), computation(operation("log1p", constant(-1)))).getBoolean("passed"))
    }

    @Test fun independentVariablesAreNotMixedOrFilledWithDefaults() {
        val registered = spec(row("two", 2, 7)).put("variables", JSONArray().put("x").put("y"))
        registered.getJSONArray("cases").getJSONObject(0).getJSONObject("input").put("y", 3)
        assertTrue(validator.evaluate(registered, computation(operation("add", variable(), operation("mul", constant(5.0 / 3), variable("y"))))).getBoolean("passed"))
        registered.getJSONArray("cases").getJSONObject(0).getJSONObject("input").remove("y")
        reject { validator.binding(registered) }
        reject { validator.evaluate(spec(), computation(variable("y"))) }
    }

    @Test fun malformedSpecsAndUndeclaredFieldsFailBeforeReplay() {
        val mutations: List<(JSONObject) -> Unit> = listOf(
            { it.put("id", "other") }, { it.put("source", "execute me") }, { it.put("variables", JSONArray()) },
            { it.put("variables", JSONArray().put("x").put("x")) }, { it.put("variables", JSONArray().put("../x")) },
            { it.put("cases", JSONArray()) }, { it.getJSONArray("cases").put(it.getJSONArray("cases").getJSONObject(0)) },
            { it.getJSONArray("cases").getJSONObject(0).put("absolute_tolerance", -1) },
            { it.getJSONArray("cases").getJSONObject(0).put("expected", "NaN") },
            { it.getJSONArray("cases").getJSONObject(0).put("expected", "1e9999") },
            { it.getJSONArray("cases").getJSONObject(0).put("expected", true) },
            { it.getJSONArray("cases").getJSONObject(0).getJSONObject("input").put("undeclared", 1) })
        mutations.forEach { change -> reject { validator.binding(spec().also(change)) } }
    }

    @Test fun expressionCannotExecuteCodeReadFilesOrIgnoreMalformedBranches() {
        for (model in listOf(JSONObject().put("source", "print('pass')"), operation("eval", constant(1)),
            operation("add", constant(1)), operation("abs", constant(1), constant(2)),
            constant(1).put("variable", "x"), operation("min", constant(0), variable("missing")),
            JSONObject().put("op", "add").put("args", JSONArray().put(1).put(2))))
            reject { validator.evaluate(spec(), computation(model)) }
    }

    @Test fun finiteLocalEnvelopesRejectUnboundedOrDeepModels() {
        var deep = constant(1)
        repeat(49) { deep = operation("neg", deep) }
        reject { validator.evaluate(spec(), computation(deep)) }
        fun tree(depth: Int): JSONObject = if (depth == 0) constant(0) else operation("add", tree(depth - 1), tree(depth - 1))
        reject { validator.evaluate(spec(), computation(tree(11))) }
        val large = JSONObject().put("id", validator.id).put("variables", JSONArray().put("x"))
            .put("cases", JSONArray((0..4096).map { row("c$it", it, 0) }))
        reject { validator.binding(large) }
        large.getJSONArray("cases").remove(4096)
        reject { validator.evaluate(large, computation(tree(9))) }
    }

    @Test fun bindingSurvivesKeyOrderButNotAChangedInputExpectedValueOrTolerance() {
        val before = criterion()
        val reordered = JSONObject(before.toString())
        val original = reordered.getJSONObject("validator")
        reordered.put("validator", JSONObject().put("cases", original.get("cases")).put("variables", original.get("variables")).put("id", validator.id))
        assertTrue(CollaborationQualifiedValidation.preserved(before, reordered))
        for (field in listOf("expected", "absolute_tolerance", "input")) {
            val changed = JSONObject(before.toString())
            val row = changed.getJSONObject("validator").getJSONArray("cases").getJSONObject(0)
            if (field == "input") row.getJSONObject(field).put("x", 5) else row.put(field, 99)
            assertFalse(CollaborationQualifiedValidation.preserved(before, changed))
            assertNotEquals(CollaborationSemanticGoalCoverage.criteriaHash(JSONArray().put(before)),
                CollaborationSemanticGoalCoverage.criteriaHash(JSONArray().put(changed)))
        }
    }

    @Test fun onlyTheLiteralComputationalScopeCanPass() {
        val body = JSONObject().put("content", "Saved expression").put("computation", computation())
        CollaborationQualifiedValidation.validate(criterion(), body)
        for (change in listOf<(JSONObject) -> Unit>(
            { it.put("requirement", "Prove this calibration works everywhere") },
            { it.put("verification", "physical") }, { it.put("verification", "documentary") },
            { it.put("evidence_kind", "simulation") }, { it.put("evidence_kind", "proposal") }))
            reject { CollaborationQualifiedValidation.validate(criterion().also(change), body) }
    }

    @Test fun numericFingerprintsSurviveJsonPersistenceWithoutHidingValueChanges() {
        val original = spec(row("roundtrip", 2.0, 4.0, 0.0))
        val saved = JSONObject(original.toString())
        assertEquals(validator.binding(original), validator.binding(saved))
        val first = validator.evaluate(original, computation(constant(4.0)))
        val second = validator.evaluate(saved, JSONObject(computation(constant(4.0)).toString()))
        assertEquals(first.getString("spec_sha256"), second.getString("spec_sha256"))
        assertEquals(first.getString("model_sha256"), second.getString("model_sha256"))
        assertNotEquals(first.getString("model_sha256"), validator.evaluate(saved, computation(constant(4.01))).getString("model_sha256"))
        saved.getJSONArray("cases").getJSONObject(0).put("expected", 4.01)
        assertNotEquals(validator.binding(original), validator.binding(saved))
    }

    @Test fun fullAcceptanceUsesExactSavedModelIndependentReviewAndPinnedCases() {
        val fixture = CollaborationGoalAcceptanceTest.Fixture(requirement = CollaborationNumericModelValidator.REQUIREMENT,
            verification = "computational", validator = spec(), computation = computation(), reviewKind = CollaborationReviewContract.KIND)
        val first = fixture.evaluate()
        assertTrue(first.feedback, first.accepted)
        val reopened = CollaborationGoalAcceptance(CollaborationResearchWorkspace(fixture.rows, { fixture.authorized }, fixture.ledger::references), fixture.ledger)
        assertTrue(reopened.evaluate(fixture.access, fixture.assessment().toString(), fixture.prior, fixture.goal).accepted)
        val easier = fixture.assessment()
        easier.getJSONArray("criteria").getJSONObject(0).getJSONObject("validator").getJSONArray("cases").getJSONObject(0).put("absolute_tolerance", 1000)
        assertFalse(fixture.evaluate(easier.toString()).accepted)
        assertFalse(CollaborationGoalAcceptanceTest.Fixture(requirement = CollaborationNumericModelValidator.REQUIREMENT,
            verification = "computational", validator = spec(), computation = computation(constant(4)),
            reviewKind = CollaborationReviewContract.KIND).evaluate().accepted)
        assertFalse(CollaborationGoalAcceptanceTest.Fixture(requirement = CollaborationNumericModelValidator.REQUIREMENT,
            verification = "computational", validator = spec(), computation = computation(), reviewer = "author",
            reviewKind = CollaborationReviewContract.KIND).evaluate().accepted)
    }

    @Test fun staleSavedCandidateCannotReuseAPassingReview() {
        val f = CollaborationGoalAcceptanceTest.Fixture(requirement = CollaborationNumericModelValidator.REQUIREMENT,
            verification = "computational", validator = spec(), computation = computation(), reviewKind = CollaborationReviewContract.KIND)
        assertTrue(f.evaluate().accepted)
        f.publish(f.access.copy(round = 3, nodeId = "revision", personId = "author"), f.item("next", "artifact",
            JSONObject().put("content", "Changed expression").put("computation", computation(constant(0))))
            .put("object_id", f.delivery.getString("object_id")).put("base_revision", 1))
        assertFalse(f.evaluate().accepted)
    }

    @Test fun goalLoopRejectsModifiedTestsBeforeNewWorkCanRun() {
        val before = criterion()
        val changed = JSONObject(before.toString())
        changed.getJSONObject("validator").getJSONArray("cases").remove(1)
        val report = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Claim completion")
            .put("decision", "achieved").put("criteria", JSONArray().put(changed.put("status", "met")))
            .put("work", JSONArray()).put("blockers", JSONArray())
        assertNotNull(CollaborationGoalLoop.decode(report.toString()))
        assertEquals("continue", CollaborationGoalLoop.disposition(report.toString(), JSONArray().put(before).toString(), acceptanceVerified = true))
        changed.getJSONObject("validator").put("id", "unqualified")
        assertNull(CollaborationGoalLoop.decode(report.toString()))
    }
}
