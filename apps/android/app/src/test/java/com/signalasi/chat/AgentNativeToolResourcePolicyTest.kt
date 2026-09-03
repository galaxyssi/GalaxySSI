package com.signalasi.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentNativeToolResourcePolicyTest {
    @Test
    fun siblingFileMutationsDoNotConflict() {
        val left = filePlan("workspace", "src/left.kt")
        val right = filePlan("workspace", "src/right.kt")

        assertTrue(left.resourceScoped)
        assertFalse(left.conflictsWith(right))
    }

    @Test
    fun sameAndNestedPathsConflict() {
        val same = filePlan("workspace", "src/main.kt")
        val duplicate = filePlan("workspace", "src/main.kt")
        val parent = filePlan("workspace", "src")

        assertTrue(same.conflictsWith(duplicate))
        assertTrue(parent.conflictsWith(same))
        assertTrue(same.conflictsWith(parent))
    }

    @Test
    fun workspaceWideMutationConflictsOnlyInsideItsWorkspace() {
        val workspaceOperation = workspacePlan("workspace")
        val sameWorkspaceFile = filePlan("workspace", "README.md")
        val isolatedWorkspaceFile = filePlan("other-worktree", "README.md")

        assertTrue(workspaceOperation.conflictsWith(sameWorkspaceFile))
        assertFalse(workspaceOperation.conflictsWith(isolatedWorkspaceFile))
    }

    @Test
    fun finalVerificationUsesExclusiveGlobalLock() {
        val verification = AgentNativeToolResourcePolicy.resolve(
            descriptor = runtimeDescriptor,
            input = mapOf(
                "workspace_id" to "workspace",
                "verification_kind" to "test"
            )
        )
        val isolatedWorkspace = workspacePlan("other-worktree")

        assertFalse(verification.resourceScoped)
        assertTrue(verification.conflictsWith(isolatedWorkspace))
    }

    @Test
    fun commitUsesExclusiveGlobalLockAcrossWorktrees() {
        val commit = AgentNativeToolResourcePolicy.resolve(
            descriptor = descriptor(
                AgentMobileProjectNativeTools.COMMIT,
                setOf("project.android_local", "project.git")
            ),
            input = mapOf("workspace_id" to "workspace")
        )

        assertFalse(commit.resourceScoped)
        assertTrue(commit.conflictsWith(workspacePlan("other-worktree")))
    }

    private fun filePlan(workspaceId: String, path: String) =
        AgentNativeToolResourcePolicy.resolve(
            descriptor = fileDescriptor,
            input = mapOf("workspace_id" to workspaceId, "path" to path)
        )

    private fun workspacePlan(workspaceId: String) =
        AgentNativeToolResourcePolicy.resolve(
            descriptor = runtimeDescriptor,
            input = mapOf("workspace_id" to workspaceId)
        )

    private val fileDescriptor = descriptor(
        id = "test.workspace.write",
        capabilities = setOf("workspace.file.bounded")
    )
    private val runtimeDescriptor = descriptor(
        id = "test.runtime.execute",
        capabilities = setOf("runtime.android_local")
    )

    private fun descriptor(
        id: String,
        capabilities: Set<String>
    ) = AgentNativeToolDescriptor(
        id = id,
        version = "1.0.0",
        title = id,
        description = "$id test tool",
        location = AgentNativeToolLocation.APPLICATION,
        inputSchema = AgentNativeJsonSchema.objectSchema(),
        outputSchema = AgentNativeJsonSchema.objectSchema(),
        risk = AgentNativeToolRisk.LOW,
        capabilities = capabilities,
        idempotency = AgentNativeToolIdempotency.IDEMPOTENT,
        concurrency = AgentNativeToolConcurrency.SERIAL
    )
}
