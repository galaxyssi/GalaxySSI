package com.galaxyssi.chat

import android.content.Context
import java.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationExecutableTool.TOOL
import com.galaxyssi.chat.CollaborationExecutableTool.TEST
import com.galaxyssi.chat.CollaborationExecutableTool.RELEASE
import com.galaxyssi.chat.CollaborationExecutableTool.RECEIPT

/** Compiles immutable scoped tools into the existing runtime invocation; never bypasses its gate. */
internal object CollaborationToolRuntime {
    const val INPUT = "collaboration_tool"
    const val FORMAT = "galaxyssi.executable-tool-output.v1"
    data class Prepared(val source: String, val identity: JSONObject, val plan: JSONObject?)

    fun prepare(context: Context, call: AgentNativeToolInvocation): Prepared? {
        if (INPUT !in call.input) return null
        val source = requireNotNull(call.context.collaborationSourceMessageId) { "Executable tool requires an exact member dispatch" }
        val access = requireNotNull(CollaborationEvidenceLedger(context).binding(source, call.context.conversationId, call.context.turnId)) {
            "Executable tool dispatch is unavailable"
        }
        val workspace = CollaborationResearchWorkspace(context)
        workspace.requirePublicationActive(access)
        return prepare(call.input, access) { reference, kind ->
            val record = CollaborationRecordValidation.exact(reference, setOf(kind),
                { id, version -> workspace.read(access, id, version) }, { id, version -> workspace.isCurrent(access, id, version) })
            if (kind == CollaborationCapabilityChannel.KIND) CollaborationCapabilityChannel.requireCurrentLineage(record, workspace, access)
            record
        }
    }

    fun prepare(input: Map<String, Any?>, access: CollaborationWorkspaceAccess, exact: (JSONObject, String) -> JSONObject): Prepared? {
        if (INPUT !in input) return null
        require(access.personId.isNotBlank() && access.nodeId.isNotBlank()) { "Executable tool requires a member identity" }
        require(listOf("source", "language", "arguments", "verification_kind", "project_scope", "discover_build_artifacts").none { it in input }) {
            "Do not override saved tool code, arguments or project verification in a collaboration_tool invocation"
        }
        val request = JSONObject(input).getJSONObject(INPUT)
        val mode = request.getString("mode")
        require(mode in setOf("test", "run")) { "Tool mode must be test or run" }
        val identity = JSONObject().put("mode", mode).put("run_id", access.runId).put("turn_id", access.turnId).put("person_id", access.personId)
        val plan: JSONObject?
        val tool: JSONObject
        val cases: JSONArray
        if (mode == "test") {
            require(request.keys().asSequence().toSet() == setOf("mode", TEST)) { "Test accepts only mode and an exact tool_test_plan" }
            plan = exact(request.getJSONObject(TEST), TEST)
            tool = exact(plan.getJSONObject("body").getJSONObject(TEST).getJSONObject(TOOL), TOOL)
            cases = JSONArray(plan.getJSONObject("body").getJSONObject(TEST).getJSONArray("cases").toString())
            identity.put(TEST, CollaborationExecutableTool.ref(plan))
        } else {
            val selected = if (request.has(CollaborationCapabilityChannel.FIELD)) CollaborationCapabilityChannel.FIELD else RELEASE
            require(request.keys().asSequence().toSet() == setOf("mode", selected, "parameters")) { "Run accepts mode, either exact tool_release or capability_channel, and parameters" }
            val channel = if (selected == CollaborationCapabilityChannel.FIELD) exact(request.getJSONObject(selected), selected) else null
            channel?.let { require(it.getJSONObject(HOST).getString("state") == "selected_scoped_version" &&
                it.getJSONObject(HOST).getString("implementation_kind") == RELEASE) { "Channel does not select an approved executable tool" } }
            val release = exact(channel?.getJSONObject(HOST)?.getJSONObject("implementation") ?: request.getJSONObject(RELEASE), RELEASE)
            channel?.let { identity.put(CollaborationCapabilityChannel.FIELD, CollaborationResearchCandidates.reference(it)) }
            require(release.getJSONObject(HOST).getString("state") == "eligible_for_scoped_tool_execution") { "Tool has not passed release review" }
            val registered = exact(release.getJSONObject(HOST).getJSONObject(TEST), TEST)
            tool = exact(release.getJSONObject(HOST).getJSONObject(TOOL), TOOL)
            require(CollaborationResearchCandidates.same(registered.getJSONObject("body").getJSONObject(TEST).getJSONObject(TOOL), tool)) { "Release test/source mismatch" }
            CollaborationExecutableTool.parameters(tool.getJSONObject("body").getJSONObject(TOOL), request.getJSONObject("parameters"))
            cases = JSONArray().put(JSONObject().put("id", "run").put("input", request.getJSONObject("parameters")))
            identity.put(RELEASE, CollaborationExecutableTool.ref(release))
                .put("tested_runtime", release.getJSONObject(HOST).getJSONObject("tested_runtime"))
            plan = null
        }
        val spec = tool.getJSONObject("body").getJSONObject(TOOL)
        identity.put(TOOL, CollaborationExecutableTool.ref(tool)).put("source_sha256", CollaborationExecutableTool.sourceHash(spec))
            .put("environment", spec.getString("environment")).put("grants_permissions", false)
        val payload = JSONObject().put("source", spec.getString("source")).put("cases", JSONArray().apply {
            repeat(cases.length()) { i -> val item = cases.getJSONObject(i); put(JSONObject().put("id", item.getString("id")).put("input", item.getJSONObject("input"))) }
        })
        identity.optJSONObject("tested_runtime")?.let { payload.put("expected_runtime", it) }
        val encoded = Base64.getEncoder().encodeToString(payload.toString().toByteArray(Charsets.UTF_8))
        val program = """
            import base64, contextlib, io, json, platform, sys
            runtime = {'python': list(sys.version_info[:3]), 'implementation': sys.implementation.name, 'machine': platform.machine()}
            payload = json.loads(base64.b64decode('$encoded').decode('utf-8'))
            environment_matches = payload.get('expected_runtime', runtime) == runtime
            results = []
            for case in payload['cases'] if environment_matches else []:
                row = {'id': case['id']}
                try:
                    namespace = {'__name__': 'galaxyssi_generated_tool'}
                    with contextlib.redirect_stdout(io.StringIO()):
                        exec(compile(payload['source'], '<saved-tool>', 'exec'), namespace)
                        output = namespace['run'](case['input'])
                    row['output'] = json.loads(json.dumps(output, allow_nan=False))
                except Exception as error:
                    row['error'] = type(error).__name__ + ': ' + str(error)
                results.append(row)
            print(json.dumps({'format': '$FORMAT', 'runtime': runtime, 'environment_matches': environment_matches, 'results': results}, ensure_ascii=True, allow_nan=False))
        """.trimIndent()
        require(program.toByteArray(Charsets.UTF_8).size <= 256 * 1024) { "Compiled tool exceeds the existing runtime source limit; split the tool or test plan" }
        return Prepared(program, identity.put("execution_source_sha256", AgentNativeJsonCodec.sha256(program)), plan)
    }

