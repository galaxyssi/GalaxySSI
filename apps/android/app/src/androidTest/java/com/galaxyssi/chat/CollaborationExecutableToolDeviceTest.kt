package com.galaxyssi.chat

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import com.galaxyssi.chat.CollaborationExecutableTool.TOOL
import com.galaxyssi.chat.CollaborationExecutableTool.TEST
import com.galaxyssi.chat.CollaborationExecutableTool.RELEASE

/** Synthetic host receipts and real encrypted storage/dispatch checks; no model or Linux process. */
@RunWith(AndroidJUnit4::class)
class CollaborationExecutableToolDeviceTest {
    @Test fun savedToolReleaseReopensAndIsBoundToExactMemberWithoutInstallingSkill() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val group = "tool-fixture-${UUID.randomUUID()}"
        val groups = CollaborationGroupStore(context)
        groups.update(group) { it.copy(members = listOf("author", "reviewer", "worker").map { id -> CollaborationMember(id, id, "fixture", "Fixture") }, coordinatorId = "reviewer") }
        try {
            val ledger = CollaborationEvidenceLedger(context)
            val workspace = CollaborationResearchWorkspace(context)
            fun access(person: String, round: Long, node: String = person) = CollaborationWorkspaceAccess(group, "run", "turn", round, node, person)
            fun publish(id: String, kind: String, value: JSONObject, person: String, round: Long, observations: JSONArray = JSONArray(),
                        body: JSONObject? = null, parents: JSONArray = JSONArray()): JSONObject {
                val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Local fixture")
                    .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject().put("id", id)
                        .put("kind", kind).put("title", id).put("body", body ?: JSONObject().put("content", "Synthetic tool fixture").put(kind, value))
                        .put("observations", observations).put("parents", parents)))
                val saved = workspace.publish(access(person, round, id), raw.toString(), round * 10)
                assertEquals(saved.toString(), "recorded", saved.getString("status"))
                return saved.getJSONArray("revisions").getJSONObject(0)
            }
            val tool = publish("echo", TOOL, JSONObject().put("name", "Fixture echo").put("purpose", "Echo a number").put("language", "python")
                .put("source", "def run(parameters):\n    return parameters['value']\n").put("environment", "synthetic-device-fixture")
                .put("dependencies", "Python").put("applies_when", "Fixture only").put("avoid_when", "Production")
                .put("side_effects", "None").put("input_schema", JSONObject("""{"type":"object","properties":{"value":{"type":"integer"}},"required":["value"],"additional_properties":false}""")), "author", 1)
            fun case(id: String, purpose: String, value: Int) = JSONObject().put("id", id).put("purpose", purpose).put("reason", "Fixture")
                .put("input", JSONObject().put("value", value)).put("expected", value)
            val plan = publish("tests", TEST, JSONObject().put(TOOL, tool).put("environment", "synthetic-device-fixture")
                .put("purpose", "Echo correctness").put("oracle_basis", "Identity").put("coverage_gaps", "Fixture only")
                .put("cases", JSONArray().put(case("one", "target", 1)).put(case("zero", "regression", 0))), "reviewer", 2)
            val binding = System.nanoTime()
            ledger.bind(binding, access("worker", 3))
            fun invocation(input: JSONObject, source: Long? = binding, turn: String = "turn") = AgentNativeToolInvocation(
                descriptor = AgentNativeToolDescriptor(AgentOnDeviceRuntimeTools.EXECUTE, "1.0.0", "Fixture", "Fixture", AgentNativeToolLocation.PHONE,
                    AgentNativeJsonSchema.objectSchema(), AgentNativeJsonSchema.objectSchema(), AgentNativeToolRisk.LOW),
                input = mapOf(CollaborationToolRuntime.INPUT to input.toNativeObject()),
                context = AgentNativeToolInvocationContext(conversationId = group, turnId = turn, collaborationSourceMessageId = source),
                initialDeadlineEpochMillis = Long.MAX_VALUE, hardDeadlineEpochMillis = null,
                cancellationToken = AgentNativeToolCancellationToken.NONE, clock = AgentNativeClock.SYSTEM, progressReporter = { _, _ -> })
            val testCall = invocation(JSONObject().put("mode", "test").put(TEST, plan))
            val prepared = CollaborationToolRuntime.prepare(context, testCall)!!
            val report = JSONObject().put("format", CollaborationToolRuntime.FORMAT)
                .put("runtime", JSONObject().put("python", JSONArray("[3,12,0]")).put("implementation", "fixture").put("machine", "synthetic"))
                .put("results", JSONArray().put(JSONObject().put("id", "one").put("output", 1)).put(JSONObject().put("id", "zero").put("output", 0)))
            val clipped = AgentRuntimeExecutionResponse(0, report.toString(), "", 1).boundedOutput(30, 0)
            val clippedResult = CollaborationToolRuntime.finish(prepared, clipped, AgentNativeToolExecutionResult.success())
            assertEquals("report_stdout_truncated", JSONObject(clippedResult.error!!.details).getJSONArray("problems").getJSONObject(0).getString("code"))
            val badReport = JSONObject(report.toString()).apply { getJSONArray("results").getJSONObject(0).put("output", 7) }
            val failure = CollaborationToolRuntime.finish(prepared, AgentRuntimeExecutionResponse(0, badReport.toString(), "", 1), AgentNativeToolExecutionResult.success())
            assertFalse(failure.isSuccess)
            val details = JSONObject(failure.error!!.details)
            assertEquals("/results/0/output", details.getJSONArray("problems").getJSONObject(0).getString("path"))
            val originalFailure = JSONObject().put("output", JSONObject(failure.output)).put("error", JSONObject()
                .put("code", failure.error!!.code).put("details", details)).toString()
            val failedObservation = ledger.record(access("worker", 3), "synthetic-failed-test", AgentOnDeviceRuntimeTools.EXECUTE,
                "{}", originalFailure, 30, 31, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
            val reopenedEvidence = CollaborationEvidenceLedger(context)
            assertEquals(originalFailure, reopenedEvidence.read(access("reviewer", 4), failedObservation.getString("evidence_id"))!!.getString("output_json"))
            val recalledProblem = reopenedEvidence.problems(access("reviewer", 4)).first.single().getJSONObject("host_problem")
            assertEquals("not_diagnosed", recalledProblem.getString("cause"))
            assertTrue(recalledProblem.getJSONArray("signals").toString().contains("value_mismatch"))
            val result = CollaborationToolRuntime.finish(prepared, AgentRuntimeExecutionResponse(0, report.toString(), "", 1), AgentNativeToolExecutionResult.success())
            assertTrue(result.isSuccess)
            val observation = ledger.record(access("worker", 3), "synthetic-test", AgentOnDeviceRuntimeTools.EXECUTE, "{}",
                JSONObject().put("output", JSONObject(result.output)).toString(), 30, 31, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
            var offset: Int? = 0
            while (offset != null) offset = ledger.readPage(access("reviewer", 4, "release"), observation.getString("evidence_id"), observation.getString("sha256"), offset)!!.next
            val release = publish("release", RELEASE, JSONObject().put(TEST, plan).put("observation", observation).put("review", "Synthetic code/oracle review")
                .put("applies_when", "Fixture").put("avoid_when", "Production").put("limitations", "Not Linux execution")
                .put("authorization_boundary", "No new permissions").put("unresolved", JSONArray()), "reviewer", 4, JSONArray().put(observation))
            val reopened = CollaborationResearchWorkspace(context)
            assertEquals(1, reopenedEvidence.problems(access("worker", 5)).first.size)
            assertNotNull(reopened.read(access("worker", 5).copy(runId = "future", turnId = "future"), release.getString("object_id"), 1))
            val nextBinding = binding + 1
            val future = access("worker", 0).copy(runId = "future", turnId = "future")
            ledger.bind(nextBinding, future)
            val matches = JSONObject(CollaborationCloudRecall.execute(context, future,
                JSONObject().put("mode", "capabilities").put("query", "echo"))).getJSONArray("records")
            assertEquals(1, matches.length())
            val found = matches.getJSONObject(0)
            assertEquals(release.getString("sha256"), found.getString("sha256"))
            assertEquals(tool.getString("sha256"), found.getJSONArray("linked_sources").getJSONObject(0)
                .getJSONObject("source").getString("sha256"))
            assertFalse(found.getJSONArray("linked_sources").getJSONObject(0).getBoolean("complete_read"))
            assertFalse(found.getBoolean("grants_permissions"))
            val run = JSONObject().put("mode", "run").put(RELEASE, found).put("parameters", JSONObject().put("value", 9))
            val restored = CollaborationToolRuntime.prepare(context, invocation(run, nextBinding, "future"))!!
            assertEquals(tool.getString("sha256"), restored.identity.getJSONObject(TOOL).getString("sha256"))
            assertNotNull(runCatching { CollaborationToolRuntime.prepare(context, invocation(run, null)) }.exceptionOrNull())
            assertNotNull(runCatching { CollaborationToolRuntime.prepare(context, invocation(run, nextBinding, "wrong-turn")) }.exceptionOrNull())
            val goalAccess = access("reviewer", 9, "goal-check")
            val planSpec = reopened.read(goalAccess, plan.getString("object_id"), 1)!!.getJSONObject("body").getJSONObject(TEST)
            val validator = JSONObject().put("id", CollaborationExecutableAcceptance.id).apply {
                listOf("environment", "purpose", "oracle_basis", "coverage_gaps", "cases").forEach { put(it, planSpec.get(it)) }
            }
            val criterion = JSONObject().put("id", "executed-tool").put("requirement", CollaborationExecutableAcceptance.REQUIREMENT)
                .put("verification", "computational").put("evidence_kind", "observed").put("validator", validator)
            val deliveryBody = JSONObject().put("content", "Synthetic observation on a real device, not real Linux execution")
                .put("computation", JSONObject().put("validator_id", CollaborationExecutableAcceptance.id).put(RELEASE, release))
            val delivery = publish("goal-delivery", "artifact", JSONObject(), "author", 6, JSONArray().put(observation), deliveryBody)
            offset = 0
            while (offset != null) offset = reopenedEvidence.readPage(access("reviewer", 7, "goal-review"), observation.getString("evidence_id"),
                observation.getString("sha256"), offset)!!.next
            val reviewBody = JSONObject().put("content", "Synthetic receipt checked").put(CollaborationReviewContract.KIND,
                JSONObject().put("criterion_id", "executed-tool").put("requirement", CollaborationExecutableAcceptance.REQUIREMENT)
                    .put("target", delivery).put("verdict", "supported").put("rationale", "Synthetic finite-case fixture only").put("unresolved", JSONArray()))
            val review = publish("goal-review", CollaborationReviewContract.KIND, JSONObject(), "reviewer", 7,
                JSONArray().put(observation), reviewBody, JSONArray().put(delivery))
            val afterReopen = CollaborationResearchWorkspace(context)
            fun exact(ref: JSONObject, kind: String): JSONObject {
                val record = requireNotNull(afterReopen.read(goalAccess, ref.getString("object_id"), ref.getInt("revision")))
                require(record.getString("kind") == kind && CollaborationResearchCandidates.same(record, ref))
                return record
            }
            val verification = CollaborationValidationEvidence(exact(delivery, "artifact"), exact(review, CollaborationReviewContract.KIND), ::exact,
                { ref -> reopenedEvidence.read(goalAccess, ref.getString("evidence_id"), ref.getString("sha256")) },
                { reopenedEvidence.requireReadCoverage(goalAccess, it) }, { afterReopen.contributorIds(goalAccess, it) })
            CollaborationQualifiedValidation.validate(criterion, deliveryBody, verification)
            val changed = JSONObject(criterion.toString()).apply { getJSONObject("validator").getJSONArray("cases").getJSONObject(0).put("expected", 999) }
            assertNotNull(runCatching { CollaborationQualifiedValidation.validate(changed, deliveryBody, verification) }.exceptionOrNull())
            groups.remove(group)
            assertNotNull(runCatching { CollaborationToolRuntime.prepare(context, invocation(run, nextBinding, "future")) }.exceptionOrNull())
            assertNotNull(runCatching { CollaborationQualifiedValidation.validate(criterion, deliveryBody, verification) }.exceptionOrNull())
        } finally { groups.remove(group) }
    }
}
