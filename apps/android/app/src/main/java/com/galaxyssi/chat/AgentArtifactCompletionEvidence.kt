package com.galaxyssi.chat

import org.json.JSONObject

/** Checks exported tool receipts, never a model's claim that a file exists. */
internal object AgentArtifactCompletionEvidence {
    fun missing(requirements: List<AgentArtifactRequirement>, history: List<AgentAction>): List<String> {
        if (requirements.isEmpty()) return emptyList()
        val observations = history.filter { it.kind == AgentActionKind.CALL_NATIVE_TOOL && !undispatched(it) }
            .map(::Observation)
        return requirements.mapNotNull { requirement ->
            val relevant = observations.filter { it.affects(requirement.path) }
            val scopes = relevant.filter { it.isExportFor(requirement.path) }.map { it.workspace }.filter(String::isNotBlank).distinct()
            if (requirement.workspaceId.isBlank() && scopes.size > 1) return@mapNotNull (
                "artifact_workspace_ambiguous: ${requirement.path} has receipts from multiple workspaces; " +
                    "bind completion_requirements.artifacts[].workspace_id to the observed workspace for this goal, not a guessed model input"
                )
            val workspace = requirement.workspaceId.ifBlank { scopes.singleOrNull().orEmpty() }
            val scoped = relevant.filter { it.workspace.isBlank() || workspace.isBlank() || it.workspace == workspace }
            // A newer export cannot settle an operation that is still capable of changing the source.
            val pending = scoped.lastOrNull { it.action.status in setOf(AgentActionStatus.RUNNING, AgentActionStatus.WAITING_RESPONSE) }
            if (pending != null) return@mapNotNull pending.failure(requirement.path, "artifact_action_pending")
            // Cached effect receipts acknowledge old work; they are not a fresh inspection after later edits.
            val latest = scoped.lastOrNull { !it.replayed || it.action.status != AgentActionStatus.COMPLETED }
            if (latest != null && (!latest.isExportFor(requirement.path) || !latest.succeeded()))
                return@mapNotNull latest.failure(requirement.path, "artifact_export_stale_or_failed")
            if (latest != null && workspace.isNotBlank() && latest.workspace != workspace)
                return@mapNotNull latest.failure(requirement.path, "artifact_workspace_unverified")
            if (latest?.workspaceConflict == true)
                return@mapNotNull latest.failure(requirement.path, "artifact_workspace_mismatch")
            val artifact = latest?.artifact(requirement.path)
            val digest = artifact?.optString("sha256").orEmpty()
            val inspection = artifact?.optJSONObject("openability")
            when {
                artifact == null || !digest.matches(Regex("[a-fA-F0-9]{64}")) || artifact.optLong("size_bytes", -1) < 0 ->
                    "an exported, hash-verified artifact receipt for ${requirement.path}; export this file individually if it was bundled in an archive"
                requirement.sourceSha256.isNotBlank() && digest.equals(requirement.sourceSha256, ignoreCase = true) ->
                    "${requirement.path} is unchanged from the declared pre-edit source; copying the original does not satisfy a requested transformation. " +
                        "source_sha256 is not an output checksum. If the user requested a new file or unchanged download and you mistakenly declared its output hash as the source, " +
                        "correct source_sha256 to empty with an explicit completion_requirements.reason. Otherwise perform and verify the requested edit. Never change correct content just to produce a different hash."
                inspection?.optString("status") != "verified" || !digest.equals(inspection?.optString("sha256"), ignoreCase = true) ->
                    "a host-owned, hash-bound openability check for ${requirement.path}; inspect or repair the file and export again. " +
                        "Current observation: ${inspection?.optString("detail").orEmpty().take(240)}"
                else -> null
            }
        }
    }

    private fun undispatched(action: AgentAction): Boolean =
        action.status in setOf(AgentActionStatus.PROPOSED, AgentActionStatus.PENDING_CONFIRMATION, AgentActionStatus.BLOCKED) ||
            action.status == AgentActionStatus.ROLLED_BACK && action.parameters[SUPERSEDED_SOURCE_STATUS_PARAMETER] in
                setOf(AgentActionStatus.PROPOSED.name, AgentActionStatus.PENDING_CONFIRMATION.name)

    private class Observation(val action: AgentAction) {
        val tool = action.parameters["tool_id"].orEmpty().ifBlank { action.target }
        val input = runCatching { JSONObject(action.parameters["input_json"].orEmpty()) }.getOrNull()
        val raw = runCatching { JSONObject(action.evidence) }.getOrNull()
        val output = raw?.optJSONObject("output") ?: raw
        private val execution = output?.optJSONObject("execution_receipt")
        val replayed = raw?.optBoolean("replayed") == true || raw?.optJSONObject("receipt")?.optBoolean("replayed") == true ||
            output?.optJSONObject("_artifact_receipt")?.optBoolean("replayed") == true
        private val outputWorkspace = output?.optString("workspace_id").orEmpty()
        private val executionWorkspace = execution?.optString("workspace_id").orEmpty()
        // Tool inputs are model-authored and may be rebound by the host. Only receipts establish ownership.
        val workspace = outputWorkspace.ifBlank { executionWorkspace }
        val workspaceConflict = outputWorkspace.isNotBlank() && executionWorkspace.isNotBlank() && outputWorkspace != executionWorkspace

