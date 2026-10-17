package com.galaxyssi.chat

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class AgentArtifactFreshnessTest {
    private val path = "outputs/result.csv"
    private val hash = "b".repeat(64)
    private val requirement = AgentArtifactRequirement(path, workspaceId = "scope-a")

    private fun action(tool: String, input: JSONObject = JSONObject().put("path", path),
        output: JSONObject = JSONObject(), status: AgentActionStatus = AgentActionStatus.COMPLETED,
        workspace: String = "scope-a"): AgentAction = AgentAction(
        "action-${java.util.UUID.randomUUID()}", AgentActionKind.CALL_NATIVE_TOOL, tool, AgentRisk.LOW, status,
        "Artifact test", mapOf("tool_id" to tool, "input_json" to input.put("workspace_id", "model-guess").toString()),
        evidence = output.put("workspace_id", workspace).toString())

    private fun export(workspace: String = "scope-a", exportPath: String = path): AgentAction = action(
        AgentPhoneNativeToolCatalog.WORKSPACE_EXPORT, JSONObject().put("path", exportPath),
        JSONObject().put("artifacts", JSONArray().put(JSONObject().put("relative_path", exportPath)
            .put("sha256", hash).put("size_bytes", 20).put("openability", JSONObject()
                .put("status", "verified").put("sha256", hash)))), workspace = workspace)

    private fun missing(vararg history: AgentAction, target: AgentArtifactRequirement = requirement) =
        AgentArtifactCompletionEvidence.missing(listOf(target), history.toList())

    @Test fun laterFailedExportNeverFallsBackToOldSuccess() {
        val failure = action(AgentPhoneNativeToolCatalog.WORKSPACE_EXPORT, status = AgentActionStatus.FAILED)
        assertTrue(missing(export(), failure).single().contains("stale_or_failed"))
        assertTrue(missing(export(), failure, export()).isEmpty())
    }

    @Test fun malformedAndIncompleteExportReceiptsInvalidatePreviousSuccess() {
        for (evidence in listOf("not-json", "{}", "{\"artifacts\":[]}")) {
            assertFalse(missing(export(), export().copy(evidence = evidence)).isEmpty())
        }
    }

    @Test fun writesPatchesAndAppendsRequireFreshExportNotReplay() {
        for (tool in listOf(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT,
            AgentPhoneNativeToolCatalog.WORKSPACE_APPEND_TEXT, AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH,
            AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_BYTES, AgentPhoneNativeToolCatalog.WORKSPACE_CREATE_BYTES)) {
            val mutation = action(tool)
            assertTrue(missing(export(), mutation).single().contains("Do not rerun"))
            assertTrue(missing(export(), mutation, export()).isEmpty())
        }
    }

    @Test fun failedMutationsMayHavePartialEffects() {
        val mutation = action(AgentPhoneNativeToolCatalog.WORKSPACE_APPEND_TEXT, status = AgentActionStatus.FAILED)
        assertFalse(missing(export(), mutation).isEmpty())
    }

    @Test fun directoryMoveAndDeleteInvalidateDescendantsButNotSiblingPrefixes() {
        val delete = action(AgentPhoneNativeToolCatalog.WORKSPACE_DELETE, JSONObject().put("path", "outputs"))
        val move = action(AgentPhoneNativeToolCatalog.WORKSPACE_MOVE,
            JSONObject().put("source_path", "outputs").put("destination_path", "archive"))
        assertFalse(missing(export(), delete).isEmpty())
        assertFalse(missing(export(), move).isEmpty())
        assertTrue(missing(export(), delete.copy(parameters = delete.parameters +
            ("input_json" to JSONObject().put("path", "output").toString()))).isEmpty())
    }

    @Test fun copyOnlyInvalidatesDestination() {
        val copy = action(AgentPhoneNativeToolCatalog.WORKSPACE_COPY,
            JSONObject().put("source_path", path).put("destination_path", "copy.csv"))
        assertTrue(missing(export(), copy).isEmpty())
        assertFalse(missing(export(), action(AgentPhoneNativeToolCatalog.WORKSPACE_COPY,
            JSONObject().put("source_path", "new.csv").put("destination_path", path))).isEmpty())
    }

    @Test fun batchedMutationsInspectEveryPath() {
        for ((tool, key) in listOf(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT_BATCH to "files",
            AgentPhoneNativeToolCatalog.WORKSPACE_APPLY_EXACT_PATCH_BATCH to "patches")) {
            val input = JSONObject().put(key, JSONArray().put(JSONObject().put("path", "unrelated.txt"))
                .put(JSONObject().put("path", path)))
            assertFalse(missing(export(), action(tool, input)).isEmpty())
        }
    }

    @Test fun zipExtractionAndCreationRespectTargetPaths() {
        assertFalse(missing(export(), action(AgentPhoneNativeToolCatalog.WORKSPACE_ZIP_EXTRACT,
            JSONObject().put("archive_path", "source.zip").put("destination_path", "outputs"))).isEmpty())
        assertTrue(missing(export(), action(AgentPhoneNativeToolCatalog.WORKSPACE_ZIP_CREATE,
            JSONObject().put("archive_path", "bundle.zip"))).isEmpty())
    }

    @Test fun unrelatedPathsReadsAndWorkspacesPreserveValidEvidence() {
        val write = action(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT, JSONObject().put("path", "notes.txt"))
        assertTrue(missing(export(), write, action(AgentPhoneNativeToolCatalog.WORKSPACE_READ_TEXT)).isEmpty())
        assertTrue(missing(export(), action(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT, workspace = "scope-b")).isEmpty())
        assertTrue(missing(export(), export(exportPath = "different.csv")).isEmpty())
    }

    @Test fun samePathDifferentWorkspacesRequireExplicitOwnership() {
        assertTrue(missing(export(), export("scope-b"), target = requirement.copy(workspaceId = ""))
            .single().contains("workspace_ambiguous"))
        assertTrue(missing(export(), export("scope-b")).isEmpty())
        assertFalse(missing(export("scope-b")).isEmpty())
    }

    @Test fun modelWorkspaceArgumentCannotSubstituteForReceiptIdentity() {
        val unowned = export().copy(evidence = JSONObject(export().evidence).apply { remove("workspace_id") }.toString())
        assertTrue(missing(unowned).single().contains("workspace_unverified"))
        assertTrue(missing(export()).isEmpty())
    }

    @Test fun conflictingReceiptIdentitiesCannotComplete() {
        val original = export()
        val evidence = JSONObject(original.evidence).put("execution_receipt", JSONObject()
            .put("workspace_id", "scope-b").put("status", "completed"))
        assertTrue(missing(original.copy(evidence = evidence.toString())).single().contains("workspace_mismatch"))
    }

    @Test fun pendingSourceChangeCannotBeSettledByAnExport() {
        for (state in listOf(AgentActionStatus.RUNNING, AgentActionStatus.WAITING_RESPONSE)) {
            assertTrue(missing(action(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT, status = state), export())
                .single().contains("action_pending"))
        }
    }

    @Test fun unexecutedPlansDoNotInvalidateExportsButActualRollbackDoes() {
        for (state in listOf(AgentActionStatus.PROPOSED, AgentActionStatus.PENDING_CONFIRMATION, AgentActionStatus.BLOCKED)) {
            val planned = action(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT, status = state)
            assertTrue(missing(export(), planned).isEmpty())
        }
        val rollback = action(AgentPhoneNativeToolCatalog.WORKSPACE_WRITE_TEXT, status = AgentActionStatus.ROLLED_BACK)
        assertFalse(missing(export(), rollback).isEmpty())
        assertTrue(missing(export(), rollback.copy(parameters = rollback.parameters +
            (SUPERSEDED_SOURCE_STATUS_PARAMETER to AgentActionStatus.PROPOSED.name))).isEmpty())
    }

    @Test fun runtimeFailureOrWorkspaceRestoreCannotReuseOldExport() {
        for (tool in listOf(AgentOnDeviceRuntimeTools.EXECUTE, AgentOnDeviceRuntimeTools.WORKSPACE_ROLLBACK)) {
            assertFalse(missing(export(), action(tool)).isEmpty())
        }
        val noChange = action(AgentOnDeviceRuntimeTools.EXECUTE, output = JSONObject().put("execution_receipt",
            JSONObject().put("status", "completed").put("workspace_disposition", "unchanged")))
        assertTrue(missing(export(), noChange).isEmpty())
    }

    @Test fun wrappedReceiptSuccessAndFailureAreChecked() {
        val original = export()
        fun wrap(status: String, tool: String = original.target) = original.copy(evidence = JSONObject()
            .put("status", status).put("tool_id", tool).put("output", JSONObject(original.evidence)).toString())
        assertTrue(missing(wrap("succeeded")).isEmpty())
        assertFalse(missing(original, wrap("failed")).isEmpty())
        assertFalse(missing(wrap("succeeded", "galaxyssi.other.tool")).isEmpty())
    }

    @Test fun workspaceRequirementRoundTripsAndRejectsInvalidValues() {
        assertEquals(requirement, AgentArtifactRequirement.parse(requirement.toJson()))
        assertNull(AgentArtifactRequirement.parse(requirement.toJson().put("workspace_id", 42)))
        assertNull(AgentArtifactRequirement.parse(requirement.toJson().put("workspace_id", "wrong\nidentity")))
    }

    @Test fun replayedExportCannotProveStateAfterNewWrite() {
        val original = export()
        val mutation = action(AgentPhoneNativeToolCatalog.WORKSPACE_APPEND_TEXT)
        for (replayed in listOf(
            original.copy(evidence = JSONObject(original.evidence).put("_artifact_receipt", JSONObject().put("replayed", true)).toString()),
            original.copy(evidence = JSONObject().put("output", JSONObject(original.evidence))
                .put("receipt", JSONObject().put("replayed", true)).toString()))) {
            assertTrue(missing(original, replayed).isEmpty())
            assertFalse(missing(original, mutation, replayed).isEmpty())
            assertFalse(missing(replayed).isEmpty())
            assertTrue(missing(original, mutation, replayed, export()).isEmpty())
        }
    }

    @Test fun failedNestedRuntimeExitCannotExportCompletionEvidence() {
        val exported = export()
        val output = JSONObject(exported.evidence).put("execution_receipt", JSONObject()
            .put("workspace_id", "scope-a").put("status", "completed").put("exit_code", 1))
        assertFalse(missing(exported.copy(evidence = output.toString())).isEmpty())
    }
}
