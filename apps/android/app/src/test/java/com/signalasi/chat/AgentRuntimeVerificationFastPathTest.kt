package com.signalasi.chat

import java.io.File
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentRuntimeVerificationFastPathTest {
    @Test
    fun normalExecutionKeepsMutationRecoveryWithoutScanningUnrequestedArtifacts() {
        val policy = AgentOnDeviceRuntimeTools.executionWorkspacePolicy(
            AgentRuntimeVerificationKind.NONE
        )

        assertTrue(policy.workspaceMutationExpected)
        assertFalse(policy.discoverBuildArtifacts)
    }

    @Test
    fun modelCanRequestArtifactDiscoveryWhenTheOutputPathIsUnknown() {
        val policy = AgentOnDeviceRuntimeTools.executionWorkspacePolicy(
            verificationKind = AgentRuntimeVerificationKind.NONE,
            discoverBuildArtifacts = true
        )

        assertTrue(policy.workspaceMutationExpected)
        assertTrue(policy.discoverBuildArtifacts)
    }

    @Test
    fun everyVerificationKindUsesTheFastWorkspacePath() {
        AgentRuntimeVerificationKind.entries
            .filterNot { it == AgentRuntimeVerificationKind.NONE }
            .forEach { kind ->
                val policy = AgentOnDeviceRuntimeTools.executionWorkspacePolicy(kind)

                assertFalse("$kind should not create a mutation checkpoint", policy.workspaceMutationExpected)
                assertFalse("$kind should not scan unrelated build outputs", policy.discoverBuildArtifacts)
            }
    }

    @Test
    fun packageVerificationCanExplicitlyDiscoverAnUnknownOutput() {
        val policy = AgentOnDeviceRuntimeTools.executionWorkspacePolicy(
            verificationKind = AgentRuntimeVerificationKind.PACKAGE,
            discoverBuildArtifacts = true
        )

        assertFalse(policy.workspaceMutationExpected)
        assertTrue(policy.discoverBuildArtifacts)
    }

    @Test
    fun verificationSkipsCheckpointAndStillCollectsExplicitArtifacts() {
        val root = Files.createTempDirectory("signalasi-verification-fast-path-").toFile()
        try {
            val runtimeRoot = File(root, "runtime")
            val projectRoot = File(root, "projects")
            val project = File(projectRoot, "workspace-one").apply { mkdirs() }
            File(project, ".git/info").mkdirs()
            File(project, ".git/HEAD").writeText("ref: refs/heads/main\n")
            File(project, ".git/refs/heads/main").apply {
                parentFile?.mkdirs()
                writeText("0123456789abcdef0123456789abcdef01234567\n")
            }
            val manager = AgentRuntimeWorkspaceManager(
                runtimeRoot = runtimeRoot,
                projectRoot = projectRoot,
                directExecution = true
            )
            val policy = AgentOnDeviceRuntimeTools.executionWorkspacePolicy(
                AgentRuntimeVerificationKind.TEST
            )
            val request = AgentRuntimeExecutionRequest(
                language = AgentRuntimeLanguage.SHELL,
                source = "./gradlew test",
                arguments = emptyList(),
                timeoutMillis = 60_000L,
                networkEnabled = false,
                artifactPaths = listOf("reports/verification.txt"),
                workspaceId = "workspace-one",
                requestId = "verify-one",
                verificationKind = AgentRuntimeVerificationKind.TEST,
                workspaceMutationExpected = policy.workspaceMutationExpected,
                discoverBuildArtifacts = policy.discoverBuildArtifacts
            )

            val prepared = manager.prepare(request)

            assertFalse(File(prepared.metadataDirectory, "git-checkpoint.json").exists())
            assertTrue(prepared.buildArtifactBaseline.isEmpty())
            File(prepared.directory, "reports/verification.txt").apply {
                parentFile?.mkdirs()
                writeText("passed")
            }
            val artifacts = manager.collectArtifacts(prepared, request)
            assertEquals(listOf("reports/verification.txt"), artifacts.map { it["relative_path"] })
        } finally {
            root.deleteRecursively()
        }
    }
}
