package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class CollaborationToolFeedbackTest {
    private fun receipt(result: AgentNativeToolExecutionResult) = JSONObject(result.output)
        .getJSONObject(CollaborationExecutableTool.RECEIPT)
    private fun problem(result: AgentNativeToolExecutionResult) = receipt(result)
        .getJSONObject("evaluation").getJSONArray("problems").getJSONObject(0)
    private fun response(stdout: String, exit: Int = 0): AgentNativeToolExecutionResult {
        val f = CollaborationExecutableToolTest.Fixture()
        return CollaborationToolRuntime.finish(f.test(), AgentRuntimeExecutionResponse(exit, stdout, "fixture stderr", 2),
            AgentNativeToolExecutionResult.success(mapOf("stdout" to stdout, "stderr" to "fixture stderr")))
    }

    @Test fun malformedJsonAndValidWrongShapeAreDifferentFacts() {
        val malformed = response("{")
        assertEquals("report_json_unparseable", problem(malformed).getString("code"))
        val array = response("[]")
        assertEquals("report_object_required", problem(array).getString("code"))
        val valid = response("{}")
        assertEquals("parsed_object", receipt(valid).getString("report_parse_status"))
        assertEquals("report_format_mismatch", problem(valid).getString("code"))
        assertEquals("/format", problem(valid).getString("path"))
    }

    @Test fun trailingOutputIsNotSilentlyIgnored() {
        val f = CollaborationExecutableToolTest.Fixture()
        assertEquals("report_trailing_content", problem(response(f.report().toString() + " garbage")).getString("code"))
        assertTrue(response(" \n" + f.report() + "\n ").isSuccess)
    }

    @Test fun processExitKeepsParseStateAndBothOriginalStreams() {
        val f = CollaborationExecutableToolTest.Fixture()
        val text = f.report().toString()
        val result = response(text, 7)
        assertEquals("process_exit_nonzero", problem(result).getString("code"))
        assertEquals(7, problem(result).getInt("actual"))
        assertEquals("parsed_object", receipt(result).getString("report_parse_status"))
        assertEquals(text, result.output["stdout"])
        assertEquals("fixture stderr", result.output["stderr"])
        assertEquals(AgentNativeJsonCodec.sha256(text), receipt(result).getString("captured_stdout_sha256"))
    }

    @Test fun missingRuntimeAndResultsHaveSpecificPaths() {
        val f = CollaborationExecutableToolTest.Fixture()
        val missingRuntime = f.report().apply { remove("runtime") }
        assertEquals("runtime_identity_missing", problem(f.finish(report = missingRuntime)).getString("code"))
        val missingResults = f.report().apply { remove("results") }
        assertEquals("case_results_required", problem(f.finish(report = missingResults)).getString("code"))
    }

    @Test fun captureTruncationIsNotMisreportedAsInvalidJsonOrSuccess() {
        val f = CollaborationExecutableToolTest.Fixture()
        for (stdout in listOf("{", f.report().toString())) {
            val response = AgentRuntimeExecutionResponse(0, stdout, "", 1, stdoutOriginalChars = stdout.length + 10,
                outputCaptureLimitChars = stdout.length)
            val result = CollaborationToolRuntime.finish(f.test(), response, AgentNativeToolExecutionResult.success())
            assertFalse(result.isSuccess)
            assertEquals("report_stdout_truncated", problem(result).getString("code"))
            assertEquals(stdout.length + 10, problem(result).getJSONObject("actual").getInt("original_chars"))
        }
    }

    @Test fun repeatedBoundingRetainsKnownOriginalLengthsAndModelExcerptSignals() {
        val original = AgentRuntimeExecutionResponse(0, "x".repeat(50), "y".repeat(30), 1)
        val bounded = original.boundedOutput(20, 0).boundedOutput(10, 0)
        assertEquals(50, bounded.stdoutOriginalChars)
        assertEquals(30, bounded.stderrOriginalChars)
        assertEquals(10, bounded.stdout.length)
        val visible = AgentOnDeviceRuntimeTools.runtimeExecutionResult(bounded).output
        assertEquals(50, visible["stdout_total_chars"])
        assertEquals(40, visible["stdout_omitted_chars"])
        assertEquals(true, visible["stdout_truncated"])
        assertEquals(30, visible["stderr_total_chars"])
        assertEquals(20, visible["stderr_omitted_chars"])
        assertEquals(10, visible["output_capture_limit_chars"])
    }

    @Test fun parserMessagePreviewCannotDuplicateAnUnboundedOutput() {
        val text = "{" + "bad".repeat(2000)
        val result = response(text)
        val detail = problem(result).getJSONObject("actual")
        assertTrue(detail.getString("parser_message").length <= 256)
        assertEquals(text, result.output["stdout"])
    }

    @Test fun missingAndUnexpectedCasesAreReportedWithoutDroppingOriginals() {
        val f = CollaborationExecutableToolTest.Fixture()
        val report = f.report()
        report.getJSONArray("results").getJSONObject(1).put("id", "not-registered")
        val result = f.finish(report = report)
        val diagnostic = problem(result)
        assertEquals("case_coverage_mismatch", diagnostic.getString("code"))
        assertEquals("[\"empty\"]", diagnostic.getJSONObject("actual").getJSONArray("missing").toString())
        assertEquals("[\"not-registered\"]", diagnostic.getJSONObject("actual").getJSONArray("unexpected").toString())
        assertEquals(report.toString(), receipt(result).getJSONObject("report").toString())
    }

    @Test fun duplicateIdsAndBadIdTypesDoNotBecomeJsonSyntaxErrors() {
        val f = CollaborationExecutableToolTest.Fixture()
        val duplicate = f.report().apply { getJSONArray("results").put(getJSONArray("results").getJSONObject(0)) }
        assertEquals("duplicate_case_results", problem(f.finish(report = duplicate)).getString("code"))
        val badId = f.report().apply { getJSONArray("results").getJSONObject(0).put("id", 42) }
        val problem = problem(f.finish(report = badId))
        assertEquals("case_id_required", problem.getString("code"))
        assertEquals("/results/0/id", problem.getString("path"))
    }

    @Test fun wrongNestedValueHasExactPointerAndRetainsFullValues() {
        val f = CollaborationExecutableToolTest.Fixture()
        val report = f.report().apply { getJSONArray("results").getJSONObject(0).put("output", JSONArray("[1,9,3]")) }
        val result = f.finish(report = report)
        assertEquals("/results/0/output/1", problem(result).getString("path"))
        assertEquals("mixed", problem(result).getString("case_id"))
        assertEquals("value_mismatch", problem(result).getString("code"))
        val check = receipt(result).getJSONObject("evaluation").getJSONArray("checks").getJSONObject(0)
        assertEquals("[1,2,3]", check.getJSONArray("expected").toString())
        assertEquals("[1,9,3]", check.getJSONArray("actual").toString())
    }

    @Test fun arrayCountsAreFactsNotHiddenAcceptanceLimits() {
        val f = CollaborationExecutableToolTest.Fixture()
        val report = f.report().apply { getJSONArray("results").getJSONObject(0).put("output", JSONArray("[1,2,3,4]")) }
        val diagnostic = problem(f.finish(report = report))
        assertEquals("array_length_mismatch", diagnostic.getString("code"))
        assertEquals(3, diagnostic.getInt("expected"))
        assertEquals(4, diagnostic.getInt("actual"))
    }

    @Test fun twelveRegisteredCasesAreAccepted() {
        val f = CollaborationExecutableToolTest.Fixture()
        val cases = JSONArray()
        val results = JSONArray()
        repeat(12) { i ->
            cases.put(JSONObject().put("id", "case-$i").put("purpose", "target").put("expected", i))
            results.put(JSONObject().put("id", "case-$i").put("output", i))
        }
        val checked = CollaborationToolRuntime.evaluateTests(JSONObject().put("cases", cases), f.report().put("results", results))
        assertTrue(checked.getBoolean("passed"))
        assertEquals(12, checked.getJSONArray("checks").length())
        assertEquals(0, checked.getJSONArray("problems").length())
    }

    @Test fun nullOutputIsNotConfusedWithMissingOutput() {
        val f = CollaborationExecutableToolTest.Fixture()
        val report = f.report().apply { getJSONArray("results").getJSONObject(0).remove("output") }
        assertEquals("case_output_missing", problem(f.finish(report = report)).getString("code"))
        report.getJSONArray("results").getJSONObject(0).put("output", JSONObject.NULL)
        assertEquals("type_mismatch", problem(f.finish(report = report)).getString("code"))
    }

    @Test fun executionErrorIsPreservedRatherThanMisdiagnosedAsWrongValue() {
        val f = CollaborationExecutableToolTest.Fixture()
        val report = f.report().apply { getJSONArray("results").getJSONObject(0).put("error", "ValueError: negative length") }
        val diagnostic = problem(f.finish(report = report))
        assertEquals("case_execution_error", diagnostic.getString("code"))
        assertEquals("ValueError: negative length", diagnostic.getString("actual"))
        assertEquals("not_diagnosed", diagnostic.getString("cause"))
    }

    @Test fun pointerEscapesKeysAndKeepsNumericEquality() {
        val expected = JSONObject().put("a/b~c", JSONArray().put(JSONObject().put("x", 1)))
        val actual = JSONObject().put("a/b~c", JSONArray().put(JSONObject().put("x", "1")))
        assertEquals("/a~1b~0c/0/x", CollaborationToolFeedback.difference(expected, actual)!!.getString("path"))
        assertNull(CollaborationToolFeedback.difference(1, 1.0))
        assertEquals("missing_key", CollaborationToolFeedback.difference(expected, JSONObject())!!.getString("code"))
        assertEquals("unexpected_key", CollaborationToolFeedback.difference(JSONObject(), actual)!!.getString("code"))
    }

    @Test fun existingRuntimeFailureIsNotOverwritten() {
        val f = CollaborationExecutableToolTest.Fixture()
        val original = AgentNativeToolError("runtime_disconnected", "Connection lost", true)
        val result = CollaborationToolRuntime.finish(f.test(), AgentRuntimeExecutionResponse(1, "{", "", 1),
            AgentNativeToolExecutionResult(error = original))
        assertEquals(original, result.error)
        assertEquals("process_exit_nonzero", problem(result).getString("code"))
    }

    @Test fun failedObservationRetainsFactsAcrossReopenWithoutInventingCause() {
        val f = CollaborationExecutableToolTest.Fixture()
        val result = f.finish(report = f.report().apply { getJSONArray("results").getJSONObject(0).remove("output") })
        val error = result.error!!
        val original = JSONObject().put("output", JSONObject(result.output)).put("error", JSONObject()
            .put("code", error.code).put("details", JSONObject(error.details))).toString()
        val rows = CollaborationEvolutionTest.Rows()
        val first = CollaborationEvidenceLedger(rows)
        val saved = first.record(f.access(), "failed-tool", AgentOnDeviceRuntimeTools.EXECUTE, "{}", original, 30, 31,
            CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL)
        val reopened = CollaborationEvidenceLedger(rows)
        val recalled = reopened.problems(f.access()).first.single()
        assertEquals(saved.getString("sha256"), recalled.getString("sha256"))
        assertEquals(original, reopened.read(f.access(), saved.getString("evidence_id"))!!.getString("output_json"))
        val host = recalled.getJSONObject("host_problem")
        assertEquals("not_diagnosed", host.getString("cause"))
        assertFalse(host.getBoolean("resolved"))
        assertTrue(host.getJSONArray("signals").toString().contains("case_output_missing"))
    }
}
