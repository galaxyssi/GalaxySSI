package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.HOST
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.objects
import com.galaxyssi.chat.CollaborationEvolutionContract.Companion.text

/** Saved code is a scoped candidate, not a newly privileged native tool or an installed Skill. */
internal object CollaborationExecutableTool {
    const val TOOL = "executable_tool"
    const val TEST = "tool_test_plan"
    const val RELEASE = "tool_release"
    const val RECEIPT = "collaboration_tool_receipt"
    val KINDS = setOf(TOOL, TEST, RELEASE, CollaborationToolComparison.KIND)
    data class ObservedTest(val plan: JSONObject, val tool: JSONObject, val observation: JSONObject,
                            val receipt: JSONObject, val checked: JSONObject)

    fun definition(value: JSONObject): JSONObject {
        listOf("name", "purpose", "applies_when", "avoid_when", "environment", "dependencies", "side_effects", "source")
            .forEach { text(value, it) }
        require(value.optString("language") == "python") { "Executable tools currently support Python run(parameters) -> JSON" }
        val manifest = parameterManifest(value)
        val validation = AgentSkillManifestValidator.validate(manifest, setOf(AgentOnDeviceRuntimeTools.EXECUTE))
        require(validation.isValid) { "Tool input schema: ${validation.issues}" }
        return JSONObject().put("state", "unexecuted_tool_candidate").put("source_sha256", sourceHash(value))
            .put("grants_permissions", false)
    }

    fun testPlan(value: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject): JSONObject {
        val tool = exact(value.getJSONObject(TOOL), setOf(TOOL))
        val spec = tool.getJSONObject("body").getJSONObject(TOOL)
        require(text(value, "environment") == spec.getString("environment")) { "Test environment must match the saved tool" }
        listOf("purpose", "coverage_gaps", "oracle_basis").forEach { text(value, it) }
        val cases = objects(value, "cases")
        require(cases.map { text(it, "id") }.distinct().size == cases.size) { "Test case IDs must be distinct" }
        cases.forEach {
            require(text(it, "purpose") in setOf("target", "edge", "regression")) { "Unknown test case purpose" }
            text(it, "reason")
            parameters(spec, it.getJSONObject("input"))
            require(it.has("expected")) { "Every case needs an explicit expected JSON value, including null" }
        }
        require(cases.any { it.getString("purpose") == "target" } && cases.any { it.getString("purpose") == "regression" }) {
            "Register target and regression coverage; the agent chooses the useful cases, not a fixed case count"
        }
        return JSONObject().put("state", "registered_tool_tests_not_executed").put(TOOL, ref(tool))
    }

    fun release(value: JSONObject, revision: JSONObject, person: String,
                exact: (JSONObject, Set<String>) -> JSONObject, original: (JSONObject) -> JSONObject?,
                coverage: (JSONObject) -> Unit): JSONObject {
        listOf("review", "applies_when", "avoid_when", "limitations", "authorization_boundary").forEach { text(value, it) }
        require(value.getJSONArray("unresolved").length() == 0) { "Resolve tool review blockers before release; keep candidates and failures intact" }
        coverage(revision)
        val tested = observedTest(value, revision, exact, original)
        val plan = tested.plan
        val tool = tested.tool
        require(person != tool.getString("person_id")) { "The code author cannot independently release their own tool" }
        require(tested.observation.getString("status") == "returned" && tested.checked.getBoolean("passed")) {
            "Incomplete or failing tests cannot be released"
        }
        return JSONObject().put("state", "eligible_for_scoped_tool_execution").put(TOOL, ref(tool)).put(TEST, ref(plan))
            .put("observation", value.getJSONObject("observation")).put("checks", tested.checked.getJSONArray("checks"))
            .put("source_sha256", sourceHash(tool.getJSONObject("body").getJSONObject(TOOL)))
            .put("tested_runtime", tested.receipt.getJSONObject("report").getJSONObject("runtime"))
            .put("grants_permissions", false).put("security_certified", false).put("general_correctness_proven", false)
    }

