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
            require(reference.opt("revision") is Int) { "Copy an exact integer revision" }
            val record = requireNotNull(workspace.read(access, reference.getString("object_id"), reference.getInt("revision"))) { "Tool record is unavailable or isolated" }
            require(record.getString("kind") == kind && CollaborationResearchCandidates.same(record, reference) &&
                workspace.isCurrent(access, reference.getString("object_id"), reference.getInt("revision"))) { "Tool version, digest or kind changed" }
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
            require(request.keys().asSequence().toSet() == setOf("mode", RELEASE, "parameters")) { "Run accepts only mode, tool_release and parameters" }
            val release = exact(request.getJSONObject(RELEASE), RELEASE)
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
        val report = runCatching { JSONObject(response.stdout.trim()) }.getOrNull()
        val checked = runCatching {
            require(response.exitCode == 0 && report?.optString("format") == FORMAT) { "Tool did not return a complete JSON result" }
            if (prepared.plan != null) evaluateTests(prepared.plan.getJSONObject("body").getJSONObject(TEST), report!!) else {
                require(equalJson(prepared.identity.getJSONObject("tested_runtime"), report!!.getJSONObject("runtime"))) {
                    "Tool runtime changed since validation; create and execute a new test plan before reuse"
                }
                val results = report!!.getJSONArray("results")
                require(results.length() == 1 && results.getJSONObject(0).getString("id") == "run") { "Tool run output is incomplete" }
                JSONObject().put("passed", results.getJSONObject(0).has("output") && !results.getJSONObject(0).has("error"))
            }
        }.getOrElse { JSONObject().put("passed", false).put("diagnosis", it.message ?: "Invalid tool output") }
        receipt.put("passed", checked.getBoolean("passed")).put("evaluation", checked)
        report?.let { receipt.put("report", it) }
        return result.copy(output = result.output + (RECEIPT to receipt.toNativeObject()), error = result.error ?: if (receipt.getBoolean("passed")) null
            else AgentNativeToolError("collaboration_tool_test_failed", "Saved tool failed or returned incomplete output; inspect retained checks and correct the code or test plan.", details = checked.toNativeObject()))
    }

    fun evaluateTests(plan: JSONObject, report: JSONObject): JSONObject {
        require(report.getString("format") == FORMAT) { "Unknown tool report format" }
        val runtime = report.getJSONObject("runtime")
        require(runtime.getJSONArray("python").length() == 3 && runtime.getString("implementation").isNotBlank() && runtime.getString("machine").isNotBlank()) { "Missing runtime identity" }
        val results = report.getJSONArray("results")
        val rows = (0 until results.length()).map(results::getJSONObject)
        require(rows.map { it.getString("id") }.distinct().size == rows.size) { "Duplicate tool case results" }
        val cases = plan.getJSONArray("cases")
        val expected = (0 until cases.length()).map(cases::getJSONObject)
        require(rows.map { it.getString("id") }.toSet() == expected.map { it.getString("id") }.toSet()) { "Missing or unregistered tool case results" }
        val checks = expected.map { case ->
            val row = rows.single { it.getString("id") == case.getString("id") }
            JSONObject().put("id", case.getString("id")).put("purpose", case.getString("purpose"))
                .put("passed", !row.has("error") && row.has("output") && equalJson(row.get("output"), case.get("expected")))
                .put("expected", case.get("expected")).put("actual", row.opt("output") ?: JSONObject.NULL).apply { row.optString("error").takeIf(String::isNotEmpty)?.let { put("error", it) } }
        }
        return JSONObject().put("passed", checks.all { it.getBoolean("passed") }).put("checks", JSONArray(checks))
    }

    private fun equalJson(a: Any, b: Any): Boolean = when {
        a is JSONObject && b is JSONObject -> a.keys().asSequence().toSet() == b.keys().asSequence().toSet() && a.keys().asSequence().all { equalJson(a.get(it), b.get(it)) }
        a is JSONArray && b is JSONArray -> a.length() == b.length() && (0 until a.length()).all { equalJson(a.get(it), b.get(it)) }
        a is Number && b is Number -> a.toString().toBigDecimal().compareTo(b.toString().toBigDecimal()) == 0
        else -> a == b
    }
}
