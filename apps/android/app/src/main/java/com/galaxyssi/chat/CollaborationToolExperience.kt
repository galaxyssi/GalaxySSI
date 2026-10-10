package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject

/** Version-scoped native observations, including failed requests; never a tool-quality score. */
internal object CollaborationToolExperience {
    private const val PAGE = 20
    private val DIGEST = Regex("[a-f0-9]{64}")

    fun browse(rows: CollaborationWorkspaceRows, prefix: String, access: CollaborationWorkspaceAccess,
               release: JSONObject, cursor: String, read: (String) -> JSONObject?): JSONObject {
        require(reference(release)) { "Tool history requires an exact release reference" }
        val scope = hash(JSONArray().put(access.groupId).put(access.runId).put(access.turnId).put(access.round)
            .put(access.nodeId).put(access.personId).put(JSONArray(access.dependencyNodes.sorted()))
            .put(JSONArray(access.pinnedReads.sorted())).put(release.toString()).toString())
        require(cursor.length <= 512) { "Tool history cursor is too long" }
        val after = if (cursor.isBlank()) "" else {
            val saved = runCatching { JSONObject(cursor) }.getOrElse { throw IllegalArgumentException("Invalid tool history cursor") }
            require(saved.optString("scope") == scope) { "Release or reader changed; restart without cursor" }
            saved.getString("after").also {
                require(it.startsWith(prefix) && it.removePrefix(prefix).matches(DIGEST)) { "Invalid tool history cursor" }
            }
        }
        // Scan existing originals as well as new observations. No migration or unbounded scan on startup.
        val keys = rows.page(prefix, after, PAGE + 1)
        val selected = keys.take(PAGE)
        val records = selected.mapNotNull { key -> read(key.removePrefix(prefix))?.let { describe(it, release) } }
        val next = if (keys.size > selected.size) JSONObject().put("scope", scope).put("after", selected.last()).toString() else null
        return JSONObject().put("method", release).put("records", JSONArray(records))
            .put("record_kind", "original_native_tool_observation").put("next_cursor", next ?: JSONObject.NULL)
            .put("snapshot", false).put("scan_complete", next == null)
            .put("coverage", "visible_saved_native_observations_live_scan")
            .put("quality_effect", JSONObject.NULL).put("causal_contribution", JSONObject.NULL)
            .put("guidance", "Follow next_cursor even after an empty page. Read each read_original selector and all next_offset pages " +
                "for exact inputs, outputs, errors and runtime identity. These are observations, not independent attempts or quality measurements. " +
                "A failed request may precede execution; a replay is not a new execution. A successful run is not correctness. " +
                "Channel requests without a resolved release cannot be attributed here; inspect problems separately. " +
                "No observations means unknown experience, not a reliable or unused tool. Old, isolated or deleted-group evidence is not inferred.")
            .put("trust", "host_execution_observations_not_method_effectiveness")
    }

    fun describe(original: JSONObject, release: JSONObject): JSONObject? {
        if (original.optString("origin") != CollaborationEvidenceOrigin.ANDROID_NATIVE_TOOL.wireValue ||
            original.optString("tool") != AgentOnDeviceRuntimeTools.EXECUTE) return null
        val request = runCatching { JSONObject(original.getString("input_json")) }
            .getOrNull()?.optJSONObject(CollaborationToolRuntime.INPUT) ?: return null
        if (request.optString("mode") != "run") return null
        val output = runCatching { JSONObject(original.getString("output_json")) }.getOrNull() ?: return null
        val runtime = output.optJSONObject("output")?.optJSONObject(CollaborationExecutableTool.RECEIPT)
        val requested = request.optJSONObject(CollaborationExecutableTool.RELEASE)
        val resolved = runtime?.optJSONObject(CollaborationExecutableTool.RELEASE)
        val binding = if (requested != null) {
            if (!same(requested, release) || resolved != null && !same(resolved, release)) return null
            "requested_release"
        } else {
            val channel = request.optJSONObject(CollaborationCapabilityChannel.FIELD) ?: return null
            if (resolved == null || !same(resolved, release) || runtime == null ||
                runtime.optJSONObject(CollaborationCapabilityChannel.FIELD)?.let { same(it, channel) } != true) return null
            "runtime_resolved_channel_release"
        }
        val native = output.optJSONObject("receipt")
        return JSONObject().put("evidence_id", original.getString("evidence_id")).put("sha256", original.getString("sha256"))
            .put("release_binding", binding).put("runtime_report_available", runtime != null)
            .put("read_original", JSONObject().put("mode", "evidence").put("evidence_id", original.getString("evidence_id"))
                .put("sha256", original.getString("sha256")))
            .put("parameters_sha256", request.optJSONObject("parameters")?.let { hash(it.toString()) } ?: JSONObject.NULL)
            .put("native_status", output.opt("status") ?: JSONObject.NULL)
            .put("runtime_reported_passed", runtime?.opt("passed") ?: JSONObject.NULL)
            .put("replayed", native?.opt("replayed") ?: JSONObject.NULL)
            .put("native_invocation_id", native?.opt("invocation_id") ?: JSONObject.NULL)
            .put("original_invocation_id", native?.opt("original_invocation_id") ?: JSONObject.NULL)
            .put("quality_effect", JSONObject.NULL).apply {
                listOf("run_id", "turn_id", "node_id", "person_id", "status", "started_at", "finished_at", "origin")
                    .forEach { put(it, original.get(it)) }
            }
    }

    private fun reference(value: JSONObject) = value.optString("object_id").matches(DIGEST) &&
        value.optString("sha256").matches(DIGEST) && value.opt("revision") is Int && value.getInt("revision") > 0
    private fun same(a: JSONObject, b: JSONObject) = reference(a) && reference(b) &&
        listOf("object_id", "revision", "sha256").all { a.get(it) == b.get(it) }
    private fun hash(value: String) = AgentNativeJsonCodec.sha256(value)
}
