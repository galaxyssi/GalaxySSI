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
        }
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
