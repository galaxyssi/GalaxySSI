package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationExperimentResultFeedbackTest {
    private val access = CollaborationWorkspaceAccess("group", "run", "turn", 4, "reporter", "reporter")
    private fun value() = JSONObject().put("interpretation", "Original observational report")
        .put("limitations", "Not a controlled comparison")
    private fun draft(value: JSONObject = value(), kind: String = "experiment_result") = JSONObject()
        .put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Preserved report")
        .put("workspace", JSONArray().put(JSONObject().put("id", "report").put("kind", kind).put("title", "Original report")
            .put("body", JSONObject().put("content", "Complete original report").put("experiment_result", value)))).toString()
    private fun detail(receipt: JSONObject): JSONObject {
        assertEquals("rejected", receipt.getString("status"))
        return receipt.getJSONObject(CollaborationRecordValidation.DETAIL)
    }
    private fun fixture() = CollaborationEvolutionTest.Fixture(CollaborationEvolutionTest())

    @Test fun missingPlanReportsSemanticsAndPreservesValidJsonDraftAcrossReopen() {
        val rows = CollaborationEvolutionTest.Rows()
        val workspace = CollaborationResearchWorkspace(rows)
        workspace.enrollPublication(access, CollaborationResearchStage.REVISE)
        val recovery = CollaborationPublicationRecovery(workspace, access)
        val raw = draft()
        assertFalse(recovery.accept(raw))
        val problem = detail(recovery.latest!!.getJSONObject("receipt"))
        assertEquals("experiment_plan_reference_required", problem.getString("code"))
        assertEquals("/body/experiment_result/plan", problem.getString("path"))
        assertEquals("absent", problem.getString("actual"))
        assertEquals("ExperimentResultValidator", problem.getString("component"))
        val contract = problem.getJSONObject("record_contract")
        assertEquals("preregistered_baseline_candidate_comparison", contract.getString("purpose"))
        assertTrue(contract.getBoolean("registration_before_measurements_required"))
        assertFalse(contract.getBoolean("automatic_conversion"))
        assertTrue(contract.getString("guidance").contains("coordinator assistance"))
        assertTrue(workspace.browse(access).revisions.isEmpty())
        val reopened = CollaborationPublicationRecovery(CollaborationResearchWorkspace(rows), access)
        assertEquals(raw, reopened.latest!!.getString("raw"))
        assertEquals("accepted", reopened.latest!!.getJSONObject("problem_state").getString("json_parse_status"))
        assertEquals("workspace_contract", reopened.latest!!.getJSONObject("problem_state").getString("failure_phase"))
        assertTrue(reopened.feedback().contains(CollaborationEvolutionExperiment.RESULT_GUIDANCE))
    }

    @Test fun nullStringAndArrayPlanAreTypedErrorsNotJsonErrors() {
        for (plan in listOf(JSONObject.NULL, "previous plan", JSONArray())) {
            val workspace = CollaborationResearchWorkspace(CollaborationEvolutionTest.Rows())
            val error = detail(workspace.publish(access, draft(value().put("plan", plan))))
            assertEquals("experiment_plan_reference_invalid", error.getString("code"))
            assertEquals(if (plan == JSONObject.NULL) "null" else "not an object", error.getString("actual"))
        }
    }

    @Test fun wrongKindKeepsExactReferenceFactsAndExplainsRecordPurpose() {
        val f = fixture()
        val error = detail(f.workspace.publish(access, draft(value().put("plan", f.baseline))))
        assertEquals("record_kind_mismatch", error.getString("code"))
        assertEquals("WorkspaceRecordValidator", error.getString("component"))
        assertEquals("/body/experiment_result/plan/kind", error.getString("path"))
        assertEquals("artifact", error.getString("actual"))
        assertEquals("experiment_plan", error.getJSONArray("expected").getString(0))
        assertEquals(f.baseline.getString("object_id"), error.getJSONObject("reference").getString("object_id"))
        assertEquals("foundation", error.getJSONObject("record_contract").getString("rules_topic"))
    }

    @Test fun badDigestAndIsolatedPlanAreNotInventedOrReadThrough() {
        val f = fixture()
        val wrong = JSONObject(f.plan.toString()).put("sha256", "0".repeat(64))
        val mismatch = detail(f.workspace.publish(access, draft(value().put("plan", wrong))))
        assertEquals("record_digest_mismatch", mismatch.getString("code"))
        val other = access.copy(groupId = "unrelated")
        val isolated = detail(f.workspace.publish(other, draft(value().put("plan", f.plan))))
        assertEquals("record_unavailable", isolated.getString("code"))
        assertEquals("missing or isolated", isolated.getString("actual"))
        assertFalse(isolated.has("record"))
    }

    @Test fun malformedReferenceKeepsFieldLevelFacts() {
        val f = fixture()
        val error = detail(f.workspace.publish(access, draft(value().put("plan", JSONObject(f.plan.toString()).put("revision", 1.5)))))
        assertEquals("record_revision_invalid", error.getString("code"))
        assertEquals("/body/experiment_result/plan/revision", error.getString("path"))
        assertEquals(1.5, error.getDouble("actual"), 0.0)
        assertEquals("positive integer", error.getString("expected"))
    }

    @Test fun infrastructureFailureIsNotReclassifiedAsMemberValidationError() {
        val failure = IllegalStateException("Storage unavailable")
        val caught = assertThrows(IllegalStateException::class.java) {
            CollaborationEvolutionExperiment.result(value().put("plan", JSONObject()), JSONObject(),
                { _, _ -> throw failure }, { null }, {})
        }
        assertSame(failure, caught)
    }

    @Test fun memberCanPreserveObservationAsArtifactButCannotClaimExperimentOrRetention() {
        val rows = CollaborationEvolutionTest.Rows()
        val workspace = CollaborationResearchWorkspace(rows)
        workspace.enrollPublication(access, CollaborationResearchStage.REVISE)
        val recovery = CollaborationPublicationRecovery(workspace, access)
        val original = value()
        assertFalse(recovery.accept(draft(original)))
        assertTrue(recovery.accept(draft(original, "artifact")))
        val entry = workspace.browse(access).revisions.single()
        val saved = requireNotNull(workspace.read(access, entry.getString("object_id"), entry.getInt("revision")))
        assertEquals("artifact", saved.getString("kind"))
        assertEquals(original.toString(), saved.getJSONObject("body").getJSONObject("experiment_result").toString())
        assertFalse(saved.has(CollaborationEvolutionContract.HOST))
        assertEquals(2, rows.data.keys.count { ":attempt:" in it })
        assertEquals(0, workspace.browseEvolution(access).revisions.size)
    }

    @Test fun memberChosenAssistancePreservesDraftWithoutHostRetryDecision() {
        val workspace = CollaborationResearchWorkspace(CollaborationEvolutionTest.Rows())
        workspace.enrollPublication(access, CollaborationResearchStage.REVISE)
        val recovery = CollaborationPublicationRecovery(workspace, access)
        val raw = draft()
        assertFalse(recovery.accept(raw))
        val request = JSONObject().put("format", CollaborationPublicationAssistance.FORMAT)
            .put("diagnosis", "Assignment requested a paired experiment record for observational evidence")
            .put("attempted_corrections", "Checked saved record rules and original report")
            .put("requested_help", "Decide whether documentary delivery or a new prospective comparison serves the goal")
        assertThrows(CollaborationPublicationAssistanceException::class.java) { recovery.accept(request.toString()) }
        assertEquals(raw, workspace.publicationCheckpoint(access)!!.getString("raw"))
        assertNotNull(workspace.publicationAssistance(access))
        assertTrue(workspace.browse(access).revisions.isEmpty())
    }

    @Test fun properPlanStillNeedsRealMeasurementsAndRejectsPostHocRegistration() {
        val without = fixture()
        assertEquals("rejected", without.publishResult().getString("status"))
        val historical = fixture()
        historical.trial(started = 50)
        assertTrue(historical.publishResult().getString("reason").contains("predates preregistration"))
        val valid = fixture()
        valid.trial()
        assertEquals("recorded", valid.publishResult().getString("status"))
    }

    @Test fun rulesDescribeChoicesWithoutChangingGoalAcceptanceOrAutomaticConversion() {
        val foundation = CollaborationEvolutionProtocol.rules("foundation").getString("contract")
        assertTrue(foundation.contains(CollaborationEvolutionExperiment.RESULT_GUIDANCE))
        assertTrue(foundation.contains("not any tool or search result"))
        assertTrue(foundation.contains("does not qualify as experiment_result"))
        assertTrue(CollaborationGoalLoop.instructions().contains("preserve original reports, criteria and verification types"))
    }
}
