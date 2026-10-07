package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationExecutableTool.RELEASE

class CollaborationExecutableAcceptanceTest {
    internal class Fixture(
        val tools: CollaborationExecutableToolTest.Fixture = CollaborationExecutableToolTest.Fixture(),
        result: AgentNativeToolExecutionResult = tools.finish(),
        val reviewer: String = "goal-reviewer",
        citeDelivery: Boolean = true,
        citeReview: Boolean = true,
        readReview: Boolean = true,
        val requirement: String = CollaborationExecutableAcceptance.REQUIREMENT
    ) {
        val observation = tools.observed(result)
        val release = tools.ref(tools.release(observation))
        val validator = specification(tools.planSpec)
        val criterion = JSONObject().put("id", "tested-program").put("requirement", requirement)
            .put("verification", "computational").put("evidence_kind", "observed")
            .put("status", "open").put("evidence", JSONArray()).put("validator", validator)
        val prior = JSONArray().put(criterion).toString()
        val access = tools.access("coordinator", 12)
        val reviewAccess = tools.access(reviewer, 7, "goal-review")
        val delivery = publish("delivery", "artifact", JSONObject().put("content", "Actual program output on the preserved suite only")
            .put("computation", JSONObject().put("validator_id", CollaborationExecutableAcceptance.id).put(RELEASE, release)),
            tools.access("author", 6, "delivery"), observations = if (citeDelivery) JSONArray().put(observation) else JSONArray())
        val review: JSONObject
        val mapping: JSONObject
        val coverageReview: JSONObject

        init {
            if (readReview) readOriginal(reviewAccess)
            review = publish("goal-review", CollaborationReviewContract.KIND, JSONObject().put(CollaborationReviewContract.KIND,
                JSONObject().put("criterion_id", "tested-program").put("requirement", requirement).put("target", delivery)
                    .put("verdict", "supported").put("rationale", "Checked original runtime output and finite-suite scope")
                    .put("unresolved", JSONArray())), reviewAccess, JSONArray().put(delivery),
                if (citeReview) JSONArray().put(observation) else JSONArray())
            val source = CollaborationSemanticGoalCoverage.source(requirement)
            fun segments(reviewing: Boolean) = JSONArray().apply {
                val parts = source.getJSONArray("segments")
                repeat(parts.length()) { i -> put(JSONObject().put("id", parts.getJSONObject(i).getString("id"))
                    .put("criterion_ids", JSONArray().put("tested-program")).put("rationale", "Finite executed suite only").apply {
                        if (reviewing) put("verdict", "supported").put("unresolved", JSONArray())
                    }) }
            }
            mapping = publish("mapping", "artifact", JSONObject().put(CollaborationSemanticGoalCoverage.MAPPING,
                JSONObject().put("format", CollaborationSemanticGoalCoverage.FORMAT).put("goal_sha256", source.getString("goal_sha256"))
                    .put("criteria_sha256", CollaborationSemanticGoalCoverage.criteriaHash(JSONArray(prior)))
                    .put("segments", segments(false))), tools.access("mapper", 8))
            coverageReview = publish("coverage-review", CollaborationReviewContract.KIND,
                JSONObject().put(CollaborationSemanticGoalCoverage.REVIEW, JSONObject().put("target", mapping)
                    .put("verdict", "supported").put("rationale", "No broader claim was requested in this fixture")
                    .put("unresolved", JSONArray()).put("segments", segments(true))), tools.access("coverage-reviewer", 9), JSONArray().put(mapping))
        }

        fun readOriginal(who: CollaborationWorkspaceAccess) {
            var offset: Int? = 0
            while (offset != null) offset = tools.ledger.readPage(who, observation.getString("evidence_id"), observation.getString("sha256"), offset)!!.next
        }
        fun publish(id: String, kind: String, body: JSONObject, who: CollaborationWorkspaceAccess,
                    parents: JSONArray = JSONArray(), observations: JSONArray = JSONArray()): JSONObject {
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Executable acceptance fixture")
                .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject()
                    .put("id", id).put("kind", kind).put("title", id).put("body", body)
                    .put("parents", parents).put("observations", observations)))
            return tools.ref(tools.workspace.publish(who, raw.toString(), who.round * 10))
        }
        fun assessment() = JSONObject().put("format", CollaborationGoalLoop.FORMAT).put("summary", "Finite suite executed and reviewed")
            .put("decision", "achieved").put("criteria", JSONArray().put(JSONObject(criterion.toString()).put("status", "met")
                .put("evidence", JSONArray().put("workspace:" + delivery.getString("object_id"))).put("delivery", delivery).put("review", review)))
            .put("work", JSONArray()).put("blockers", JSONArray()).put(CollaborationSemanticGoalCoverage.FIELD,
                JSONObject().put("mapping", mapping).put("review", coverageReview))
        fun evaluate(raw: JSONObject = assessment(), previous: String = prior, who: CollaborationWorkspaceAccess = access,
                     workspace: CollaborationResearchWorkspace = tools.workspace) =
            CollaborationGoalAcceptance(workspace, tools.ledger).evaluate(who, raw.toString(), previous, requirement, 200)
    }

    @Test fun observedExecutedSuitePassesThroughProductionGoalGateAndReopens() {
        val f = Fixture()
        assertTrue(f.evaluate().feedback, f.evaluate().accepted)
        assertTrue(f.evaluate(workspace = f.tools.reopen()).accepted)
        assertFalse(f.evaluate().feedback.contains("scientifically verified"))
    }

    @Test fun neitherModelClaimNorMissingHostContextIsAnExecutionReceipt() {
        val f = Fixture()
        val body = f.tools.resolve(f.delivery, "artifact", f.access).getJSONObject("body")
        assertThrows(IllegalArgumentException::class.java) { CollaborationQualifiedValidation.validate(f.criterion, body) }
        assertThrows(IllegalArgumentException::class.java) { CollaborationExecutableAcceptance.validate(f.criterion, body) }
    }

    @Test fun suiteInputsEnvironmentAndOracleCannotChangeDuringContinuation() {
        for (field in listOf("environment", "oracle_basis", "purpose", "coverage_gaps", "cases")) {
            val f = Fixture()
            val raw = f.assessment()
            val spec = raw.getJSONArray("criteria").getJSONObject(0).getJSONObject("validator")
            if (field == "cases") spec.getJSONArray("cases").getJSONObject(0).put("expected", JSONArray("[3,2,1]")) else spec.put(field, "changed")
            assertFalse(field, f.evaluate(raw).accepted)
        }
        val f = Fixture()
        assertFalse(f.evaluate(previous = JSONArray(f.prior).apply { getJSONObject(0).remove("validator") }.toString()).accepted)
    }

    @Test fun executedPlanMustMatchThePreviouslyPreservedSuiteNotJustAPassingRelease() {
        val f = Fixture()
        val raw = f.assessment()
        raw.getJSONArray("criteria").getJSONObject(0).getJSONObject("validator").put("environment", "different-runtime")
        // Even matching forged criteria/mapping cannot replace the actual plan contract.
        val body = f.tools.resolve(f.delivery, "artifact", f.access).getJSONObject("body")
        assertThrows(IllegalArgumentException::class.java) { CollaborationExecutableAcceptance.validateRecorded(
            raw.getJSONArray("criteria").getJSONObject(0), body, evidence(f)) }
    }

    @Test fun deliveryAndReviewerMustCiteTheOriginalAndReviewerMustReadIt() {
        assertFalse(Fixture(citeDelivery = false).evaluate().accepted)
        assertFalse(Fixture(citeReview = false).evaluate().accepted)
        val unread = Fixture(readReview = false)
        assertFalse(unread.evaluate().accepted)
        unread.readOriginal(unread.reviewAccess)
        assertFalse("Later reading does not change the frozen review", unread.evaluate().accepted)
    }

    @Test fun authorCannotSelfAcceptThroughASeparateDeliveryWriter() {
        val f = Fixture(reviewer = "author")
        val receipt = f.evaluate()
        assertFalse(receipt.accepted)
        assertTrue(receipt.feedback.contains("contributor"))
    }

    @Test fun historicalReceiptCannotStandInForCurrentGoalExecution() {
        val f = Fixture()
        val host = evidence(f)
        val later = JSONObject(host.delivery.toString()).put("run_id", "later-run").put("turn_id", "later-turn")
        assertThrows(IllegalArgumentException::class.java) {
            CollaborationExecutableAcceptance.validateRecorded(f.criterion, host.delivery.getJSONObject("body"), host.copy(delivery = later))
        }
    }

    @Test fun finiteCasesCannotCertifyScientificTruthPhysicalExperimentsOrBroadCorrectness() {
        assertFalse(Fixture(requirement = "Prove the generated program is correct for all possible inputs").evaluate().accepted)
        val f = Fixture()
        for (kind in listOf("proposal", "simulation")) {
            val raw = f.assessment()
            raw.getJSONArray("criteria").getJSONObject(0).put("evidence_kind", kind)
            assertFalse(f.evaluate(raw).accepted)
        }
    }

    @Test fun preservedSpecificationRejectsCoercionUnknownFieldsAndMissingRegression() {
        val f = Fixture()
        for (mutate in listOf<(JSONObject) -> Unit>(
            { it.put("shell", "arbitrary execution") }, { it.put("environment", 12) },
            { it.getJSONArray("cases").getJSONObject(0).put("input", "not an object") },
            { it.getJSONArray("cases").getJSONObject(0).remove("expected") },
            { it.getJSONArray("cases").getJSONObject(2).put("purpose", "target") },
            { it.getJSONArray("cases").put(it.getJSONArray("cases").getJSONObject(0)) }
        )) {
            val value = JSONObject(f.validator.toString()); mutate(value)
            assertThrows(IllegalArgumentException::class.java) { CollaborationExecutableAcceptance.binding(value) }
        }
    }

    @Test fun jsonPersistenceAndKeyOrderDoNotInvalidatePreservedBinding() {
        val first = specification(CollaborationExecutableToolTest.Fixture().planSpec)
        first.getJSONArray("cases").getJSONObject(0).put("expected", JSONArray().put(1.0).put(2).put(3))
        val second = JSONObject(first.toString())
        val reverse = JSONObject().apply { second.keys().asSequence().toList().reversed().forEach { put(it, second.get(it)) } }
        assertEquals(CollaborationExecutableAcceptance.binding(first), CollaborationExecutableAcceptance.binding(reverse))
    }

    private fun evidence(f: Fixture) = CollaborationValidationEvidence(
        f.tools.resolve(f.delivery, "artifact", f.access), f.tools.resolve(f.review, CollaborationReviewContract.KIND, f.access),
        { ref, kind -> f.tools.resolve(ref, kind, f.access) },
        { ref -> f.tools.ledger.read(f.access, ref.getString("evidence_id"), ref.getString("sha256")) },
        { f.tools.ledger.requireReadCoverage(f.access, it) }, { f.tools.workspace.contributorIds(f.access, it) })

    companion object {
        fun specification(plan: JSONObject) = JSONObject().put("id", CollaborationExecutableAcceptance.id).apply {
            listOf("environment", "purpose", "oracle_basis", "coverage_gaps", "cases").forEach { put(it, plan.get(it)) }
        }
    }
}
