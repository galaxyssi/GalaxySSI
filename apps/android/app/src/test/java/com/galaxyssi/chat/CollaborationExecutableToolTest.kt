package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import com.galaxyssi.chat.CollaborationExecutableTool.TOOL
import com.galaxyssi.chat.CollaborationExecutableTool.TEST
import com.galaxyssi.chat.CollaborationExecutableTool.RELEASE
import com.galaxyssi.chat.CollaborationExecutableTool.RECEIPT
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST

class CollaborationExecutableToolTest {
    internal class Fixture {
        val rows = CollaborationEvolutionTest.Rows()
        val ledger = CollaborationEvidenceLedger(CollaborationEvolutionTest.Rows())
        fun reopen() = CollaborationResearchWorkspace(rows, evidence = ledger::references, evidenceReadCoverage = ledger::requireReadCoverage,
            evidenceOriginal = { a, r -> ledger.read(a, r.getString("evidence_id"), r.getString("sha256")) })
        val workspace = reopen()
        fun access(person: String = "reviewer", round: Long = 5, node: String = person) = CollaborationWorkspaceAccess("group", "run", "turn", round, node, person)
        val spec = JSONObject().put("name", "Stable integer sort").put("purpose", "Sort fixture integers").put("language", "python")
            .put("source", "def run(parameters):\n    return sorted(parameters['values'])\n").put("environment", "python-standard-library")
            .put("dependencies", "Python 3 standard library").put("applies_when", "Integer arrays").put("avoid_when", "Other types")
            .put("side_effects", "None").put("input_schema", JSONObject("""{"type":"object","properties":{"values":{"type":"array","items":{"type":"integer"}}},"required":["values"],"additional_properties":false}"""))
        fun publish(id: String, kind: String, value: JSONObject, person: String, round: Long, observations: JSONArray = JSONArray()): JSONObject {
            val raw = JSONObject().put("format", CollaborationResearchArtifact.FORMAT).put("summary", "Synthetic executable tool")
                .put("findings", JSONArray()).put("candidates", JSONArray()).put("workspace", JSONArray().put(JSONObject().put("id", id)
                    .put("kind", kind).put("title", id).put("body", JSONObject().put("content", "Fixture").put(kind, value)).put("observations", observations)))
            return workspace.publish(access(person, round, id), raw.toString(), round * 10)
        }
        fun ref(value: JSONObject): JSONObject { assertEquals(value.toString(), "recorded", value.getString("status")); return value.getJSONArray("revisions").getJSONObject(0) }
        val tool = ref(publish("sort", TOOL, spec, "author", 1))
        val planSpec = JSONObject().put(TOOL, tool).put("environment", spec.getString("environment")).put("purpose", "Correct integer ordering")
            .put("oracle_basis", "Exact manually specified sorted lists").put("coverage_gaps", "Synthetic lists only")
            .put("cases", JSONArray().put(case("mixed", "target", "[3,1,2]", "[1,2,3]"))
                .put(case("empty", "edge", "[]", "[]")).put(case("duplicates", "regression", "[2,-1,2]", "[-1,2,2]")))
        val plan = ref(publish("tests", TEST, planSpec, "reviewer", 2))
        fun case(id: String, purpose: String, input: String, output: String) = JSONObject().put("id", id).put("purpose", purpose)
            .put("reason", "Check $id").put("input", JSONObject().put("values", JSONArray(input))).put("expected", JSONArray(output))
        fun resolve(ref: JSONObject, kind: String, access: CollaborationWorkspaceAccess = access()): JSONObject {
            val saved = requireNotNull(workspace.read(access, ref.getString("object_id"), ref.getInt("revision")))
            require(saved.getString("kind") == kind && CollaborationResearchCandidates.same(saved, ref))
            return saved
        }
        fun prepare(request: JSONObject, input: Map<String, Any?> = emptyMap(), access: CollaborationWorkspaceAccess = access("tester", 3)) =
            CollaborationToolRuntime.prepare(input + (CollaborationToolRuntime.INPUT to request.toNativeObject()), access) { ref, kind -> resolve(ref, kind, access) }!!
        fun test() = prepare(JSONObject().put("mode", "test").put(TEST, plan))
        fun report() = JSONObject().put("format", CollaborationToolRuntime.FORMAT).put("runtime", runtime()).put("results", JSONArray().apply {
            val cases = planSpec.getJSONArray("cases"); repeat(cases.length()) { i -> val c = cases.getJSONObject(i); put(JSONObject().put("id", c.getString("id")).put("output", c.get("expected"))) }
        })
        fun runtime() = JSONObject().put("python", JSONArray("[3,12,0]")).put("implementation", "cpython").put("machine", "fixture")
        fun finish(prepared: CollaborationToolRuntime.Prepared = test(), report: JSONObject = report(), exit: Int = 0) = CollaborationToolRuntime.finish(prepared,
            AgentRuntimeExecutionResponse(exit, report.toString(), "", 1, requestId = "fixture"), AgentNativeToolExecutionResult.success())
        fun observed(result: AgentNativeToolExecutionResult = finish(), id: String = "test", started: Long = 30, toolId: String = AgentOnDeviceRuntimeTools.EXECUTE): JSONObject =
            ledger.record(access("tester", 3), id, toolId, "{}", JSONObject().put("output", JSONObject(result.output)).toString(), started, started + 1, CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
        fun releaseSpec(observation: JSONObject) = JSONObject().put(TEST, plan).put("observation", observation).put("review", "Source and oracle checked")
            .put("applies_when", "Integer lists").put("avoid_when", "Any I/O").put("limitations", "Fixture only")
            .put("authorization_boundary", "Existing runtime authorization").put("unresolved", JSONArray())
        fun release(observation: JSONObject = observed(), person: String = "reviewer", read: Boolean = true, value: JSONObject = releaseSpec(observation)): JSONObject {
            val a = access(person, 4, "release")
            if (read) { var offset: Int? = 0; while (offset != null) offset = ledger.readPage(a, observation.getString("evidence_id"), observation.getString("sha256"), offset)!!.next }
            return publish("release", RELEASE, value, person, 4, JSONArray().put(observation))
        }
    }