        fun artifact(path: String): JSONObject? {
            val artifacts = output?.optJSONArray("artifacts") ?: return null
            return (0 until artifacts.length()).mapNotNull(artifacts::optJSONObject)
                .lastOrNull { it.optString("relative_path") == path }
        }

        fun isExportFor(path: String): Boolean = artifact(path) != null ||
            tool == AgentPhoneNativeToolCatalog.WORKSPACE_EXPORT && input?.optString("path") == path ||
            tool == AgentOnDeviceRuntimeTools.EXECUTE && input?.optJSONArray("artifact_paths")?.let { paths ->
                (0 until paths.length()).any { paths.optString(it) == path }
            } == true

        fun affects(path: String): Boolean {
            if (isExportFor(path)) return true
            if (tool == AgentOnDeviceRuntimeTools.EXECUTE) {
                // Arbitrary programs can write paths not listed as outputs. A host-confirmed no-change receipt is safe.
                return !(succeeded() && execution?.optString("workspace_disposition") == "unchanged")
            }
            if (tool == AgentOnDeviceRuntimeTools.WORKSPACE_ROLLBACK) return true
            if (tool == AgentPhoneNativeToolCatalog.WORKSPACE_EXPORT) return input?.optString("path").isNullOrBlank()
            if (tool !in mutations) return false
            val paths = when (tool) {
                AgentPhoneNativeToolCatalog.WORKSPACE_MOVE -> fields("source_path", "destination_path")
                AgentPhoneNativeToolCatalog.WORKSPACE_COPY, AgentPhoneNativeToolCatalog.WORKSPACE_ZIP_EXTRACT -> fields("destination_path")
                AgentPhoneNativeToolCatalog.WORKSPACE_ZIP_CREATE -> fields("archive_path")
                AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT_BATCH -> batchPaths("files")
                AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH_BATCH -> batchPaths("patches")
                else -> fields("path")
            }
            return paths.isEmpty() || paths.any { it.isBlank() || path == it || path.startsWith("${it.trimEnd('/')}/") }
        }

        private fun fields(vararg keys: String) = keys.mapNotNull { key -> input?.opt(key) as? String }
        private fun batchPaths(key: String): List<String> {
            val items = input?.optJSONArray(key) ?: return emptyList()
            return (0 until items.length()).map { items.optJSONObject(it)?.optString("path").orEmpty() }
        }

        fun succeeded(): Boolean = action.status == AgentActionStatus.COMPLETED && raw != null &&
            (!raw.has("output") || (!raw.has("status") || raw.optString("status") == "succeeded") &&
                (!raw.has("tool_id") || raw.optString("tool_id") == tool)) &&
            (raw.optJSONObject("receipt")?.let { !it.has("status") || it.optString("status") == "succeeded" } != false) &&
            (output?.let { !it.has("exit_code") || it.optInt("exit_code", -1) == 0 } == true) &&
            (tool != AgentOnDeviceRuntimeTools.EXECUTE || output?.has("status") != true || output.optString("status") == "completed") &&
            (execution?.let { (!it.has("status") || it.optString("status") == "completed") &&
                (!it.has("exit_code") || it.optInt("exit_code", -1) == 0) } != false)

        fun failure(path: String, code: String): String = "$code: $path; action_id=${action.id}; tool_id=$tool; " +
            "inspect the latest operation and file state, then export and verify the requested file again when settled. " +
            "Do not rerun a write, move, delete or program merely to manufacture completion evidence."
    }

    private val mutations = setOf(
        AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT, AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT_BATCH,
        AgentPhoneNativeToolCatalog.WORKSPACE_CREATE_TEXT, AgentPhoneNativeToolCatalog.WORKSPACE_APPEND_TEXT,
        AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_BYTES, AgentPhoneNativeToolCatalog.WORKSPACE_CREATE_BYTES,
        AgentPhoneNativeToolCatalog.WORKSPACE_APPEND_BYTES, AgentPhoneNativeToolCatalog.WORKSPACE_MOVE,
        AgentPhoneNativeToolCatalog.WORKSPACE_COPY, AgentPhoneNativeToolCatalog.WORKSPACE_DELETE,
        AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH, AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH_BATCH,
        AgentPhoneNativeToolCatalog.WORKSPACE_ZIP_CREATE, AgentPhoneNativeToolCatalog.WORKSPACE_ZIP_EXTRACT
    )
}