    /** Rechecks complete original reports, including failed cases, without executing a tool again. */
    fun observedTest(value: JSONObject, revision: JSONObject, exact: (JSONObject, Set<String>) -> JSONObject,
                     original: (JSONObject) -> JSONObject?): ObservedTest {
        val plan = exact(value.getJSONObject(TEST), setOf(TEST))
        val tool = exact(plan.getJSONObject("body").getJSONObject(TEST).getJSONObject(TOOL), setOf(TOOL))
        val observations = objects(revision, "host_observations")
        val selected = value.getJSONObject("observation")
        require(observations.any { it.getString("evidence_id") == selected.optString("evidence_id") && it.getString("sha256") == selected.optString("sha256") }) {
            "Cite the original test observation"
        }
        val saved = requireNotNull(original(selected)) { "Tool test observation is unavailable or isolated" }
        require(saved.getString("sha256") == selected.getString("sha256") && saved.getString("status") in setOf("returned", "failed") &&
            saved.getString("observation_kind") == "tool_output_recorded" && saved.getString("origin") == "android_native_tool" &&
            saved.getString("tool") == AgentOnDeviceRuntimeTools.EXECUTE) { "An original native runtime test is required, not a model claim" }
        require(saved.getLong("started_at") >= plan.getLong("recorded_at")) { "Tests must execute after test-plan registration" }
        val output = JSONObject(saved.getString("output_json")).getJSONObject("output")
        val receipt = output.getJSONObject(RECEIPT)
        require(receipt.optString("mode") == "test" &&
            receipt.getInt("exit_code") == 0 && receipt.getString("source_sha256") == sourceHash(tool.getJSONObject("body").getJSONObject(TOOL)) &&
            receipt.getString("run_id") == saved.getString("run_id") && receipt.getString("turn_id") == saved.getString("turn_id") &&
            receipt.getString("person_id") == saved.getString("person_id") &&
            CollaborationResearchCandidates.same(receipt.getJSONObject(TOOL), tool) &&
            CollaborationResearchCandidates.same(receipt.getJSONObject(TEST), plan)) { "Host test receipt version or dispatch mismatch" }
        val compiled = CollaborationToolRuntime.prepare(mapOf(CollaborationToolRuntime.INPUT to mapOf("mode" to "test", TEST to ref(plan).toNativeObject())),
            CollaborationWorkspaceAccess(saved.getString("group_id"), saved.getString("run_id"), saved.getString("turn_id"), saved.getLong("round"),
                saved.getString("node_id"), saved.getString("person_id"))) { reference, kind -> exact(reference, setOf(kind)) }!!
        require(compiled.identity.getString("execution_source_sha256") == receipt.getString("execution_source_sha256")) { "Test harness differs from the saved source and cases" }
        val checked = CollaborationToolRuntime.evaluateTests(plan.getJSONObject("body").getJSONObject(TEST), receipt.getJSONObject("report"))
        require(receipt.opt("passed") is Boolean && receipt.getBoolean("passed") == checked.getBoolean("passed")) {
            "Stored test verdict differs from the original case outputs"
        }
        receipt.optJSONObject("stdout_capture")?.let { capture ->
            require(capture.getLong("original_chars") <= capture.getLong("captured_chars")) { "Original test report was truncated" }
        }
        return ObservedTest(plan, tool, saved, receipt, checked)
    }

    fun parameters(spec: JSONObject, value: JSONObject) {
        val issues = AgentSkillManifestValidator.validateParameters(parameterManifest(spec).parameters, value.toNativeObject())
        require(issues.isEmpty()) { "Tool parameters: $issues" }
    }

    // Reuse the existing strict Skill schema/parser instead of introducing another JSON-schema dialect.
    private fun parameterManifest(spec: JSONObject): AgentSkillManifest = requireNotNull(AgentSkillManifestCodec.fromMap(mapOf(
        "id" to "collaboration.parameter-contract", "version" to "1", "title" to "Tool parameters", "instructions" to "Validate parameters",
        "native_tools" to listOf(AgentOnDeviceRuntimeTools.EXECUTE), "parameters" to spec.getJSONObject("input_schema").toNativeObject(),
        "steps" to listOf(mapOf("id" to "validate", "tool_id" to AgentOnDeviceRuntimeTools.EXECUTE, "input" to emptyMap<String, Any?>()))
    ))) { "Invalid tool input_schema; use the existing Skill parameter schema" }

    fun sourceHash(spec: JSONObject) = AgentNativeJsonCodec.sha256(spec.getString("source"))
    fun ref(record: JSONObject) = CollaborationResearchCandidates.reference(record)
}
