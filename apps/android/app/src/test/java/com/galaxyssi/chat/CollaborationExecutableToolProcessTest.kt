package com.galaxyssi.chat

import java.util.concurrent.TimeUnit
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/** Real local Python execution of synthetic code, with no model, network or external side effects. */
class CollaborationExecutableToolProcessTest {
    private fun execute(prepared: CollaborationToolRuntime.Prepared): AgentNativeToolExecutionResult {
        val python = System.getenv("GALAXYSSI_TEST_PYTHON") ?: "python"
        val process = ProcessBuilder(python, "-c", prepared.source).start()
        if (!process.waitFor(15, TimeUnit.SECONDS)) { process.destroyForcibly(); fail("Synthetic Python fixture did not terminate") }
        val response = AgentRuntimeExecutionResponse(process.exitValue(), process.inputStream.bufferedReader().readText(),
            process.errorStream.bufferedReader().readText(), 1, requestId = "local-python-fixture")
        return CollaborationToolRuntime.finish(prepared, response, AgentNativeToolExecutionResult.success())
    }
    @Test fun writeExecuteTestReleaseReopenAndReuseRealPython() {
        val f = CollaborationExecutableToolTest.Fixture()
        val tested = execute(f.test())
        assertTrue(tested.toString(), tested.isSuccess)
        val release = f.ref(f.release(f.observed(tested)))
        val future = f.access().copy(turnId = "new-task", runId = "new-run", round = 0)
        assertNotNull(f.reopen().read(future, release.getString("object_id"), 1))
        val reused = execute(f.prepare(JSONObject().put("mode", "run").put(CollaborationExecutableTool.RELEASE, release)
            .put("parameters", JSONObject().put("values", JSONArray("[42,3,-8,42]"))), access = future))
        assertTrue(reused.toString(), reused.isSuccess)
        assertEquals("[-8,3,42,42]", JSONObject(reused.output).getJSONObject(CollaborationExecutableTool.RECEIPT)
            .getJSONObject("report").getJSONArray("results").getJSONObject(0).getJSONArray("output").toString())
    }
    @Test fun realIncorrectCodeAndExceptionProduceActionableFailures() {
        for (source in listOf("def run(parameters):\n    return parameters['values']", "def run(parameters):\n    raise ValueError('fixture failure')")) {
            val f = CollaborationExecutableToolTest.Fixture()
            val tool = f.ref(f.publish("broken", CollaborationExecutableTool.TOOL, JSONObject(f.spec.toString()).put("source", source), "author", 1))
            val plan = f.ref(f.publish("broken-tests", CollaborationExecutableTool.TEST, JSONObject(f.planSpec.toString()).put(CollaborationExecutableTool.TOOL, tool), "reviewer", 2))
            val result = execute(f.prepare(JSONObject().put("mode", "test").put(CollaborationExecutableTool.TEST, plan)))
            assertFalse(result.isSuccess)
            assertTrue(result.output.containsKey(CollaborationExecutableTool.RECEIPT))
            val diagnostic = JSONObject(result.error!!.details).getJSONArray("problems").getJSONObject(0)
            assertEquals(if (source.contains("raise ValueError")) "case_execution_error" else "value_mismatch", diagnostic.getString("code"))
            assertEquals("mixed", diagnostic.getString("case_id"))
        }
    }
    @Test fun repairedVersionKeepsOriginalExecutedFailure() {
        val f = CollaborationExecutableToolTest.Fixture()
        val broken = f.ref(f.publish("broken-source", CollaborationExecutableTool.TOOL,
            JSONObject(f.spec.toString()).put("source", "def run(parameters):\n    return parameters['values']"), "author", 1))
        val brokenPlan = f.ref(f.publish("broken-plan", CollaborationExecutableTool.TEST,
            JSONObject(f.planSpec.toString()).put(CollaborationExecutableTool.TOOL, broken), "reviewer", 2))
        val failed = execute(f.prepare(JSONObject().put("mode", "test").put(CollaborationExecutableTool.TEST, brokenPlan)))
        assertFalse(failed.isSuccess)
        val original = f.observed(failed, id = "actual-failed-python")
        assertEquals("rejected", f.release(original, value = f.releaseSpec(original).put(CollaborationExecutableTool.TEST, brokenPlan)).getString("status"))
        val fixed = f.ref(f.publish("fixed-source", CollaborationExecutableTool.TOOL, JSONObject(f.spec.toString()), "author", 4))
        val fixedPlan = f.ref(f.publish("fixed-plan", CollaborationExecutableTool.TEST,
            JSONObject(f.planSpec.toString()).put(CollaborationExecutableTool.TOOL, fixed), "reviewer", 5))
        val fixedAccess = f.access("tester", 6)
        val passed = execute(f.prepare(JSONObject().put("mode", "test").put(CollaborationExecutableTool.TEST, fixedPlan), access = fixedAccess))
        assertTrue(passed.toString(), passed.isSuccess)
        val old = f.ledger.read(f.access(), original.getString("evidence_id"), original.getString("sha256"))!!
        val oldReceipt = JSONObject(old.getString("output_json")).getJSONObject("output").getJSONObject(CollaborationExecutableTool.RECEIPT)
        assertFalse(oldReceipt.getBoolean("passed"))
        assertEquals(broken.getString("sha256"), oldReceipt.getJSONObject(CollaborationExecutableTool.TOOL).getString("sha256"))
        assertNotEquals(oldReceipt.getString("source_sha256"), JSONObject(passed.output)
            .getJSONObject(CollaborationExecutableTool.RECEIPT).getString("source_sha256"))
    }
    @Test fun runtimeMismatchStopsBeforeExecutingAnySavedCode() {
        val f = CollaborationExecutableToolTest.Fixture()
        val release = f.ref(f.release()) // Deliberately synthetic runtime identity, unlike this local Python.
        val result = execute(f.prepare(JSONObject().put("mode", "run").put(CollaborationExecutableTool.RELEASE, release)
            .put("parameters", JSONObject().put("values", JSONArray())), access = f.access("worker", 5)))
        assertFalse(result.isSuccess)
        val report = JSONObject(result.output).getJSONObject(CollaborationExecutableTool.RECEIPT).getJSONObject("report")
        assertFalse(report.getBoolean("environment_matches"))
        assertEquals(0, report.getJSONArray("results").length())
    }
}
