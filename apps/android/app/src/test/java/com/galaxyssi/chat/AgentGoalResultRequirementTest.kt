package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentGoalResultRequirementTest {
    private val battery = AgentGoalResultRequirement("battery", "Report battery percentage")
    private val storage = AgentGoalResultRequirement("storage", "Report available internal storage")
    private val pending = AgentCompletionRequirements(AgentPublicationRequirement.NONE, false,
        results = listOf(battery, storage))
    private val batteryOutcome = AgentObservedOutcome("battery_value", "galaxyssi.fixture.battery",
        mapOf("/device" to "phone"), mapOf("/percent" to 42))
    private val storageOutcome = AgentObservedOutcome("storage_value", "galaxyssi.fixture.storage",
        mapOf("/volume" to "internal"), mapOf("/available_bytes" to 1000))
    private val verified = pending.copy(reason = "Bound both requested values to actual observations",
        outcomes = listOf(batteryOutcome, storageOutcome), results = listOf(
            battery.copy(outcomeIds = listOf(batteryOutcome.id), answer = "Battery: 42%"),
            storage.copy(outcomeIds = listOf(storageOutcome.id), answer = "Available: 1000 bytes")))
    private val answer = "Battery: 42%\nAvailable: 1000 bytes"
    private fun receipt(tool: String, output: String) = AgentAction(tool, AgentActionKind.CALL_NATIVE_TOOL,
        tool, AgentRisk.LOW, AgentActionStatus.COMPLETED, "Read", mapOf("tool_id" to tool), evidence = output)
    private val receipts = listOf(receipt(batteryOutcome.toolId, """{"device":"phone","percent":42}"""),
        receipt(storageOutcome.toolId, """{"volume":"internal","available_bytes":1000}"""))

    @Test fun pendingAndVerifiedResultsRoundTripWithoutLosingIdentityOrEvidence() {
        for (value in listOf(pending, verified)) {
            val stored = value.toJson().toString()
            assertEquals(value, AgentCompletionRequirements.parse(JSONObject(stored)))
            val operation = AgentDeviceOperation("conversation", kind = "agent", goal = "Read both values",
                completionJson = stored)
            assertTrue(operation.context().contains("Report available internal storage"))
            assertEquals(value, AgentCompletionRequirements.parse(JSONObject(operation.completionJson)))
        }
    }

    @Test fun planningRequiresResultsButDoesNotInventTheirUnknownValues() {
        assertNotNull(AgentGoalResultEvidence.planningViolation(null, required = true))
        assertNotNull(AgentGoalResultEvidence.planningViolation(pending.copy(results = emptyList()), required = true))
        assertNull(AgentGoalResultEvidence.planningViolation(pending, required = true))
        assertNull(AgentGoalResultEvidence.planningViolation(null, required = false))
        assertFalse(AgentSupervisedProjectCompletionPolicy.missingEvidence(pending, receipts, answer, true).isEmpty())
    }

    @Test fun completingOneRequestedResultCannotHideAnotherPendingResult() {
        val partial = verified.copy(results = listOf(verified.results.first(), storage))
        val missing = AgentSupervisedProjectCompletionPolicy.missingEvidence(partial, receipts, "Battery: 42%", true)
        assertTrue(missing.any { it.contains("storage needs outcome_ids") })
        assertTrue(missing.any { it.contains("storage needs an evidence-grounded answer") })
    }

    @Test fun declarationsAndAnswersCannotReplaceActualObservations() {
        assertFalse(AgentSupervisedProjectCompletionPolicy.missingEvidence(verified, emptyList(), answer, true).isEmpty())
        assertFalse(AgentSupervisedProjectCompletionPolicy.missingEvidence(verified, receipts.take(1), answer, true).isEmpty())
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(verified, receipts, answer, true).isEmpty())
    }

    @Test fun finalAnswerMustIncludeEveryEvidenceBoundResult() {
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(verified, receipts, "Battery: 42%", true)
            .any { it.contains("storage is missing from the final answer") })
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(verified, receipts, "Done", true).size >= 2)
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(verified, receipts, answer, true).isEmpty())
    }

    @Test fun unknownReferencesAndBlankProofAreRejected() {
        val bad = verified.copy(results = listOf(battery.copy(outcomeIds = listOf("invented"),
            artifactPaths = listOf("outputs/missing.pdf"), answer = "Done"), verified.results.last()))
        val missing = AgentSupervisedProjectCompletionPolicy.missingEvidence(bad, receipts, "Done\nAvailable: 1000 bytes", true)
        assertTrue(missing.any { it.contains("undeclared outcome invented") })
        assertTrue(missing.any { it.contains("undeclared artifact outputs/missing.pdf") })
    }

    @Test fun newFailureWrongSubjectAndStaleEvidenceRemainFailures() {
        for (newer in listOf(receipts.last().copy(evidence = """{"volume":"internal","available_bytes":0}"""),
            receipts.last().copy(status = AgentActionStatus.FAILED))) {
            assertFalse(AgentSupervisedProjectCompletionPolicy.missingEvidence(verified, receipts + newer, answer, true).isEmpty())
        }
        assertFalse(AgentSupervisedProjectCompletionPolicy.missingEvidence(verified,
            receipts.take(1) + receipts.last().copy(evidence = """{"volume":"external","available_bytes":1000}"""), answer, true).isEmpty())
        val after = verified.copy(outcomes = listOf(batteryOutcome, storageOutcome.copy(afterToolId = "galaxyssi.fixture.write")))
        assertFalse(AgentSupervisedProjectCompletionPolicy.missingEvidence(after,
            receipts + receipt("galaxyssi.fixture.write", "{}"), answer, true).isEmpty())
    }

    @Test fun resultIdsCannotBeRemovedEvenWithAnExplanation() {
        assertTrue(verified.canReplace(pending))
        assertFalse(verified.copy(reason = "").canReplace(pending))
        assertFalse(verified.copy(results = verified.results.take(1), reason = "The other result is not ready").canReplace(pending))
        assertFalse(verified.copy(results = emptyList(), reason = "Tools succeeded").canReplace(pending))
        assertFalse(verified.copy(results = verified.results.map { it.copy(id = "new_${it.id}") }).canReplace(pending))
        assertTrue(verified.copy(results = verified.results + AgentGoalResultRequirement("extra", "An additional result"))
            .canReplace(pending))
    }

    @Test fun declaredArtifactsStillRequireHashBoundOpeningEvidence() {
        val required = pending.copy(results = listOf(AgentGoalResultRequirement("report", "Deliver a readable report",
            artifactPaths = listOf("outputs/report.pdf"), answer = "Report ready")),
            artifacts = listOf(AgentArtifactRequirement("outputs/report.pdf")))
        assertTrue(AgentGoalResultEvidence.missing(required, "Report ready", required = true).isEmpty())
        assertFalse(AgentSupervisedProjectCompletionPolicy.missingEvidence(required, emptyList(), "Report ready", true).isEmpty())
    }

    @Test fun malformedOrDuplicateResultsCannotSilentlyBecomeAnEmptyList() {
        for (bad in listOf(JSONObject.NULL, "bad", 1, JSONObject())) {
            assertNull(AgentCompletionRequirements.parse(pending.toJson().put("results", bad)))
        }
        assertNull(AgentCompletionRequirements.parse(pending.toJson().put("results",
            JSONArray().put(battery.toJson()).put(battery.toJson()))))
        for ((key, bad) in listOf("id" to "", "description" to " ", "answer" to JSONObject.NULL,
            "outcome_ids" to "id", "outcome_ids" to JSONArray().put(123),
            "outcome_ids" to JSONArray().put("same").put("same"),
            "artifact_paths" to JSONArray().put("../outside.txt"))) {
            assertNull(key, AgentGoalResultRequirement.parse(battery.toJson().put(key, bad)))
        }
    }

    @Test fun optionalLegacyProjectDeclarationsDoNotAcquireInventedResults() {
        val legacy = AgentCompletionRequirements.parse(JSONObject("""{"publication":"none","phone_linux":false}"""))!!
        assertTrue(legacy.results.isEmpty())
        assertTrue(AgentSupervisedProjectCompletionPolicy.missingEvidence(legacy, emptyList()).isEmpty())
        assertFalse(AgentSupervisedProjectCompletionPolicy.missingEvidence(legacy, receipts, answer, true).isEmpty())
    }
}