    fun finish(prepared: Prepared, response: AgentRuntimeExecutionResponse, result: AgentNativeToolExecutionResult): AgentNativeToolExecutionResult {
        val receipt = JSONObject(prepared.identity.toString()).put("passed", false).put("exit_code", response.exitCode)
            .put("duration_ms", response.durationMillis).put("request_id", response.requestId)
        val parsed = runCatching { CollaborationToolFeedback.parse(response.stdout.trim()) }
        val report = parsed.getOrNull()
        receipt.put("report_parse_status", if (report != null) "parsed_object" else "rejected")
            .put("captured_stdout_sha256", AgentNativeJsonCodec.sha256(response.stdout))
            .put("captured_stderr_sha256", AgentNativeJsonCodec.sha256(response.stderr))
        val capture = JSONObject().put("captured_chars", response.stdout.length)
            .put("original_chars", response.stdoutOriginalChars ?: response.stdout.length)
            .put("limit_chars", response.outputCaptureLimitChars ?: JSONObject.NULL)
        receipt.put("stdout_capture", capture)
        val checked = runCatching {
            CollaborationToolFeedback.require(response.exitCode == 0, "process_exit_nonzero", "/exit_code",
                "Tool process exited unsuccessfully; inspect original stdout and stderr", 0, response.exitCode)
            CollaborationToolFeedback.require((response.stdoutOriginalChars ?: response.stdout.length) <= response.stdout.length,
                "report_stdout_truncated", "/stdout", "Runtime stdout was truncated before validation; the complete tool report is unavailable",
                "complete captured report", capture)
            parsed.getOrThrow()
            CollaborationToolFeedback.require(report?.optString("format") == FORMAT, "report_format_mismatch", "/format",
                "Parsed JSON has an unsupported tool report format", FORMAT, report?.opt("format"))
            if (prepared.plan != null) evaluateTests(prepared.plan.getJSONObject("body").getJSONObject(TEST), report!!) else {
                val expectedRuntime = prepared.identity.getJSONObject("tested_runtime")
                val actualRuntime = report!!.optJSONObject("runtime")
                CollaborationToolFeedback.require(actualRuntime != null && equalJson(expectedRuntime, actualRuntime),
                    "runtime_identity_changed", "/runtime", "Tool runtime changed since validation; create and execute a new test plan before reuse",
                    expectedRuntime, actualRuntime)
                val results = report.optJSONArray("results")
                CollaborationToolFeedback.require(results?.length() == 1 && results.optJSONObject(0)?.opt("id") == "run",
                    "run_result_identity_mismatch", "/results", "Tool run needs exactly one result with id=run", "one run result", results)
                val row = results!!.getJSONObject(0)
                val problem = resultProblem(row, "/results/0")
                JSONObject().put("passed", problem == null).put("problems", JSONArray().apply { problem?.let(::put) })
            }
        }.getOrElse(CollaborationToolFeedback::failed)
        receipt.put("passed", checked.getBoolean("passed")).put("evaluation", checked)
        report?.let { receipt.put("report", it) }
        return result.copy(output = result.output + (RECEIPT to receipt.toNativeObject()), error = result.error ?: if (receipt.getBoolean("passed")) null
            else AgentNativeToolError("collaboration_tool_test_failed", "Saved tool validation failed; inspect structured problems and original checks before choosing a repair, probe or delegation.", details = checked.toNativeObject()))
    }

