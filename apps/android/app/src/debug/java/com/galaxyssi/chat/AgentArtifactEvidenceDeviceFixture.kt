package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import java.nio.file.Files
import java.nio.file.Path
import java.util.Comparator
import java.util.UUID

/** Real native file operations in an isolated temporary root, never user workspaces or model calls. */
internal object AgentArtifactEvidenceDeviceFixture {
    fun run(parent: Path): JSONObject {
        val root = Files.createTempDirectory(parent, "artifact-evidence-")
        try {
            val registry = AgentPhoneNativeToolCatalog.createRegistry(
                workspaceFileTools = AgentWorkspaceFileTools(root),
                actionExecutor = object : AgentActionExecutor {
                    override fun execute(action: AgentAction, screen: ScreenContext): AgentActionResult =
                        error("Device actions are not allowed in this file fixture")
                }, screenProvider = { ScreenContext("GalaxySSI", pageTitle = "File fixture") })
            val path = "outputs/example.csv"
            val target = AgentArtifactRequirement(path, workspaceId = "fixture-a")
            val actions = mutableListOf<AgentAction>()
            val cases = mutableListOf<String>()
            var calls = 0
            fun invoke(tool: String, input: Map<String, Any?>, scope: String = "fixture-a"): AgentAction {
                val arguments = input + ("workspace_id" to scope)
                val descriptor = requireNotNull(registry.lookup(tool)).descriptor
                val result = registry.invoke(tool, arguments, AgentNativeToolInvocationContext(
                    idempotencyKey = UUID.randomUUID().toString(),
                    grantedPermissions = descriptor.requiredPermissions.mapTo(linkedSetOf()) { it.id },
                    grantedConsents = descriptor.requiredConsents.mapTo(linkedSetOf()) { it.id }))
                calls++
                check(result.output["workspace_id"] == scope)
                return AgentAction("fixture-$calls", AgentActionKind.CALL_NATIVE_TOOL, tool, AgentRisk.LOW,
                    if (result.isSuccess) AgentActionStatus.COMPLETED else AgentActionStatus.FAILED,
                    "Isolated file fixture", mapOf("tool_id" to tool, "input_json" to JSONObject(arguments).toString()),
                    evidence = result.toJson()).also(actions::add)
            }
            fun export() = invoke(AgentPhoneNativeToolCatalog.WORKSPACE_EXPORT, mapOf("path" to path))
            fun missing() = AgentArtifactCompletionEvidence.missing(listOf(target), actions)
            invoke(AgentPhoneNativeToolCatalog.WORKSPACE_INITIALIZE, emptyMap())
            invoke(AgentPhoneNativeToolCatalog.WORKSPACE_CREATE_TEXT,
                mapOf("path" to path, "text" to "item,total\napple,6\n", "create_parents" to true))
            val first = export()
            check(missing().isEmpty())
            cases += "real_export_and_openability_accepted"
            invoke(AgentPhoneNativeToolCatalog.WORKSPACE_APPEND_TEXT, mapOf("path" to path, "text" to "pear,8\n"))
            check(missing().isNotEmpty())
            cases += "real_append_invalidates_old_export"
            val second = export()
            check(missing().isEmpty())
            fun hash(action: AgentAction) = JSONObject(action.evidence).getJSONObject("output")
                .getJSONArray("artifacts").getJSONObject(0).getString("sha256")
            check(hash(first) != hash(second))
            cases += "fresh_export_captures_changed_bytes"
            invoke(AgentPhoneNativeToolCatalog.WORKSPACE_DELETE, mapOf("path" to path))
            check(missing().isNotEmpty())
            val failure = export()
            check(failure.status == AgentActionStatus.FAILED && missing().isNotEmpty())
            cases += "real_missing_file_export_cannot_reuse_success"
            invoke(AgentPhoneNativeToolCatalog.WORKSPACE_CREATE_TEXT,
                mapOf("path" to path, "text" to "item,total\napple,6\npear,8\n", "create_parents" to true))
            export()
            check(missing().isEmpty())
            cases += "restored_file_requires_fresh_export"
            invoke(AgentPhoneNativeToolCatalog.WORKSPACE_INITIALIZE, emptyMap(), "fixture-b")
            invoke(AgentPhoneNativeToolCatalog.WORKSPACE_CREATE_TEXT,
                mapOf("path" to path, "text" to "different,workspace\n", "create_parents" to true), "fixture-b")
            invoke(AgentPhoneNativeToolCatalog.WORKSPACE_EXPORT, mapOf("path" to path), "fixture-b")
            check(missing().isEmpty())
            check(AgentArtifactCompletionEvidence.missing(listOf(target.copy(workspaceId = "")), actions)
                .single().contains("workspace_ambiguous"))
            cases += "same_path_workspaces_remain_separate"
            return JSONObject().put("passed", true).put("cases", JSONArray(cases)).put("native_calls", calls)
                .put("model_calls", 0).put("isolated_temporary_files", true)
                .put("initial_sha256", hash(first)).put("updated_sha256", hash(second))
        } finally {
            check(root.toAbsolutePath().normalize().startsWith(parent.toAbsolutePath().normalize()))
            Files.walk(root).use { paths -> paths.sorted(Comparator.reverseOrder()).forEach { Files.deleteIfExists(it) } }
        }
    }
}