    @Test fun exactCodeTestsAndIndependentReleaseSurviveAnotherTask() {
        val f = Fixture(); val release = f.ref(f.release())
        assertFalse(release.getJSONObject(HOST).getBoolean("automatically_installed"))
        assertFalse(release.getJSONObject(HOST).getBoolean("security_certified"))
        val future = f.access().copy(turnId = "later", runId = "later", round = 0)
        val restored = f.reopen().read(future, release.getString("object_id"), 1)!!
        val prepared = f.prepare(JSONObject().put("mode", "run").put(RELEASE, CollaborationExecutableTool.ref(restored))
            .put("parameters", JSONObject().put("values", JSONArray("[9,4]"))), access = future)
        assertEquals(f.tool.getString("sha256"), prepared.identity.getJSONObject(TOOL).getString("sha256"))
        assertEquals("later", prepared.identity.getString("run_id"))
    }

    @Test fun ordinaryRuntimeInvocationHasNoWorkspaceReads() {
        assertNull(CollaborationToolRuntime.prepare(mapOf("source" to "print(1)"), Fixture().access()) { _, _ -> error("Must not read") })
    }
    @Test fun badSchemaIsNotSilentlyIgnored() {
        val f = Fixture(); f.spec.getJSONObject("input_schema").put("unknown_validator", true)
        reject { CollaborationExecutableTool.definition(f.spec) }
    }
    @Test fun invalidParametersFailBeforeExecution() {
        val f = Fixture(); val release = f.ref(f.release())
        reject { f.prepare(JSONObject().put("mode", "run").put(RELEASE, release).put("parameters", JSONObject().put("values", JSONArray().put("wrong")))) }
    }
    @Test fun additionalParametersCannotLeakIntoCode() {
        val f = Fixture(); reject { CollaborationExecutableTool.parameters(f.spec, JSONObject().put("values", JSONArray()).put("shell", "arbitrary")) }
    }
    @Test fun declaredTestCoverageCannotBeEmptyOrOnlyHappyPath() {
        val f = Fixture(); f.planSpec.put("cases", JSONArray().put(f.case("one", "target", "[1]", "[1]")))
        reject { CollaborationExecutableTool.testPlan(f.planSpec) { ref, kinds -> f.resolve(ref, kinds.single()) } }
    }
    @Test fun releaseCannotBeSelfApproved() {
        val f = Fixture(); assertEquals("rejected", f.release(person = "author").getString("status"))
    }
    @Test fun releaseRequiresFullOriginalRead() {
        val f = Fixture(); assertEquals("rejected", f.release(read = false).getString("status"))
    }
    @Test fun releaseRejectsUnresolvedReview() {
        val f = Fixture(); val observed = f.observed()
        assertEquals("rejected", f.release(observed, value = f.releaseSpec(observed).put("unresolved", JSONArray().put("Unreviewed network side effect"))).getString("status"))
    }
    @Test fun genericToolTextCannotMintExecutableRelease() {
        val f = Fixture(); val fake = f.observed(AgentNativeToolExecutionResult.success(mapOf("stdout" to "all tests passed")))
        assertEquals("rejected", f.release(fake).getString("status"))
    }
    @Test fun wrongToolOrPredatedExecutionCannotRelease() {
        for (old in listOf(true, false)) { val f = Fixture(); val receipt = if (old) f.observed(started = 10) else f.observed(toolId = "fixture")
            assertEquals("rejected", f.release(receipt).getString("status")) }
    }
    @Test fun failedTestRetainsActualAndExpectedAndBlocksRelease() {
        val f = Fixture(); val report = f.report(); report.getJSONArray("results").getJSONObject(0).put("output", JSONArray("[3,1,2]"))
        val result = f.finish(report = report)
        assertFalse(result.isSuccess)
        val receipt = JSONObject(result.output).getJSONObject(RECEIPT)
        assertEquals("[3,1,2]", receipt.getJSONObject("evaluation").getJSONArray("checks").getJSONObject(0).getJSONArray("actual").toString())
        assertEquals("rejected", f.release(f.observed(result)).getString("status"))
    }
    @Test fun missingAndDuplicateResultsAreNotPasses() {
        val f = Fixture(); for (duplicate in listOf(true, false)) { val report = f.report(); val rows = report.getJSONArray("results")
            if (duplicate) rows.put(rows.getJSONObject(0)) else rows.remove(0)
            assertFalse(f.finish(report = report).isSuccess) }
    }
    @Test fun nonzeroExitAndTruncatedJsonAreNotPasses() {
        val f = Fixture(); assertFalse(f.finish(exit = 1).isSuccess)
        assertFalse(CollaborationToolRuntime.finish(f.test(), AgentRuntimeExecutionResponse(0, "{", "", 1), AgentNativeToolExecutionResult.success()).isSuccess)
    }
    @Test fun codeOverridesAndUnregisteredModesAreRejected() {
        val f = Fixture(); for (key in listOf("source", "language", "arguments", "verification_kind", "project_scope", "discover_build_artifacts"))
            reject { f.prepare(JSONObject().put("mode", "test").put(TEST, f.plan), mapOf(key to "override")) }
        reject { f.prepare(JSONObject().put("mode", "install").put(TEST, f.plan)) }
    }
    @Test fun wrongDigestAndOtherGroupCannotLoadCode() {
        val f = Fixture(); reject { f.prepare(JSONObject().put("mode", "test").put(TEST, JSONObject(f.plan.toString()).put("sha256", "bad"))) }
        reject { f.prepare(JSONObject().put("mode", "test").put(TEST, f.plan), access = f.access().copy(groupId = "other")) }
    }
    @Test fun isolatedBranchCannotLoadCurrentTool() {
        val f = Fixture(); reject { f.prepare(JSONObject().put("mode", "test").put(TEST, f.plan), access = f.access("isolated", 1)) }
    }
    @Test fun unreleasedToolCannotBeCalledAsARelease() {
        val f = Fixture(); reject { f.prepare(JSONObject().put("mode", "run").put(RELEASE, f.tool).put("parameters", JSONObject().put("values", JSONArray()))) }
    }
    @Test fun expectedNullAndNumericEqualityAreHandledWithoutTruthiness() {
        val plan = JSONObject().put("cases", JSONArray().put(JSONObject().put("id", "null").put("purpose", "edge").put("expected", JSONObject.NULL)))
        val report = JSONObject().put("format", CollaborationToolRuntime.FORMAT).put("runtime", Fixture().runtime()).put("results", JSONArray().put(JSONObject().put("id", "null").put("output", JSONObject.NULL)))
        assertTrue(CollaborationToolRuntime.evaluateTests(plan, report).getBoolean("passed"))
        report.getJSONArray("results").getJSONObject(0).remove("output")
        assertFalse(CollaborationToolRuntime.evaluateTests(plan, report).getBoolean("passed"))
    }
    @Test fun releaseIsBoundToTestedDispatchAndSource() {
        for (field in listOf("run_id", "turn_id", "person_id")) { val f = Fixture(); val result = f.finish()
            val output = JSONObject(result.output); output.getJSONObject(RECEIPT).put(field, "wrong")
            assertEquals("rejected", f.release(f.observed(result.copy(output = output.toNativeObject()))).getString("status")) }
    }
    @Test fun sourceAndExpectedAnswersAreNotShellInterpolated() {
        val f = Fixture(); val prepared = f.test()
        assertFalse(prepared.source.contains(f.spec.getString("source")))
        assertFalse(prepared.source.contains("['expected']"))
        assertTrue(prepared.source.contains("base64.b64decode"))
    }
    @Test fun changedHarnessOrSourceHashCannotRelease() {
        for (field in listOf("execution_source_sha256", "source_sha256")) { val f = Fixture(); val result = f.finish()
            val output = JSONObject(result.output); output.getJSONObject(RECEIPT).put(field, "changed")
            assertEquals("rejected", f.release(f.observed(result.copy(output = output.toNativeObject()))).getString("status")) }
    }
    @Test fun environmentChangeRequiresNewValidationInsteadOfSilentReuse() {
        val f = Fixture(); val release = f.ref(f.release())
        val prepared = f.prepare(JSONObject().put("mode", "run").put(RELEASE, release).put("parameters", JSONObject().put("values", JSONArray())), access = f.access("worker", 5))
        val report = JSONObject().put("format", CollaborationToolRuntime.FORMAT).put("runtime", f.runtime().put("machine", "changed"))
            .put("results", JSONArray().put(JSONObject().put("id", "run").put("output", JSONArray())))
        val result = f.finish(prepared, report)
        assertFalse(result.isSuccess)
        assertTrue(JSONObject(result.output).getJSONObject(RECEIPT).getJSONObject("evaluation").getString("diagnosis").contains("runtime changed"))
    }
    @Test fun repeatedReceiptDoesNotRequireRepeatingPythonExecution() {
        val f = Fixture(); val observed = f.observed()
        val first = f.release(observed); val second = f.release(observed)
        assertEquals(AgentNativeJsonCodec.sha256(first.toNativeObject()), AgentNativeJsonCodec.sha256(second.toNativeObject()))
    }
    private fun reject(action: () -> Unit) = assertNotNull("Expected rejection", runCatching(action).exceptionOrNull())
}