    fun evaluateTests(plan: JSONObject, report: JSONObject): JSONObject {
        CollaborationToolFeedback.require(report.opt("format") == FORMAT, "report_format_mismatch", "/format",
            "Parsed JSON has an unsupported tool report format", FORMAT, report.opt("format"))
        val runtime = report.optJSONObject("runtime")
        CollaborationToolFeedback.require(runtime?.optJSONArray("python")?.length() == 3 &&
            !runtime.optString("implementation").isNullOrBlank() && !runtime.optString("machine").isNullOrBlank(),
            "runtime_identity_missing", "/runtime", "Parsed JSON is missing the runtime identity", "python[3], implementation, machine", runtime)
        val results = report.optJSONArray("results")
        CollaborationToolFeedback.require(results != null, "case_results_required", "/results", "Parsed JSON requires a results array", "array", report.opt("results"))
        val rows = (0 until results!!.length()).map { index ->
            val row = results.optJSONObject(index)
            CollaborationToolFeedback.require(row?.opt("id") is String && row.optString("id").isNotBlank(),
                "case_id_required", "/results/$index/id", "Each result needs a nonempty string case ID", "string", row?.opt("id"))
            row!!
        }
        val ids = rows.map { it.getString("id") }
        val duplicates = ids.groupingBy { it }.eachCount().filterValues { it > 1 }.keys.sorted()
        CollaborationToolFeedback.require(duplicates.isEmpty(), "duplicate_case_results", "/results", "Duplicate tool case IDs",
            "one result per registered case", JSONArray(duplicates))
        val cases = plan.getJSONArray("cases")
        val expected = (0 until cases.length()).map(cases::getJSONObject)
        val expectedIds = expected.map { it.getString("id") }.toSet()
        CollaborationToolFeedback.require(ids.toSet() == expectedIds, "case_coverage_mismatch", "/results",
            "Missing or unregistered tool case results", JSONArray(expectedIds.sorted()), JSONObject()
                .put("missing", JSONArray((expectedIds - ids.toSet()).sorted())).put("unexpected", JSONArray((ids.toSet() - expectedIds).sorted())))
        val checks = expected.map { case ->
            val index = rows.indexOfFirst { it.getString("id") == case.getString("id") }
            val row = rows[index]
            val path = "/results/$index"
            val problem = resultProblem(row, path) ?: CollaborationToolFeedback.difference(case.get("expected"), row.get("output"), "$path/output")
            problem?.put("case_id", case.getString("id"))
            JSONObject().put("id", case.getString("id")).put("purpose", case.getString("purpose"))
                .put("passed", problem == null).put("actual_present", row.has("output"))
                .put("expected", case.get("expected")).put("actual", row.opt("output") ?: JSONObject.NULL).apply {
                    problem?.let { put("problem", it) }
                    row.optString("error").takeIf(String::isNotEmpty)?.let { put("error", it) }
                }
        }
        return JSONObject().put("passed", checks.all { it.getBoolean("passed") }).put("checks", JSONArray(checks))
            .put("problems", JSONArray(checks.mapNotNull { it.optJSONObject("problem") }))
    }

    private fun resultProblem(row: JSONObject, path: String): JSONObject? = when {
        row.has("error") -> CollaborationToolFeedback.problem("case_execution_error", "$path/error", actual = row.opt("error"))
        !row.has("output") -> CollaborationToolFeedback.problem("case_output_missing", "$path/output", "present including explicit null", "absent")
        else -> null
    }

    private fun equalJson(a: Any, b: Any): Boolean = when {
        a is JSONObject && b is JSONObject -> a.keys().asSequence().toSet() == b.keys().asSequence().toSet() && a.keys().asSequence().all { equalJson(a.get(it), b.get(it)) }
        a is JSONArray && b is JSONArray -> a.length() == b.length() && (0 until a.length()).all { equalJson(a.get(it), b.get(it)) }
        a is Number && b is Number -> a.toString().toBigDecimal().compareTo(b.toString().toBigDecimal()) == 0
        else -> a == b
    }
}
